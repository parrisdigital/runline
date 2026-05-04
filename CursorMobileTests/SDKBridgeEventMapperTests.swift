import XCTest
@testable import CursorMobile

final class SDKBridgeEventMapperTests: XCTestCase {
    func testMapsSDKAssistantThinkingAndToolEventsIntoTimelineEvents() {
        let events = SDKBridgeEventMapper.events(
            from: [
                ServerSentEvent(id: nil, event: "assistant", data: #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Reviewing files"}]}}"#),
                ServerSentEvent(id: nil, event: "thinking", data: #"{"type":"thinking","text":"Checking state"}"#),
                ServerSentEvent(id: nil, event: "tool_call", data: #"{"type":"tool_call","name":"read_file","status":"running","args":{"path":"AppState.swift"}}"#),
            ],
            runID: "run-123"
        )

        XCTAssertEqual(events.map(\.kind), [.assistant, .thinking, .toolCall])
        XCTAssertEqual(events[0].title, "Assistant")
        XCTAssertEqual(events[0].message, "Reviewing files")
        XCTAssertEqual(events[1].message, "Checking state")
        XCTAssertTrue(events[2].message.contains("read_file"))
        XCTAssertTrue(events[2].message.contains("AppState.swift"))
    }

    func testSDKEventFallbackIDsAreStableAcrossReplay() throws {
        let event = ServerSentEvent(id: nil, event: "thinking", data: #"{"type":"thinking","text":"Checking state"}"#)

        let first = try XCTUnwrap(SDKBridgeEventMapper.streamEvent(from: event, runID: "run-123", fallbackIndex: 0))
        let replay = try XCTUnwrap(SDKBridgeEventMapper.streamEvent(from: event, runID: "run-123", fallbackIndex: 0))

        XCTAssertEqual(first.id, replay.id)
    }
}
