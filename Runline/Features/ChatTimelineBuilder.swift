import Foundation

struct ChatTimelineItem: Identifiable, Hashable {
    var id: String
    var runID: String
    var kind: StreamEventKind
    var title: String
    var message: String
    var activityPreviewText: String
    var activityDetailText: String
    var timestamp: String
    var sourceEventIDs: [String]
    var changeSet: WorkspaceChangeSet?

    init(event: AgentStreamEvent) {
        id = event.id
        runID = event.runID
        kind = event.kind
        title = event.title
        message = ChatTimelineTextProjection.displayMessage(for: event)
        activityPreviewText = ChatTimelineTextProjection.preview(from: message, maxCharacters: 220)
        activityDetailText = ChatTimelineTextProjection.detail(from: message, kind: event.kind)
        timestamp = event.timestamp
        sourceEventIDs = [event.id]
        changeSet = WorkspaceChangeSetParser.shouldInspect(event)
            ? WorkspaceChangeSetParser.changeSet(from: event)
            : nil
    }

    mutating func appendMessageFragment(_ fragment: String) {
        message = ChatTimelineTextProjection.append(fragment, to: message, kind: kind)
        activityPreviewText = ChatTimelineTextProjection.preview(from: message, maxCharacters: 220)
        activityDetailText = ChatTimelineTextProjection.detail(from: message, kind: kind)
    }
}

enum ChatTimelineBuilder {
    static func items(from events: [AgentStreamEvent]) -> [ChatTimelineItem] {
        var items: [ChatTimelineItem] = []
        var activeTextItem: ChatTimelineItem?
        var previousSignature: EventSignature?

        func flushActiveTextItem() {
            if let activeTextItem {
                items.append(activeTextItem)
            }
            activeTextItem = nil
        }

        for event in events {
            let signature = EventSignature(event: event)
            if signature == previousSignature {
                continue
            }
            previousSignature = signature

            if isThinkingCompletion(event) {
                if var active = activeTextItem, active.kind == .thinking {
                    active.title = event.title
                    if active.message.isEmpty {
                        active.message = event.message
                    }
                    active.timestamp = event.timestamp
                    active.sourceEventIDs.append(event.id)
                    activeTextItem = active
                } else {
                    flushActiveTextItem()
                    items.append(ChatTimelineItem(event: event))
                }
                continue
            }

            guard isCoalescibleTextEvent(event) else {
                flushActiveTextItem()
                items.append(ChatTimelineItem(event: event))
                continue
            }

            if var active = activeTextItem,
               active.kind == event.kind,
               active.title == event.title {
                active.appendMessageFragment(event.message)
                active.timestamp = event.timestamp
                active.sourceEventIDs.append(event.id)
                activeTextItem = active
            } else {
                flushActiveTextItem()
                activeTextItem = ChatTimelineItem(event: event)
            }
        }

        flushActiveTextItem()
        return items
    }

    private static func isCoalescibleTextEvent(_ event: AgentStreamEvent) -> Bool {
        switch event.kind {
        case .assistant:
            event.title == "Assistant"
        case .thinking:
            event.title == "Thinking"
        default:
            false
        }
    }

    private static func isThinkingCompletion(_ event: AgentStreamEvent) -> Bool {
        event.kind == .thinking && event.title == "Thinking Completed"
    }
}

enum WorkspaceChangeSetParser {
    fileprivate static let maxDiffCandidateCharacters = 80_000
    private static let maxPayloadTraversalDepth = 6
    private static let maxArrayPayloadItems = 40
    private static let diffPayloadKeys: Set<String> = ["diff", "patch", "unifiedDiff", "unified_diff"]

    static func shouldInspect(_ event: AgentStreamEvent) -> Bool {
        if event.message.looksLikeUnifiedDiffCandidate {
            return true
        }

        guard event.rawPayload != nil else { return false }
        switch event.kind {
        case .assistant, .result, .task, .toolCall:
            return true
        case .system, .status, .thinking, .request, .heartbeat, .done, .error, .unknown, .user:
            return false
        }
    }

    static func changeSet(from event: AgentStreamEvent) -> WorkspaceChangeSet? {
        let message = event.message.trimmingCharacters(in: .whitespacesAndNewlines)

        if message.looksLikeUnifiedDiffCandidate,
           let changeSet = parseUnifiedDiff(message, eventID: event.id) {
            return changeSet
        }

        if let payload = event.rawPayload,
           let changeSet = parseStructuredFileChanges(payload, eventID: event.id) {
            return changeSet
        }

        for candidate in diffStrings(from: event.rawPayload) {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.looksLikeUnifiedDiffCandidate else { continue }
            if let changeSet = parseUnifiedDiff(trimmed, eventID: event.id) {
                return changeSet
            }
        }

        return nil
    }

    private static func parseUnifiedDiff(_ text: String, eventID: String) -> WorkspaceChangeSet? {
        let diffText = extractDiffText(from: text)
        let lines = diffText.components(separatedBy: .newlines)
        guard lines.contains(where: { $0.hasPrefix("diff --git ") || $0.hasPrefix("--- ") || $0.hasPrefix("+++ ") }) else {
            return nil
        }

        let chunks = splitDiffChunks(lines)
        guard !chunks.isEmpty else { return nil }
        let bodyText = chunks.compactMap(\.diff).joined(separator: "\n\n")
        return WorkspaceChangeSet(
            id: "\(eventID)-changes",
            title: "File changes",
            changes: chunks,
            bodyText: bodyText
        )
    }

    private static func extractDiffText(from text: String) -> String {
        guard let fenceRange = text.range(of: "```diff") else { return text }
        let afterFence = text[fenceRange.upperBound...]
        guard let endRange = afterFence.range(of: "```") else { return String(afterFence) }
        return String(afterFence[..<endRange.lowerBound])
    }

    private static func splitDiffChunks(_ lines: [String]) -> [WorkspaceFileChange] {
        var chunks: [[String]] = []
        var current: [String] = []

        func flush() {
            guard !current.isEmpty else { return }
            chunks.append(current)
            current = []
        }

        for line in lines {
            if line.hasPrefix("diff --git "), !current.isEmpty {
                flush()
            }
            current.append(line)
        }
        flush()

        return chunks.compactMap(parseDiffChunk)
    }

    private static func parseDiffChunk(_ lines: [String]) -> WorkspaceFileChange? {
        let diff = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !diff.isEmpty else { return nil }
        let path = diffPath(from: lines)
        guard !path.isEmpty else { return nil }

        let additions = lines.reduce(0) { total, line in
            line.hasPrefix("+") && !line.hasPrefix("+++") ? total + 1 : total
        }
        let deletions = lines.reduce(0) { total, line in
            line.hasPrefix("-") && !line.hasPrefix("---") ? total + 1 : total
        }

        return WorkspaceFileChange(
            path: path,
            action: action(from: lines),
            additions: additions,
            deletions: deletions,
            diff: diff
        )
    }

    private static func diffPath(from lines: [String]) -> String {
        for prefix in ["+++ ", "--- "] {
            for line in lines where line.hasPrefix(prefix) {
                let path = normalizedDiffPath(String(line.dropFirst(prefix.count)))
                if !path.isEmpty, path != "/dev/null" {
                    return path
                }
            }
        }

        for line in lines where line.hasPrefix("diff --git ") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 4 {
                let path = normalizedDiffPath(String(parts[3]))
                if !path.isEmpty {
                    return path
                }
            }
        }

        return ""
    }

    private static func normalizedDiffPath(_ value: String) -> String {
        var path = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("a/") || path.hasPrefix("b/") {
            path = String(path.dropFirst(2))
        }
        return path
    }

    private static func action(from lines: [String]) -> WorkspaceFileChangeAction {
        if lines.contains(where: { $0.hasPrefix("rename from ") || $0.hasPrefix("rename to ") }) {
            return .renamed
        }
        if lines.contains(where: { $0.hasPrefix("new file mode ") || $0 == "--- /dev/null" }) {
            return .added
        }
        if lines.contains(where: { $0.hasPrefix("deleted file mode ") || $0 == "+++ /dev/null" }) {
            return .deleted
        }
        return .modified
    }

    private static func parseStructuredFileChanges(_ value: JSONValue, eventID: String) -> WorkspaceChangeSet? {
        let changes = structuredChanges(from: value)
        guard !changes.isEmpty else { return nil }
        let bodyText = changes.map { change in
            """
            Path: \(change.path)
            Kind: \(change.action.rawValue)
            Totals: +\(change.additions) -\(change.deletions)
            """
        }
        .joined(separator: "\n\n")
        return WorkspaceChangeSet(
            id: "\(eventID)-changes",
            title: "File changes",
            changes: changes,
            bodyText: bodyText
        )
    }

    private static func structuredChanges(from value: JSONValue, depth: Int = 0) -> [WorkspaceFileChange] {
        guard depth <= maxPayloadTraversalDepth else { return [] }
        switch value {
        case .object(let object):
            if let path = object.stringValue(forAny: ["path", "file", "filename", "filePath", "file_path"]),
               looksLikeFilePath(path) {
                return [
                    WorkspaceFileChange(
                        path: path,
                        action: action(from: object.stringValue(forAny: ["action", "kind", "type", "status"])),
                        additions: object.intValue(forAny: ["additions", "added", "linesAdded"]) ?? 0,
                        deletions: object.intValue(forAny: ["deletions", "deleted", "linesDeleted", "removals"]) ?? 0,
                        diff: object.stringValue(forAny: ["diff", "patch", "unifiedDiff"])
                    )
                ]
            }
            return object.values.flatMap { structuredChanges(from: $0, depth: depth + 1) }
        case .array(let array):
            return array.prefix(maxArrayPayloadItems).flatMap { structuredChanges(from: $0, depth: depth + 1) }
        case .string, .number, .bool, .null:
            return []
        }
    }

    private static func action(from value: String?) -> WorkspaceFileChangeAction {
        switch value?.lowercased() {
        case "added", "add", "create", "created", "new":
            .added
        case "deleted", "delete", "removed", "remove":
            .deleted
        case "renamed", "rename", "moved", "move":
            .renamed
        case "modified", "modify", "updated", "update", "edit", "edited":
            .modified
        default:
            .unknown
        }
    }

    private static func diffStrings(from value: JSONValue?, depth: Int = 0) -> [String] {
        guard let value else { return [] }
        guard depth <= maxPayloadTraversalDepth else { return [] }
        switch value {
        case .string:
            return []
        case .array(let array):
            return array.prefix(maxArrayPayloadItems).flatMap { diffStrings(from: $0, depth: depth + 1) }
        case .object(let object):
            return object.flatMap { key, value -> [String] in
                if diffPayloadKeys.contains(key) || diffPayloadKeys.contains(key.lowercased()),
                   case .string(let string) = value,
                   string.count <= maxDiffCandidateCharacters {
                    return [string]
                }
                return diffStrings(from: value, depth: depth + 1)
            }
        case .number, .bool, .null:
            return []
        }
    }

    private static func looksLikeFilePath(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("/") || trimmed.contains(".")
    }
}

private struct EventSignature: Equatable {
    var kind: StreamEventKind
    var title: String
    var message: String

    init(event: AgentStreamEvent) {
        kind = event.kind
        title = event.title
        message = event.message
    }
}

enum ChatTimelineTextProjection {
    private static let maxAssistantCharacters = 18_000
    private static let maxActivityCharacters = 2_000
    private static let maxActivityDetailCharacters = 2_400

    static func displayMessage(for event: AgentStreamEvent) -> String {
        bounded(
            event.message,
            maxCharacters: maxDisplayCharacters(for: event.kind),
            truncationMessage: "Details truncated for smoother chat performance."
        )
    }

    static func append(_ fragment: String, to message: String, kind: StreamEventKind) -> String {
        bounded(
            message + fragment,
            maxCharacters: maxDisplayCharacters(for: kind),
            truncationMessage: "Details truncated for smoother chat performance."
        )
    }

    static func detail(from message: String, kind: StreamEventKind) -> String {
        switch kind {
        case .assistant, .user:
            return message.trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            return bounded(
                message.trimmingCharacters(in: .whitespacesAndNewlines),
                maxCharacters: maxActivityDetailCharacters,
                truncationMessage: "Open the artifact or pull request for the complete output."
            )
        }
    }

    static func preview(from message: String, maxCharacters: Int) -> String {
        let sample = String(message.prefix(max(maxCharacters * 4, maxCharacters)))
        let flattened = sample
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return bounded(flattened, maxCharacters: maxCharacters, truncationMessage: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func maxDisplayCharacters(for kind: StreamEventKind) -> Int {
        switch kind {
        case .assistant, .user:
            return maxAssistantCharacters
        default:
            return maxActivityCharacters
        }
    }

    private static func bounded(_ text: String, maxCharacters: Int, truncationMessage: String) -> String {
        guard text.count > maxCharacters else { return text }
        let suffix = truncationMessage.isEmpty ? "" : "\n\n\(truncationMessage)"
        return String(text.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines) + suffix
    }
}

private extension String {
    var looksLikeUnifiedDiffCandidate: Bool {
        count <= WorkspaceChangeSetParser.maxDiffCandidateCharacters
            && (contains("diff --git ")
                || hasPrefix("--- ")
                || hasPrefix("+++ ")
                || contains("\n--- ")
                || contains("\n+++ ")
                || contains("```diff"))
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func stringValue(forAny keys: [String]) -> String? {
        for key in keys {
            if case .string(let value)? = self[key] {
                return value
            }
        }
        return nil
    }

    func intValue(forAny keys: [String]) -> Int? {
        for key in keys {
            switch self[key] {
            case .number(let value):
                return Int(value)
            case .string(let value):
                if let integer = Int(value) {
                    return integer
                }
            default:
                continue
            }
        }
        return nil
    }
}
