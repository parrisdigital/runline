import CryptoKit
import Foundation

enum SDKBridgeEventMapper {
    static func events(from serverEvents: [ServerSentEvent], runID: AgentRun.ID) -> [AgentStreamEvent] {
        serverEvents.enumerated().compactMap { index, event in
            streamEvent(from: event, runID: runID, fallbackIndex: index)
        }
    }

    static func streamEvent(
        from event: ServerSentEvent,
        runID: AgentRun.ID,
        fallbackIndex: Int
    ) -> AgentStreamEvent? {
        if event.data == "[DONE]" {
            return AgentStreamEvent(
                id: event.id ?? "\(runID)-sdk-done",
                runID: runID,
                kind: .done,
                title: "Done",
                message: "Stream closed",
                timestamp: "now"
            )
        }

        let json = try? JSONDecoder().decode(JSONValue.self, from: Data(event.data.utf8))
        let object = json?.objectValue
        let eventName = event.event ?? object?.stringValue(for: "event") ?? object?.stringValue(for: "type")
        let kind = StreamEventKind(sdkBridgeValue: eventName)

        let content = content(for: kind, eventName: eventName, object: object, json: json)
        guard content.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || kind == .done else {
            return nil
        }

        return AgentStreamEvent(
            id: stableID(for: event, object: object, runID: runID, fallbackIndex: fallbackIndex),
            runID: runID,
            kind: kind,
            title: content.title,
            message: content.message,
            timestamp: object?.stringValue(for: "timestamp")
                ?? CursorDateParser.relativeDescription(from: object?.stringValue(for: "createdAt"))
        )
    }

    private static func content(
        for kind: StreamEventKind,
        eventName: String?,
        object: [String: JSONValue]?,
        json: JSONValue?
    ) -> (title: String, message: String) {
        switch kind {
        case .assistant:
            return ("Assistant", textContent(from: object) ?? "Assistant output")
        case .thinking:
            let duration = object?.numberValue(for: "thinkingDurationMs")
                ?? object?.numberValue(for: "thinking_duration_ms")
            if let duration, textContent(from: object)?.isEmpty != false {
                return ("Thinking Completed", "Completed in \(Int(duration)) ms")
            }
            return ("Thinking", textContent(from: object) ?? "Thinking update")
        case .toolCall:
            let name = object?.stringValue(for: "name")
                ?? object?.stringValue(for: "toolName")
                ?? object?.stringValue(for: "type")
                ?? "tool"
            let status = object?.stringValue(for: "status") ?? "running"
            var parts = [status]
            if let args = object?["args"] ?? object?["input"] {
                parts.append("args \(args.previewLine(maxLength: 120))")
            }
            if let result = object?["result"] {
                parts.append("result \(result.previewLine(maxLength: 120))")
            }
            return ("Tool Call", "\(name): \(parts.joined(separator: " - "))")
        case .status:
            return ("Status", object?.stringValue(for: "status") ?? object?.stringValue(for: "message") ?? "Status update")
        case .task:
            return ("Task", textContent(from: object) ?? object?.stringValue(for: "summary") ?? "Task update")
        case .request:
            return ("Request", object?.stringValue(for: "message") ?? "Cursor is waiting for input or approval.")
        case .result:
            return ("Result", object?.stringValue(for: "result") ?? object?.stringValue(for: "text") ?? object?.stringValue(for: "status") ?? "Run result received")
        case .heartbeat:
            return ("Heartbeat", "Cursor stream heartbeat")
        case .error:
            let code = object?.stringValue(for: "code") ?? "UNKNOWN"
            let message = object?.stringValue(for: "message") ?? "Unknown stream error"
            return ("Error", "[\(code)] \(message)")
        case .done:
            return ("Done", "Stream closed")
        case .system:
            return ("System", object?.stringValue(for: "message") ?? "Run metadata received")
        case .user:
            return ("User", textContent(from: object) ?? "User message received")
        case .unknown:
            return (displayTitle(from: eventName ?? "event"), textContent(from: object) ?? json?.previewLine() ?? "Stream event received")
        }
    }

    private static func textContent(from object: [String: JSONValue]?) -> String? {
        guard let object else { return nil }
        if let text = object.stringValue(for: "text") {
            return text
        }
        if let message = object.stringValue(for: "message") {
            return message
        }
        if let message = object.objectValue(for: "message"),
           let content = message.arrayValue(for: "content") {
            let text = content.compactMap { block -> String? in
                if let value = block.stringValue {
                    return value
                }
                return block.objectValue?.stringValue(for: "text")
            }
            .joined()
            if !text.isEmpty {
                return text
            }
        }
        if let userMessage = object.objectValue(for: "userMessage")
            ?? object.objectValue(for: "user_message") {
            return userMessage.stringValue(for: "text")
        }
        return nil
    }

    private static func stableID(
        for event: ServerSentEvent,
        object: [String: JSONValue]?,
        runID: AgentRun.ID,
        fallbackIndex: Int
    ) -> String {
        if let id = object?.stringValue(for: "id")?.nilIfBlank ?? event.id?.nilIfBlank {
            return id
        }
        let digest = stableDigest("\(event.event ?? "event"):\(event.data)")
        return "\(runID)-sdk-\(digest)-\(fallbackIndex)"
    }

    private static func stableDigest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .prefix(10)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func displayTitle(from value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .map { word in
                guard let first = word.first else { return "" }
                return first.uppercased() + String(word.dropFirst())
            }
            .joined(separator: " ")
    }
}

private extension StreamEventKind {
    init(sdkBridgeValue: String?) {
        switch sdkBridgeValue?.lowercased() {
        case "system":
            self = .system
        case "user", "user_message", "user-message-appended":
            self = .user
        case "status":
            self = .status
        case "assistant", "assistant_message", "text-delta":
            self = .assistant
        case "thinking", "reasoning", "thinking-delta", "thinking-completed":
            self = .thinking
        case "tool_call", "toolcall", "tool-call-started", "partial-tool-call", "tool-call-completed":
            self = .toolCall
        case "task", "summary", "summary-started", "summary-delta", "summary-completed", "step-started", "step-completed", "turn-ended":
            self = .task
        case "request":
            self = .request
        case "result", "tool_result":
            self = .result
        case "heartbeat":
            self = .heartbeat
        case "error":
            self = .error
        case "done", "complete", "completed":
            self = .done
        default:
            self = .unknown
        }
    }
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        if case .object(let object) = self {
            return object
        }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    func previewLine(maxLength: Int = 180) -> String {
        let flattened = preview(maxLines: 4)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        if flattened.count <= maxLength {
            return flattened
        }
        return String(flattened.prefix(maxLength)) + "..."
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func stringValue(for key: String) -> String? {
        self[key]?.stringValue
    }

    func objectValue(for key: String) -> [String: JSONValue]? {
        self[key]?.objectValue
    }

    func arrayValue(for key: String) -> [JSONValue]? {
        if case .array(let values)? = self[key] {
            return values
        }
        return nil
    }

    func numberValue(for key: String) -> Double? {
        if case .number(let value)? = self[key] {
            return value
        }
        return nil
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
