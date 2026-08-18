import iCloudBridgeCore
import AppKit
import Foundation
import Logging
import SwiftMCP

@main
struct iCloudBridgeCommand {
    static func main() async {
        do {
            if CommandLine.arguments.contains("--stdio") {
                try await runStdio()
            } else {
                await runMenuBar()
            }
        } catch {
            FileHandle.standardError.write(Data("iCloud Bridge error: \(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func runStdio() async throws {
        LoggingSystem.bootstrap { label in
            StreamLogHandler.standardError(label: label)
        }

        try LocalMCPProxy.run()
    }

    private static func runMenuBar() async {
        guard isOnlyMenuBarInstance() else {
            return
        }

        await MainActor.run {
            let controller = MenuBarController()
            withExtendedLifetime(controller) {
                controller.run()
            }
        }
    }

    private static func isOnlyMenuBarInstance() -> Bool {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let otherInstances = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.calendarbridge.app")
            .contains { $0.processIdentifier != currentPID }

        if otherInstances {
            FileHandle.standardError.write(
                Data("iCloud Bridge is already running.\n".utf8)
            )
            return false
        }

        return true
    }
}
