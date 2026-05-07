import Foundation

struct CursorSSEParser {
    private var eventID: String?
    private var eventName: String?
    private var dataLines: [String] = []

    mutating func ingest(_ line: String) -> ServerSentEvent? {
        if line.isEmpty {
            return flush()
        }

        if line.hasPrefix(":") {
            return nil
        }

        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard let field = parts.first else { return nil }
        let value = normalizedValue(parts.count > 1 ? String(parts[1]) : "")

        switch field {
        case "id":
            eventID = value
        case "event":
            eventName = value
        case "data":
            dataLines.append(value)
        case "retry":
            return nil
        default:
            return nil
        }

        return nil
    }

    mutating func finish() -> ServerSentEvent? {
        flush()
    }

    static func parse(_ payload: String) -> [ServerSentEvent] {
        var parser = CursorSSEParser()
        var events: [ServerSentEvent] = []

        for line in payload.components(separatedBy: .newlines) {
            if let event = parser.ingest(line) {
                events.append(event)
            }
        }

        if let event = parser.finish() {
            events.append(event)
        }

        return events
    }

    private mutating func flush() -> ServerSentEvent? {
        guard !dataLines.isEmpty else {
            eventName = nil
            return nil
        }

        let event = ServerSentEvent(
            id: eventID,
            event: eventName,
            data: dataLines.joined(separator: "\n")
        )
        eventName = nil
        dataLines.removeAll()
        return event
    }

    private func normalizedValue(_ value: String) -> String {
        if value.first == " " {
            return String(value.dropFirst())
        }
        return value
    }
}
