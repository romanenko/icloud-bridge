import EventKit
import Foundation
import OSLog

/// Owns the EventKit reminder store inside the authorized menu-bar process.
public final class ReminderStore: @unchecked Sendable {
    private let eventStore = EKEventStore()
    private let logger = Logger(subsystem: "com.icloudbridge.app", category: "reminder-permissions")

    public init() {}

    public func status() -> AccessStatus {
        let authorization = authorizationName
        let message: String

        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            message = "Reminders full access is enabled."
        case .writeOnly:
            message = "Reminders write-only access is enabled; reading reminders requires Full Access."
        case .denied:
            message = "Reminders access was denied. Enable iCloud Bridge in System Settings."
        case .restricted:
            message = "Reminders access is restricted by macOS or device policy."
        case .notDetermined:
            message = "Reminders access has not been requested yet."
        @unknown default:
            message = "Reminders access has an unknown status."
        }

        return AccessStatus(authorization: authorization, message: message)
    }

    @MainActor
    public func requestAccessIfNeeded(
        completion: @escaping @MainActor @Sendable (Result<Void, iCloudBridgeError>) -> Void
    ) {
        let currentStatus = EKEventStore.authorizationStatus(for: .reminder)
        logger.notice("Reminders access request started; current status: \(String(describing: currentStatus), privacy: .public)")

        guard currentStatus == .notDetermined else {
            logger.notice("Reminders access request skipped; status is already \(self.authorizationName, privacy: .public)")
            do {
                try requireFullAccess()
                completion(.success(()))
            } catch let error as iCloudBridgeError {
                completion(.failure(error))
            } catch {
                completion(.failure(.accessRequestFailed(error.localizedDescription)))
            }
            return
        }

        logger.notice("Calling EKEventStore.requestFullAccessToReminders(completion:)")
        eventStore.requestFullAccessToReminders { [logger] granted, error in
            let result: Result<Void, iCloudBridgeError>

            if granted {
                logger.notice("EKEventStore.requestFullAccessToReminders() completed with granted=true")
                result = .success(())
            } else if let error {
                logger.error("EKEventStore.requestFullAccessToReminders() failed: \(error.localizedDescription, privacy: .public)")
                result = .failure(.accessRequestFailed(error.localizedDescription))
            } else {
                let status = EKEventStore.authorizationStatus(for: .reminder)
                let authorization = reminderAuthorizationName(for: status)
                logger.error("EKEventStore.requestFullAccessToReminders() completed with granted=false; status=\(authorization, privacy: .public)")
                result = .failure(.accessRequired(authorization))
            }

            DispatchQueue.main.async { @MainActor in
                completion(result)
            }
        }
    }

    public func listLists() throws -> [ReminderListSummary] {
        try requireFullAccess()

        let defaultID = eventStore.defaultCalendarForNewReminders()?.calendarIdentifier
        return eventStore.calendars(for: .reminder)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { list in
                ReminderListSummary(
                    id: list.calendarIdentifier,
                    title: list.title,
                    source: list.source?.title,
                    type: String(describing: list.type),
                    writable: list.allowsContentModifications,
                    subscribed: list.isSubscribed,
                    isDefault: list.calendarIdentifier == defaultID
                )
            }
    }

    public func findReminders(
        start: Date?,
        end: Date?,
        listIDs: [String],
        search: String?,
        includeCompleted: Bool,
        limit: Int
    ) async throws -> [ReminderSummary] {
        try requireFullAccess()
        if let start, let end, end <= start {
            throw iCloudBridgeError.invalidDateRange
        }
        guard (1...500).contains(limit) else { throw iCloudBridgeError.invalidLimit }

        let lists: [EKCalendar]?
        if listIDs.isEmpty {
            lists = nil
        } else {
            lists = try listIDs.map { try list(withID: $0) }
        }

        let reminders = await fetchReminders(matching: eventStore.predicateForReminders(in: lists))
        let normalizedSearch = search?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return reminders
            .filter { reminder in
                if !includeCompleted && reminder.completed { return false }

                if let normalizedSearch, !normalizedSearch.isEmpty,
                   !reminder.title.localizedCaseInsensitiveContains(normalizedSearch),
                   !(reminder.notes?.localizedCaseInsensitiveContains(normalizedSearch) ?? false) {
                    return false
                }

                if let due = reminder.due {
                    if let start, due < start { return false }
                    if let end, due >= end { return false }
                }

                return true
            }
            .sorted { lhs, rhs in
                switch (lhs.due, rhs.due) {
                case let (left?, right?):
                    if left != right { return left < right }
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    break
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    public func createReminder(
        title: String,
        listID: String,
        start: Date?,
        due: Date?,
        notes: String?,
        url: URL?,
        priority: Int,
        completed: Bool
    ) throws -> ReminderSummary {
        try requireFullAccess()
        try validate(priority: priority)

        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = try writableList(withID: listID)
        reminder.title = title
        reminder.startDateComponents = dateComponents(from: start)
        reminder.dueDateComponents = dateComponents(from: due)
        reminder.notes = notes
        reminder.url = url
        reminder.priority = priority
        reminder.isCompleted = completed

        try save(reminder)
        return makeSummary(reminder)
    }

    public func updateReminder(
        reminderID: String,
        listID: String?,
        title: String?,
        start: Date?,
        due: Date?,
        notes: String?,
        url: URL?,
        priority: Int?,
        completed: Bool?
    ) throws -> ReminderSummary {
        try requireFullAccess()

        let reminder = try reminder(withID: reminderID)
        if let listID { reminder.calendar = try writableList(withID: listID) }
        if let title { reminder.title = title }
        if let start { reminder.startDateComponents = dateComponents(from: start) }
        if let due { reminder.dueDateComponents = dateComponents(from: due) }
        if let notes { reminder.notes = notes }
        if let url { reminder.url = url }
        if let priority {
            try validate(priority: priority)
            reminder.priority = priority
        }
        if let completed { reminder.isCompleted = completed }

        try save(reminder)
        return makeSummary(reminder)
    }

    public func deleteReminder(reminderID: String) throws -> AccessStatus {
        try requireFullAccess()

        let reminder = try reminder(withID: reminderID)
        do {
            try eventStore.remove(reminder, commit: true)
        } catch {
            throw iCloudBridgeError.reminderOperationFailed(error.localizedDescription)
        }

        return AccessStatus(
            authorization: authorizationName,
            message: "Deleted reminder \(reminderID)."
        )
    }

    private var authorizationName: String {
        reminderAuthorizationName(for: EKEventStore.authorizationStatus(for: .reminder))
    }

    private func requireFullAccess() throws {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            throw iCloudBridgeError.accessRequired(authorizationName)
        }
    }

    private func list(withID id: String) throws -> EKCalendar {
        guard let list = eventStore.calendar(withIdentifier: id) else {
            throw iCloudBridgeError.reminderListNotFound(id)
        }
        return list
    }

    private func writableList(withID id: String) throws -> EKCalendar {
        let list: EKCalendar
        if id.isEmpty {
            guard let defaultList = eventStore.defaultCalendarForNewReminders() else {
                throw iCloudBridgeError.reminderListNotFound("default list")
            }
            list = defaultList
        } else {
            list = try self.list(withID: id)
        }

        guard list.allowsContentModifications else {
            throw iCloudBridgeError.reminderListNotWritable(list.calendarIdentifier)
        }
        return list
    }

    private func reminder(withID id: String) throws -> EKReminder {
        guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
            throw iCloudBridgeError.reminderNotFound(id)
        }
        return reminder
    }

    private func validate(priority: Int) throws {
        guard priority == 0 || (1...9).contains(priority) else {
            throw iCloudBridgeError.invalidPriority
        }
    }

    private func save(_ reminder: EKReminder) throws {
        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            throw iCloudBridgeError.reminderOperationFailed(error.localizedDescription)
        }
    }

    private func fetchReminders(matching predicate: NSPredicate) async -> [ReminderSummary] {
        await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders?.map(self.makeSummary) ?? [])
            }
        }
    }

    private func makeSummary(_ reminder: EKReminder) -> ReminderSummary {
        ReminderSummary(
            id: reminder.calendarItemIdentifier,
            externalId: reminder.calendarItemExternalIdentifier,
            listId: reminder.calendar?.calendarIdentifier ?? "",
            listTitle: reminder.calendar?.title ?? "Unknown list",
            title: reminder.title,
            start: date(from: reminder.startDateComponents),
            due: date(from: reminder.dueDateComponents),
            completed: reminder.isCompleted,
            completedAt: reminder.completionDate,
            priority: Int(reminder.priority),
            notes: reminder.notes,
            url: reminder.url
        )
    }

    private func date(from components: DateComponents?) -> Date? {
        guard let components else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        if let timeZone = components.timeZone {
            calendar.timeZone = timeZone
        }
        return calendar.date(from: components)
    }

    private func dateComponents(from date: Date?) -> DateComponents? {
        guard let date else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return components
    }
}

private func reminderAuthorizationName(for status: EKAuthorizationStatus) -> String {
    switch status {
    case .fullAccess: return "full_access"
    case .writeOnly: return "write_only"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "not_determined"
    @unknown default: return "unknown"
    }
}
