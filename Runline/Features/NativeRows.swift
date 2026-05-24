import SwiftUI

struct AgentListRow: View {
    var agent: Agent
    var run: AgentRun?
    var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.12))
                    Image(systemName: symbolName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(color)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(agent.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)

                    Text(agent.repository.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let run {
                    RunStatusBadge(status: run.status)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }

            HStack(spacing: 8) {
                AgentMetadataChip(systemName: "arrow.triangle.branch", title: agent.branchName)
                AgentMetadataChip(systemName: "cpu", title: agent.modelID)
                if agent.artifactCount > 0 {
                    AgentMetadataChip(systemName: "tray.full", title: "\(agent.artifactCount)")
                }
                Spacer(minLength: 0)
                Text(agent.updatedAtDescription)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .lineLimit(1)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Color.blue.opacity(0.45) : Color(uiColor: .separator).opacity(0.12), lineWidth: 0.75)
        )
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

private struct AgentMetadataChip: View {
    var systemName: String
    var title: String

    var body: some View {
        Label(title, systemImage: systemName)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            )
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

enum ComposerLabelFormatter {
    static func modelTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return title }

        let parts = trimmed
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map(String.init)

        guard !parts.isEmpty else { return trimmed }

        return parts.map { part in
            switch part.lowercased() {
            case "gpt":
                "GPT"
            case "claude":
                "Claude"
            case "sonnet":
                "Sonnet"
            case "thinking":
                "Thinking"
            case "composer":
                "Composer"
            default:
                part
            }
        }
        .joined(separator: " ")
    }
}

struct ComposerControlPill: View {
    var systemName: String?
    var title: String
    var detail: String?
    var showsChevron = true
    var maxWidth: CGFloat?
    var tint: Color = .secondary

    var body: some View {
        content
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .composerControlPillSurface
            .contentShape(Capsule())
    }

    private var content: some View {
        HStack(spacing: 6) {
            if let systemName {
                Image(systemName: systemName)
                    .font(.caption.weight(.semibold))
            }

            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    var composerControlPillSurface: some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: Capsule())
                .overlay(Capsule().stroke(Color(uiColor: .separator).opacity(0.24), lineWidth: 0.5))
        } else {
            background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color(uiColor: .separator).opacity(0.24), lineWidth: 0.5))
        }
    }
}

struct RunStatusBadge: View {
    var status: RunStatus

    var body: some View {
        Text(status.title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
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

                TimelineMessageText(
                    message: item.message,
                    isTechnical: isTechnical,
                    rendersMarkdown: rendersMarkdown,
                    foregroundColor: messageColor
                )
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var isTechnical: Bool {
        item.kind == .toolCall || item.kind == .result || item.kind == .error
    }

    private var rendersMarkdown: Bool {
        switch item.kind {
        case .assistant, .thinking, .task, .request:
            true
        default:
            false
        }
    }

    private var messageColor: Color {
        switch item.kind {
        case .assistant, .user:
            .primary
        default:
            .secondary
        }
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

struct TimelineMessageText: View {
    var message: String
    var isTechnical: Bool
    var rendersMarkdown: Bool
    var foregroundColor: Color

    var body: some View {
        Group {
            if isTechnical || !rendersMarkdown {
                Text(message)
                    .font(isTechnical ? .caption.monospaced() : .callout)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(TimelineMarkdownParser.blocks(from: message).enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                }
            }
        }
        .foregroundStyle(foregroundColor)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: TimelineMarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            InlineMarkdownText(text: text, font: headingFont(level))
                .foregroundStyle(.primary)
                .padding(.top, level == 1 ? 4 : 2)
        case .paragraph(let text):
            InlineMarkdownText(text: text, font: .callout)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                InlineMarkdownText(text: text, font: .callout)
            }
        case .numbered(let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.tertiary)
                InlineMarkdownText(text: text, font: .callout)
            }
        case .code(let text):
            Text(text)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1:
            .headline
        case 2:
            .subheadline.weight(.semibold)
        default:
            .callout.weight(.semibold)
        }
    }
}

private struct InlineMarkdownText: View {
    var text: String
    var font: Font

    var body: some View {
        if let attributedText {
            Text(attributedText)
                .font(font)
        } else {
            Text(text)
                .font(font)
        }
    }

    private var attributedText: AttributedString? {
        try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
    }
}

private enum TimelineMarkdownBlock: Hashable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case numbered(marker: String, text: String)
    case code(String)
}

private enum TimelineMarkdownParser {
    static func blocks(from message: String) -> [TimelineMarkdownBlock] {
        var blocks: [TimelineMarkdownBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String] = []
        var isInCodeBlock = false

        func flushParagraph() {
            let paragraph = paragraphLines
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph))
            }
            paragraphLines.removeAll()
        }

        for line in normalizedLines(from: message) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if isInCodeBlock {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    isInCodeBlock = false
                } else {
                    flushParagraph()
                    isInCodeBlock = true
                }
                continue
            }

            if isInCodeBlock {
                codeLines.append(line)
                continue
            }

            guard !trimmed.isEmpty else {
                flushParagraph()
                continue
            }

            if let heading = heading(from: trimmed) {
                flushParagraph()
                blocks.append(heading)
                continue
            }

            if let bullet = bullet(from: trimmed) {
                flushParagraph()
                blocks.append(.bullet(bullet))
                continue
            }

            if let numbered = numberedItem(from: trimmed) {
                flushParagraph()
                blocks.append(numbered)
                continue
            }

            paragraphLines.append(trimmed)
        }

        if isInCodeBlock, !codeLines.isEmpty {
            blocks.append(.code(codeLines.joined(separator: "\n")))
        }
        flushParagraph()

        return blocks.isEmpty ? [.paragraph(message)] : blocks
    }

    private static func normalizedLines(from message: String) -> [String] {
        message
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private static func heading(from line: String) -> TimelineMarkdownBlock? {
        let marker = line.prefix { $0 == "#" }
        guard !marker.isEmpty, marker.count <= 6 else { return nil }

        let textStart = line.index(line.startIndex, offsetBy: marker.count)
        guard textStart < line.endIndex, line[textStart] == " " else { return nil }

        let text = String(line[line.index(after: textStart)...])
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return .heading(level: marker.count, text: text)
    }

    private static func bullet(from line: String) -> String? {
        for marker in ["- ", "* "] where line.hasPrefix(marker) {
            let text = String(line.dropFirst(marker.count))
                .trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private static func numberedItem(from line: String) -> TimelineMarkdownBlock? {
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }

        let number = line[..<dotIndex]
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }

        let textStart = line.index(after: dotIndex)
        guard textStart < line.endIndex, line[textStart] == " " else { return nil }

        let text = String(line[line.index(after: textStart)...])
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return .numbered(marker: "\(number).", text: text)
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
