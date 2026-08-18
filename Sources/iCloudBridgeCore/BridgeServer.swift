import Foundation
import SwiftMCP

@MCPServer(
    name: "icloud-bridge",
    version: "0.1.0",
    description: "A local bridge to the user's macOS Calendar and Reminders data. Data is private. Only modify items when the user explicitly asks.",
    title: "iCloud Bridge"
)
public actor iCloudBridgeServer {
    private let calendar: CalendarStore
    private let reminders: ReminderStore

    public init(calendar: CalendarStore, reminders: ReminderStore) {
        self.calendar = calendar
        self.reminders = reminders
    }

    public init(calendar: CalendarStore) {
        self.calendar = calendar
        self.reminders = ReminderStore()
    }

    /// Returns the current Calendar permission state without requesting access.
    @MCPTool(hints: [.readOnly, .idempotent])
    public func calendarGetStatus() async -> AccessStatus {
        calendar.status()
    }

    /// Lists the calendars configured in macOS Calendar.
    @MCPTool(hints: [.readOnly, .idempotent])
    public func calendarListCalendars() async throws -> [CalendarSummary] {
        try calendar.listCalendars()
    }

    /// Finds events in a required date range. Search matches title, location, or notes.
    /// - Parameter start: Inclusive start of the search range.
    /// - Parameter end: Exclusive end of the search range.
    /// - Parameter calendarIDs: Optional calendar identifiers returned by calendarListCalendars.
    /// - Parameter search: Optional text to match in title, location, or notes.
    /// - Parameter limit: Maximum number of events to return, from 1 to 500.
    @MCPTool(hints: [.readOnly, .idempotent])
    public func calendarFindEvents(
        start: Date,
        end: Date,
        calendarIDs: [String] = [],
        search: String? = nil,
        limit: Int = 100
    ) async throws -> [EventSummary] {
        try calendar.findEvents(
            start: start,
            end: end,
            calendarIDs: calendarIDs,
            search: search,
            limit: limit
        )
    }

    /// Creates an event in the selected calendar. An empty calendar ID uses the user's default calendar.
    @MCPTool(hints: [.openWorld])
    public func calendarCreateEvent(
        title: String,
        start: Date,
        end: Date,
        calendarID: String = "",
        allDay: Bool = false,
        location: String? = nil,
        notes: String? = nil,
        url: URL? = nil
    ) async throws -> EventSummary {
        try calendar.createEvent(
            title: title,
            start: start,
            end: end,
            calendarID: calendarID,
            allDay: allDay,
            location: location,
            notes: notes,
            url: url
        )
    }

    /// Updates an existing event by identifier. Only supplied fields are changed.
    /// Recurring events can be updated for this event or this and future events.
    @MCPTool(hints: [.openWorld])
    public func calendarUpdateEvent(
        eventID: String,
        calendarID: String? = nil,
        span: String = "this_event",
        title: String? = nil,
        start: Date? = nil,
        end: Date? = nil,
        allDay: Bool? = nil,
        location: String? = nil,
        notes: String? = nil,
        url: URL? = nil
    ) async throws -> EventSummary {
        try calendar.updateEvent(
            eventID: eventID,
            calendarID: calendarID,
            span: span,
            title: title,
            start: start,
            end: end,
            allDay: allDay,
            location: location,
            notes: notes,
            url: url
        )
    }

    /// Deletes an event by identifier. Recurring events support this_event or future_events.
    @MCPTool(hints: [.destructive, .openWorld])
    public func calendarDeleteEvent(
        eventID: String,
        span: String = "this_event"
    ) async throws -> AccessStatus {
        try calendar.deleteEvent(eventID: eventID, span: span)
    }

    /// Returns the current Reminders permission state without requesting access.
    @MCPTool(hints: [.readOnly, .idempotent])
    public func reminderGetStatus() async -> AccessStatus {
        reminders.status()
    }

    /// Lists the reminder lists configured in macOS Reminders.
    @MCPTool(hints: [.readOnly, .idempotent])
    public func reminderListLists() async throws -> [ReminderListSummary] {
        try reminders.listLists()
    }

    /// Finds reminders, optionally filtering by due-date range, list, text, and completion state.
    /// - Parameter start: Optional inclusive lower bound for due dates.
    /// - Parameter end: Optional exclusive upper bound for due dates.
    /// - Parameter listIDs: Optional list identifiers returned by reminderListLists.
    /// - Parameter search: Optional text to match in the title or notes.
    /// - Parameter includeCompleted: Whether completed reminders should be returned.
    /// - Parameter limit: Maximum number of reminders to return, from 1 to 500.
    @MCPTool(hints: [.readOnly, .idempotent])
    public func reminderFindReminders(
        start: Date? = nil,
        end: Date? = nil,
        listIDs: [String] = [],
        search: String? = nil,
        includeCompleted: Bool = false,
        limit: Int = 100
    ) async throws -> [ReminderSummary] {
        try await reminders.findReminders(
            start: start,
            end: end,
            listIDs: listIDs,
            search: search,
            includeCompleted: includeCompleted,
            limit: limit
        )
    }

    /// Creates a reminder in the selected list. An empty list ID uses the default reminder list.
    @MCPTool(hints: [.openWorld])
    public func reminderCreateReminder(
        title: String,
        listID: String = "",
        start: Date? = nil,
        due: Date? = nil,
        notes: String? = nil,
        url: URL? = nil,
        priority: Int = 0,
        completed: Bool = false
    ) async throws -> ReminderSummary {
        try reminders.createReminder(
            title: title,
            listID: listID,
            start: start,
            due: due,
            notes: notes,
            url: url,
            priority: priority,
            completed: completed
        )
    }

    /// Updates an existing reminder. Only supplied fields are changed.
    @MCPTool(hints: [.openWorld])
    public func reminderUpdateReminder(
        reminderID: String,
        listID: String? = nil,
        title: String? = nil,
        start: Date? = nil,
        due: Date? = nil,
        notes: String? = nil,
        url: URL? = nil,
        priority: Int? = nil,
        completed: Bool? = nil
    ) async throws -> ReminderSummary {
        try reminders.updateReminder(
            reminderID: reminderID,
            listID: listID,
            title: title,
            start: start,
            due: due,
            notes: notes,
            url: url,
            priority: priority,
            completed: completed
        )
    }

    /// Deletes a reminder by identifier.
    @MCPTool(hints: [.destructive, .openWorld])
    public func reminderDeleteReminder(reminderID: String) async throws -> AccessStatus {
        try reminders.deleteReminder(reminderID: reminderID)
    }
}
