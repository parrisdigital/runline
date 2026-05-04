import SwiftUI

struct AgentListRow: View {
    var agent: Agent
    var run: AgentRun?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .foregroundStyle(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(agent.name)
                    .font(.body)
                    .lineLimit(1)

                Text("\(agent.repository.displayName) / \(agent.branchName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if let run {
                    RunStatusBadge(status: run.status)
                }
                Text(agent.updatedAtDescription)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var symbolName: String {
        switch run?.status {
        case .some(.finished):
            "checkmark.circle"
        case .some(.error):
            "exclamationmark.triangle"
        case .some(.cancelled):
            "stop.circle"
        case .some(.running), .some(.creating):
            "dot.radiowaves.left.and.right"
        default:
            "message"
        }
    }

    private var color: Color {
        switch run?.status {
        case .some(.finished):
            .green
        case .some(.error):
            .red
        case .some(.cancelled):
            .secondary
        case .some(.running), .some(.creating):
            .blue
        default:
            .secondary
        }
    }
}

struct RepositoryListRow: View {
    var repository: Repository
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(repository.displayName)
                    .lineLimit(1)
                Text(repository.defaultBranch.isEmpty ? "Default branch from Cursor" : repository.defaultBranch)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ModelListRow: View {
    var model: AgentModel
    var isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.displayName)
                Text(model.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(String(repeating: "$", count: max(model.costTier, 1)))
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
            }
        }
    }
}

struct RunStatusBadge: View {
    var status: RunStatus

    var body: some View {
        Text(status.title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .finished:
            .green
        case .error:
            .red
        case .cancelled, .expired:
            .secondary
        case .creating, .running:
            .blue
        case .unknown:
            .secondary
        }
    }
}

struct StreamEventListRow: View {
    var item: ChatTimelineItem

    init(event: AgentStreamEvent) {
        item = ChatTimelineItem(event: event)
    }

    init(item: ChatTimelineItem) {
        self.item = item
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(item.timestamp)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(item.message)
                    .font(isTechnical ? .caption.monospaced() : .callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var isTechnical: Bool {
        item.kind == .toolCall || item.kind == .result || item.kind == .error
    }

    private var symbolName: String {
        switch item.kind {
        case .system:
            "gearshape"
        case .user:
            "person"
        case .status:
            "checkmark.circle"
        case .assistant:
            "sparkles"
        case .thinking:
            "brain"
        case .toolCall:
            "terminal"
        case .task:
            "checklist"
        case .request:
            "questionmark.bubble"
        case .result:
            "doc.text"
        case .heartbeat:
            "waveform.path.ecg"
        case .error:
            "exclamationmark.triangle"
        case .done:
            "checkmark.seal"
        case .unknown:
            "circle"
        }
    }

    private var color: Color {
        switch item.kind {
        case .status, .done:
            .green
        case .error:
            .red
        case .thinking, .request:
            .orange
        case .assistant, .toolCall, .task, .result:
            .blue
        default:
            .secondary
        }
    }
}

struct ArtifactListRow: View {
    var artifact: Artifact

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(artifact.path.replacingOccurrences(of: "artifacts/", with: ""))
                    .lineLimit(1)
                Text("\(artifact.sizeDescription) / \(artifact.updatedAtDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbolName)
                .foregroundStyle(.blue)
        }
    }

    private var symbolName: String {
        switch artifact.kind {
        case .screenshot:
            "photo"
        case .video:
            "play.rectangle"
        case .log:
            "doc.text"
        case .file:
            "doc"
        }
    }
}
