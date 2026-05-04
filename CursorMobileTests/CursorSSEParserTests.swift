import XCTest
@testable import CursorMobile

final class CursorSSEParserTests: XCTestCase {
    func testParsesEventIDNameAndMultilineData() {
        let events = CursorSSEParser.parse(
            """
            id: event-1
            event: assistant
            data: {"text":"first"}
            data: {"text":"second"}

            """
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.id, "event-1")
        XCTAssertEqual(events.first?.event, "assistant")
        XCTAssertEqual(events.first?.data, #"{"text":"first"}"# + "\n" + #"{"text":"second"}"#)
    }

    func testIgnoresCommentsAndUnknownFields() {
        let events = CursorSSEParser.parse(
            """
            : heartbeat
            retry: 1000
            ignored: value
            data: [DONE]

            """
        )

        XCTAssertEqual(events, [ServerSentEvent(id: nil, event: nil, data: "[DONE]")])
    }

    func testFlushesFinalEventWithoutTrailingBlankLine() {
        let events = CursorSSEParser.parse(
            """
            id: final
            event: done
            data: [DONE]
            """
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.id, "final")
        XCTAssertEqual(events.first?.event, "done")
        XCTAssertEqual(events.first?.data, "[DONE]")
    }
}
