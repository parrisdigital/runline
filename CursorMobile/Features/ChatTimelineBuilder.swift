import Foundation

struct ChatTimelineItem: Identifiable, Hashable {
    var id: String
    var runID: String
    var kind: StreamEventKind
    var title: String
    var message: String
    var timestamp: String
    var sourceEventIDs: [String]

    init(event: AgentStreamEvent) {
        id = event.id
        runID = event.runID
        kind = event.kind
        title = event.title
        message = event.message
        timestamp = event.timestamp
        sourceEventIDs = [event.id]
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
                active.message += event.message
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
