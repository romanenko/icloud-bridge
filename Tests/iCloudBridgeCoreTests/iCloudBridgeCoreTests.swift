import Foundation
import SwiftMCP
import XCTest
@testable import iCloudBridgeCore

final class iCloudBridgeCoreTests: XCTestCase {
    func testCalendarStatusDecodesAsStructuredData() throws {
        let data = Data(#"{"authorization":"full_access","message":"ready"}"#.utf8)
        let status = try JSONDecoder().decode(AccessStatus.self, from: data)

        XCTAssertEqual(status.authorization, "full_access")
        XCTAssertEqual(status.message, "ready")
    }

    func testReminderSummaryDecodesAsStructuredData() throws {
        let data = Data(#"{"id":"reminder-1","externalId":null,"listId":"list-1","listTitle":"Inbox","title":"Buy milk","start":null,"due":1787043600,"completed":false,"completedAt":null,"priority":5,"notes":null,"url":null}"#.utf8)
        let reminder = try JSONDecoder().decode(ReminderSummary.self, from: data)

        XCTAssertEqual(reminder.listTitle, "Inbox")
        XCTAssertEqual(reminder.title, "Buy milk")
        XCTAssertEqual(reminder.priority, 5)
        XCTAssertFalse(reminder.completed)
    }

    func testMCPExposesCalendarAndReminderTools() async throws {
        let server = iCloudBridgeServer(calendar: CalendarStore(), reminders: ReminderStore())
        let response = await server.handleMessage(JSONRPCMessage.request(id: 1, method: "tools/list"))

        guard case .response(let responseData)? = response,
              let result = responseData.result?.dictionaryValue,
              let toolValues = result["tools"]?.jsonObject as? [[String: Any]] else {
            XCTFail("tools/list did not return a tool list")
            return
        }

        let toolNames = Set(toolValues.compactMap { $0["name"] as? String })
        XCTAssertTrue(toolNames.isSuperset(of: [
            "calendarGetStatus",
            "calendarListCalendars",
            "calendarFindEvents",
            "calendarCreateEvent",
            "calendarUpdateEvent",
            "calendarDeleteEvent",
            "reminderGetStatus",
            "reminderListLists",
            "reminderFindReminders",
            "reminderCreateReminder",
            "reminderUpdateReminder",
            "reminderDeleteReminder"
        ]))
    }

    func testInvalidSpanHasActionableError() {
        let error = iCloudBridgeError.invalidSpan("all_events")

        XCTAssertEqual(
            error.localizedDescription,
            "Unsupported recurring-event span: all_events. Use this_event or future_events."
        )
    }
}
