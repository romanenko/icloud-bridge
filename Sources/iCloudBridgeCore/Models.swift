import Foundation
import SwiftMCP

@Schema
public struct AccessStatus: Codable, Sendable {
    public let authorization: String
    public let message: String

    public init(authorization: String, message: String) {
        self.authorization = authorization
        self.message = message
    }
}


@Schema
public struct CalendarSummary: Codable, Sendable {
    public let id: String
    public let title: String
    public let source: String?
    public let type: String
    public let writable: Bool
    public let subscribed: Bool
    public let isDefault: Bool

    public init(
        id: String,
        title: String,
        source: String?,
        type: String,
        writable: Bool,
        subscribed: Bool,
        isDefault: Bool
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.type = type
        self.writable = writable
        self.subscribed = subscribed
        self.isDefault = isDefault
    }
}

@Schema
public struct EventSummary: Codable, Sendable {
    public let id: String
    public let externalId: String?
    public let calendarId: String
    public let calendarTitle: String
    public let title: String
    public let start: Date
    public let end: Date
    public let allDay: Bool
    public let timeZone: String?
    public let location: String?
    public let notes: String?
    public let url: URL?
    public let recurrence: Bool
    public let status: String

    public init(
        id: String,
        externalId: String?,
        calendarId: String,
        calendarTitle: String,
        title: String,
        start: Date,
        end: Date,
        allDay: Bool,
        timeZone: String?,
        location: String?,
        notes: String?,
        url: URL?,
        recurrence: Bool,
        status: String
    ) {
        self.id = id
        self.externalId = externalId
        self.calendarId = calendarId
        self.calendarTitle = calendarTitle
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
        self.timeZone = timeZone
        self.location = location
        self.notes = notes
        self.url = url
        self.recurrence = recurrence
        self.status = status
    }
}

@Schema
public struct ReminderListSummary: Codable, Sendable {
    public let id: String
    public let title: String
    public let source: String?
    public let type: String
    public let writable: Bool
    public let subscribed: Bool
    public let isDefault: Bool

    public init(
        id: String,
        title: String,
        source: String?,
        type: String,
        writable: Bool,
        subscribed: Bool,
        isDefault: Bool
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.type = type
        self.writable = writable
        self.subscribed = subscribed
        self.isDefault = isDefault
    }
}

@Schema
public struct ReminderSummary: Codable, Sendable {
    public let id: String
    public let externalId: String?
    public let listId: String
    public let listTitle: String
    public let title: String
    public let start: Date?
    public let due: Date?
    public let completed: Bool
    public let completedAt: Date?
    public let priority: Int
    public let notes: String?
    public let url: URL?

    public init(
        id: String,
        externalId: String?,
        listId: String,
        listTitle: String,
        title: String,
        start: Date?,
        due: Date?,
        completed: Bool,
        completedAt: Date?,
        priority: Int,
        notes: String?,
        url: URL?
    ) {
        self.id = id
        self.externalId = externalId
        self.listId = listId
        self.listTitle = listTitle
        self.title = title
        self.start = start
        self.due = due
        self.completed = completed
        self.completedAt = completedAt
        self.priority = priority
        self.notes = notes
        self.url = url
    }
}

public enum iCloudBridgeError: LocalizedError, Sendable {
    case accessRequired(String)
    case accessRequestFailed(String)
    case calendarNotFound(String)
    case calendarNotWritable(String)
    case eventNotFound(String)
    case reminderListNotFound(String)
    case reminderListNotWritable(String)
    case reminderNotFound(String)
    case invalidDateRange
    case invalidLimit
    case invalidPriority
    case invalidSpan(String)
    case calendarOperationFailed(String)
    case reminderOperationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .accessRequired(let status):
            return "Access is not available (\(status)). Open iCloud Bridge and grant Full Access in System Settings."
        case .accessRequestFailed(let message):
            return "Access request failed: \(message)"
        case .calendarNotFound(let id):
            return "Calendar not found: \(id)"
        case .calendarNotWritable(let id):
            return "Calendar is not writable: \(id)"
        case .eventNotFound(let id):
            return "Event not found: \(id)"
        case .reminderListNotFound(let id):
            return "Reminder list not found: \(id)"
        case .reminderListNotWritable(let id):
            return "Reminder list is not writable: \(id)"
        case .reminderNotFound(let id):
            return "Reminder not found: \(id)"
        case .invalidDateRange:
            return "The end date must be after the start date."
        case .invalidLimit:
            return "The result limit must be between 1 and 500."
        case .invalidPriority:
            return "Reminder priority must be 0 or between 1 and 9."
        case .invalidSpan(let span):
            return "Unsupported recurring-event span: \(span). Use this_event or future_events."
        case .calendarOperationFailed(let message):
            return "Calendar operation failed: \(message)"
        case .reminderOperationFailed(let message):
            return "Reminder operation failed: \(message)"
        }
    }
}
