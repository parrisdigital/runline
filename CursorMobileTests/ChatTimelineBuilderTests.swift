import XCTest
@testable import CursorMobile

final class ChatTimelineBuilderTests: XCTestCase {
    func testCoalescesThinkingDeltasAndCompletion() {
        let events = [
            event(id: "think-1", kind: .thinking, title: "Thinking", message: "Review"),
            event(id: "think-2", kind: .thinking, title: "Thinking", message: "ing the"),
            event(id: "think-3", kind: .thinking, title: "Thinking", message: "ing the"),
            event(id: "think-4", kind: .thinking, title: "Thinking", message: " current file state"),
            event(id: "think-done", kind: .thinking, title: "Thinking Completed", message: "Completed in 3998 ms"),
        ]

        let items = ChatTimelineBuilder.items(from: events)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].kind, .thinking)
        XCTAssertEqual(items[0].title, "Thinking Completed")
        XCTAssertEqual(items[0].message, "Reviewing the current file state")
        XCTAssertEqual(items[0].sourceEventIDs, ["think-1", "think-2", "think-4", "think-done"])
    }

    func testCoalescesAssistantDeltasAndDropsAdjacentDuplicates() {
        let events = [
            event(id: "assistant-1", kind: .assistant, title: "Assistant", message: "Search"),
            event(id: "assistant-2", kind: .assistant, title: "Assistant", message: "ing"),
            event(id: "assistant-3", kind: .assistant, title: "Assistant", message: "ing"),
            event(id: "assistant-4", kind: .assistant, title: "Assistant", message: " files"),
        ]

        let items = ChatTimelineBuilder.items(from: events)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].kind, .assistant)
        XCTAssertEqual(items[0].message, "Searching files")
        XCTAssertEqual(items[0].sourceEventIDs, ["assistant-1", "assistant-2", "assistant-4"])
    }

    func testToolCallsBreakTextGroups() {
        let events = [
            event(id: "think-1", kind: .thinking, title: "Thinking", message: "Checking state"),
            event(id: "tool-1", kind: .toolCall, title: "Tool Call", message: "read_file: running"),
            event(id: "think-2", kind: .thinking, title: "Thinking", message: "Planning fix"),
        ]

        let items = ChatTimelineBuilder.items(from: events)

        XCTAssertEqual(items.map(\.kind), [.thinking, .toolCall, .thinking])
        XCTAssertEqual(items[0].message, "Checking state")
        XCTAssertEqual(items[1].message, "read_file: running")
        XCTAssertEqual(items[2].message, "Planning fix")
    }

    func testKeepsNonDeltaAssistantRowsSeparate() {
        let events = [
            event(id: "follow-up-1", kind: .assistant, title: "Follow-up", message: "Run the same check again."),
            event(id: "follow-up-2", kind: .assistant, title: "Follow-up", message: "Confirm the final output."),
        ]

        let items = ChatTimelineBuilder.items(from: events)

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.message), ["Run the same check again.", "Confirm the final output."])
    }

    private func event(
        id: String,
        kind: StreamEventKind,
        title: String,
        message: String,
        timestamp: String = "now"
    ) -> AgentStreamEvent {
        AgentStreamEvent(
            id: id,
            runID: "run-123",
            kind: kind,
            title: title,
            message: message,
            timestamp: timestamp
        )
    }
}
