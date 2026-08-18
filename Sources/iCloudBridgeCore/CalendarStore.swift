import EventKit
import Foundation
import OSLog

public final class CalendarStore: @unchecked Sendable {
    private let eventStore = EKEventStore()
    private let logger = Logger(subsystem: "com.icloudbridge.app", category: "calendar-permissions")

    public init() {}

    public func status() -> AccessStatus {
        let authorization = authorizationName
        let message: String

        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            message = "Calendar full access is enabled."
        case .writeOnly:
            message = "Calendar write-only access is enabled; reading events requires Full Access."
        case .denied:
            message = "Calendar access was denied. Enable iCloud Bridge in System Settings."
        case .restricted:
            message = "Calendar access is restricted by macOS or device policy."
        case .notDetermined:
            message = "Calendar access has not been requested yet."
        @unknown default:
            message = "Calendar access has an unknown status."
        }

        return AccessStatus(authorization: authorization, message: message)
    }

    @MainActor
    public func requestAccessIfNeeded(
        completion: @escaping @MainActor @Sendable (Result<Void, iCloudBridgeError>) -> Void
    ) {
        let currentStatus = EKEventStore.authorizationStatus(for: .event)
        logger.notice("Calendar access request started; current status: \(String(describing: currentStatus), privacy: .public)")

        guard currentStatus == .notDetermined else {
            logger.notice("Calendar access request skipped; status is already \(self.authorizationName, privacy: .public)")
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

        logger.notice("Calling EKEventStore.requestFullAccessToEvents(completion:)")
        eventStore.requestFullAccessToEvents { [logger] granted, error in
            let result: Result<Void, iCloudBridgeError>

            if granted {
                logger.notice("EKEventStore.requestFullAccessToEvents() completed with granted=true")
                result = .success(())
            } else if let error {
                logger.error("EKEventStore.requestFullAccessToEvents() failed: \(error.localizedDescription, privacy: .public)")
                result = .failure(.accessRequestFailed(error.localizedDescription))
            } else {
                let status = EKEventStore.authorizationStatus(for: .event)
                let authorization = calendarAuthorizationName(for: status)
                logger.error("EKEventStore.requestFullAccessToEvents() completed with granted=false; status=\(authorization, privacy: .public)")
                result = .failure(.accessRequired(authorization))
            }

            DispatchQueue.main.async { @MainActor in
                completion(result)
            }
        }
    }

    public func listCalendars() throws -> [CalendarSummary] {
        try requireFullAccess()

        let defaultID = eventStore.defaultCalendarForNewEvents?.calendarIdentifier
        return eventStore.calendars(for: .event)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { calendar in
                CalendarSummary(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    source: calendar.source?.title,
                    type: String(describing: calendar.type),
                    writable: calendar.allowsContentModifications,
                    subscribed: calendar.isSubscribed,
                    isDefault: calendar.calendarIdentifier == defaultID
                )
            }
    }

    public func findEvents(
        start: Date,
        end: Date,
        calendarIDs: [String],
        search: String?,
        limit: Int
    ) throws -> [EventSummary] {
        try requireFullAccess()

        guard end > start else { throw iCloudBridgeError.invalidDateRange }
        guard (1...500).contains(limit) else { throw iCloudBridgeError.invalidLimit }

        let calendars: [EKCalendar]?
        if calendarIDs.isEmpty {
            calendars = nil
        } else {
            calendars = try calendarIDs.map { try calendar(withID: $0) }
        }

        let predicate = eventStore.predicateForEvents(
            withStart: start,
            end: end,
            calendars: calendars
        )

        let normalizedSearch = search?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return eventStore.events(matching: predicate)
            .filter { event in
                guard let normalizedSearch, !normalizedSearch.isEmpty else { return true }
                return [event.title, event.location, event.notes]
                    .compactMap { $0?.lowercased() }
                    .contains { $0.localizedCaseInsensitiveContains(normalizedSearch) }
            }
            .sorted { $0.startDate < $1.startDate }
            .prefix(limit)
            .map(makeSummary)
    }

    public func createEvent(
        title: String,
        start: Date,
        end: Date,
        calendarID: String,
        allDay: Bool,
        location: String?,
        notes: String?,
        url: URL?
    ) throws -> EventSummary {
        try requireFullAccess()
        guard end > start else { throw iCloudBridgeError.invalidDateRange }

        let calendar = try writableCalendar(withID: calendarID)
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = title
        event.startDate = start
        event.endDate = end
        event.isAllDay = allDay
        event.location = location
        event.notes = notes
        event.url = url

        try save(event, span: .thisEvent)
        return makeSummary(event)
    }

    public func updateEvent(
        eventID: String,
        calendarID: String?,
        span: String,
        title: String?,
        start: Date?,
        end: Date?,
        allDay: Bool?,
        location: String?,
        notes: String?,
        url: URL?
    ) throws -> EventSummary {
        try requireFullAccess()

        let event = try event(withID: eventID)
        if let calendarID {
            event.calendar = try writableCalendar(withID: calendarID)
        }
        if let title { event.title = title }
        if let start { event.startDate = start }
        if let end { event.endDate = end }
        if let allDay { event.isAllDay = allDay }
        if let location { event.location = location }
        if let notes { event.notes = notes }
        if let url { event.url = url }

        guard event.endDate > event.startDate else { throw iCloudBridgeError.invalidDateRange }
        try save(event, span: try eventSpan(from: span))
        return makeSummary(event)
    }

    public func deleteEvent(eventID: String, span: String) throws -> AccessStatus {
        try requireFullAccess()

        let event = try event(withID: eventID)
        do {
            try eventStore.remove(event, span: try eventSpan(from: span), commit: true)
        } catch {
            throw iCloudBridgeError.calendarOperationFailed(error.localizedDescription)
        }

        return AccessStatus(
            authorization: authorizationName,
            message: "Deleted event \(eventID)."
        )
    }

    private var authorizationName: String {
        calendarAuthorizationName(for: EKEventStore.authorizationStatus(for: .event))
    }

    private func requireFullAccess() throws {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw iCloudBridgeError.accessRequired(authorizationName)
        }
    }

    private func calendar(withID id: String) throws -> EKCalendar {
        let calendar = eventStore.calendar(withIdentifier: id)
        guard let calendar else { throw iCloudBridgeError.calendarNotFound(id) }
        return calendar
    }

    private func writableCalendar(withID id: String) throws -> EKCalendar {
        let calendar: EKCalendar
        if id.isEmpty {
            guard let defaultCalendar = eventStore.defaultCalendarForNewEvents else {
                throw iCloudBridgeError.calendarNotFound("default calendar")
            }
            calendar = defaultCalendar
        } else {
            calendar = try self.calendar(withID: id)
        }

        guard calendar.allowsContentModifications else {
            throw iCloudBridgeError.calendarNotWritable(calendar.calendarIdentifier)
        }
        return calendar
    }

    private func event(withID id: String) throws -> EKEvent {
        guard let event = eventStore.event(withIdentifier: id) else {
            throw iCloudBridgeError.eventNotFound(id)
        }
        return event
    }

    private func eventSpan(from value: String) throws -> EKSpan {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "this_event", "thisevent", "this":
            return .thisEvent
        case "future_events", "futureevents", "future":
            return .futureEvents
        default:
            throw iCloudBridgeError.invalidSpan(value)
        }
    }

    private func save(_ event: EKEvent, span: EKSpan) throws {
        do {
            try eventStore.save(event, span: span, commit: true)
        } catch {
            throw iCloudBridgeError.calendarOperationFailed(error.localizedDescription)
        }
    }

    private func makeSummary(_ event: EKEvent) -> EventSummary {
        EventSummary(
            id: event.eventIdentifier ?? event.calendarItemIdentifier,
            externalId: event.calendarItemExternalIdentifier,
            calendarId: event.calendar?.calendarIdentifier ?? "",
            calendarTitle: event.calendar?.title ?? "Unknown calendar",
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            allDay: event.isAllDay,
            timeZone: event.timeZone?.identifier,
            location: event.location,
            notes: event.notes,
            url: event.url,
            recurrence: event.recurrenceRules?.isEmpty == false,
            status: String(describing: event.status)
        )
    }
}

private func calendarAuthorizationName(for status: EKAuthorizationStatus) -> String {
    switch status {
    case .fullAccess: return "full_access"
    case .writeOnly: return "write_only"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "not_determined"
    @unknown default: return "unknown"
    }
}
