import AppKit
import EventKit
import Foundation
import OSLog

@MainActor
public final class MenuBarController: NSObject, NSApplicationDelegate {
    private enum AccessKind: Hashable {
        case calendar
        case reminders

        var label: String {
            switch self {
            case .calendar: return "Calendar"
            case .reminders: return "Reminders"
            }
        }

        var settingsURL: URL? {
            let privacyArea: String
            switch self {
            case .calendar: privacyArea = "Privacy_Calendars"
            case .reminders: privacyArea = "Privacy_Reminders"
            }
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(privacyArea)")
        }
    }

    private let calendar = CalendarStore()
    private let reminders = ReminderStore()
    private let logger = Logger(subsystem: "com.icloudbridge.app", category: "menu-bar")
    private var statusItem: NSStatusItem!
    private var permissionWindow: NSWindow?
    private var mcpBroker: LocalMCPBroker?
    private var statusMenuItems: [AccessKind: NSMenuItem] = [:]
    private var requestAccessMenuItem: NSMenuItem?
    private var requestAccessSeparator: NSMenuItem?
    private var quitMenuItem: NSMenuItem!
    private var pendingAccessKinds: [AccessKind] = []
    private var isRequestingAccess: AccessKind?
    private var accessPollTimer: Timer?
    private let statusMenu = NSMenu()

    public func run() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.delegate = self
        application.run()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "iCloud"

        addStatusItem(for: .calendar)
        addStatusItem(for: .reminders)
        quitMenuItem = addActionItem(title: "Quit iCloud Bridge", action: #selector(quit), keyEquivalent: "q")
        statusItem.menu = statusMenu
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(eventStoreChanged),
            name: .EKEventStoreChanged,
            object: nil
        )

        startMCPBroker()
        refreshStatus()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        accessPollTimer?.invalidate()
        accessPollTimer = nil
        NotificationCenter.default.removeObserver(self, name: .EKEventStoreChanged, object: nil)
        mcpBroker?.stop()
        mcpBroker = nil
    }

    private func addStatusItem(for kind: AccessKind) {
        let item = NSMenuItem(title: "Checking \(kind.label) access…", action: nil, keyEquivalent: "")
        item.isEnabled = false
        statusMenuItems[kind] = item
        statusMenu.addItem(item)
    }

    private func startMCPBroker() {
        do {
            let broker = LocalMCPBroker(
                server: iCloudBridgeServer(calendar: calendar, reminders: reminders)
            )
            try broker.start()
            mcpBroker = broker
        } catch {
            logger.error("Unable to start local MCP broker: \(error.localizedDescription, privacy: .public)")
            statusMenuItems.values.forEach { $0.title = "MCP: unavailable" }
        }
    }

    @objc private func requestMissingAccess() {
        guard isRequestingAccess == nil else {
            logger.notice("Ignoring duplicate access request while one is already pending")
            return
        }

        pendingAccessKinds = accessKinds.filter { status(for: $0).authorization != "full_access" }
        guard !pendingAccessKinds.isEmpty else {
            refreshStatus()
            return
        }

        requestNextAccess()
    }

    private func requestNextAccess() {
        guard isRequestingAccess == nil else { return }

        guard !pendingAccessKinds.isEmpty else {
            refreshStatus()
            return
        }

        let kind = pendingAccessKinds.removeFirst()
        let currentStatus = status(for: kind)

        if currentStatus.authorization == "full_access" {
            requestNextAccess()
            return
        }

        guard currentStatus.authorization == "not_determined" else {
            logger.notice("\(kind.label) access cannot show a prompt; status is already \(currentStatus.authorization, privacy: .public)")
            showAccessError(for: kind, error: iCloudBridgeError.accessRequired(currentStatus.authorization))
            requestNextAccess()
            return
        }

        isRequestingAccess = kind
        refreshStatus()
        logger.notice("Request Missing Access started for \(kind.label)")
        let becameRegularApp = NSApp.setActivationPolicy(.regular)
        logger.notice("Temporarily foregrounding iCloud Bridge for permission request; policy changed=\(becameRegularApp, privacy: .public)")
        NSApp.activate(ignoringOtherApps: true)

        let window = NSWindow(
            contentRect: NSRect(x: -100, y: -100, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0.01
        window.hasShadow = false
        window.ignoresMouseEvents = true
        permissionWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        statusMenuItems[kind]?.title = "Requesting \(kind.label) Access…"
        accessPollTimer = Timer.scheduledTimer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(checkPendingAccessStatus),
            userInfo: nil,
            repeats: true
        )

        let completion: @MainActor @Sendable (Result<Void, iCloudBridgeError>) -> Void = { [weak self] result in
            self?.finishAccessRequest(kind: kind, result: result)
        }

        switch kind {
        case .calendar:
            calendar.requestAccessIfNeeded(completion: completion)
        case .reminders:
            reminders.requestAccessIfNeeded(completion: completion)
        }
    }

    @objc private func eventStoreChanged() {
        checkPendingAccessStatus()
    }

    @objc private func checkPendingAccessStatus() {
        guard let kind = isRequestingAccess else { return }
        let currentStatus = status(for: kind)
        guard currentStatus.authorization != "not_determined" else { return }

        let result: Result<Void, iCloudBridgeError> = currentStatus.authorization == "full_access"
            ? .success(())
            : .failure(.accessRequired(currentStatus.authorization))
        finishAccessRequest(kind: kind, result: result)
    }

    private func finishAccessRequest(
        kind: AccessKind,
        result: Result<Void, iCloudBridgeError>
    ) {
        guard isRequestingAccess == kind else { return }

        isRequestingAccess = nil
        accessPollTimer?.invalidate()
        accessPollTimer = nil
        permissionWindow?.orderOut(nil)
        permissionWindow = nil
        NSApp.setActivationPolicy(.accessory)

        switch result {
        case .success:
            logger.notice("\(kind.label) access request completed successfully")
        case .failure(let error):
            logger.error("\(kind.label) access request failed: \(error.localizedDescription, privacy: .public)")
            showAccessError(for: kind, error: error)
        }

        refreshStatus()
        requestNextAccess()
    }

    private func showAccessError(for kind: AccessKind, error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(kind.label) Access Failed"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Open \(kind.label) Settings")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn, let url = kind.settingsURL {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private var accessKinds: [AccessKind] {
        [.calendar, .reminders]
    }

    private func status(for kind: AccessKind) -> AccessStatus {
        switch kind {
        case .calendar: return calendar.status()
        case .reminders: return reminders.status()
        }
    }

    private func refreshStatus() {
        for kind in accessKinds {
            let status = status(for: kind)
            statusMenuItems[kind]?.title = "\(kind.label): \(status.authorization.replacingOccurrences(of: "_", with: " "))"
        }

        let allGranted = accessKinds.allSatisfy { status(for: $0).authorization == "full_access" }
        statusItem.button?.title = allGranted ? "iCloud ✓" : "iCloud"

        let shouldShowRequest = !allGranted
        if shouldShowRequest, requestAccessMenuItem == nil {
            let separator = NSMenuItem.separator()
            let requestItem = NSMenuItem(title: "Request Missing Access", action: #selector(requestMissingAccess), keyEquivalent: "")
            requestItem.target = self
            let quitIndex = statusMenu.index(of: quitMenuItem)
            statusMenu.insertItem(separator, at: quitIndex)
            statusMenu.insertItem(requestItem, at: quitIndex + 1)
            requestAccessSeparator = separator
            requestAccessMenuItem = requestItem
        } else if !shouldShowRequest, let requestItem = requestAccessMenuItem {
            statusMenu.removeItem(requestItem)
            if let separator = requestAccessSeparator {
                statusMenu.removeItem(separator)
            }
            requestAccessMenuItem = nil
            requestAccessSeparator = nil
        }

        requestAccessMenuItem?.title = isRequestingAccess == nil
            ? "Request Missing Access"
            : "Requesting \(isRequestingAccess?.label ?? "Access")…"
        requestAccessMenuItem?.isEnabled = isRequestingAccess == nil
    }

    @discardableResult
    private func addActionItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        statusMenu.addItem(item)
        return item
    }
}
