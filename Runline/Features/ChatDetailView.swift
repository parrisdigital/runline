import AVKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ChatDetailView: View {
    private static let maxPromptImages = 5
    private static let promptImageMaxDimension: CGFloat = 1600
    private static let promptImageJPEGQuality: CGFloat = 0.82
    private static let composerControlSize: CGFloat = 38

    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    var agent: Agent
    @State private var followUpText = ""
    @State private var followUpImages: [PromptImage] = []
    @State private var followUpFiles: [PromptFile] = []
    @State private var selectedFollowUpPhotoItems: [PhotosPickerItem] = []
    @State private var isLoadingFollowUpImages = false
    @State private var isFollowUpFileImporterPresented = false
    @State private var isLoadingFollowUpFiles = false
    @State private var followUpFileImportMessage: String?
    @State private var isArtifactsPresented = false
    @State private var followUpModelAgentID: Agent.ID?
    @State private var selectedFollowUpModelID: String?
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        let currentAgent = appState.agent(id: agent.id) ?? agent
        let latestRun = appState.runs(for: currentAgent).first
        let events = latestRun.map { appState.events(for: $0.id) } ?? []
        let timelineItems = ChatTimelineBuilder.items(from: events)
        let showsComposer = shouldShowComposer(agent: currentAgent, run: latestRun)

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    CloudChatHeaderCard(agent: currentAgent, run: latestRun)

                    if let latestRun {
                        if timelineItems.isEmpty {
                            CloudChatEmptyTimeline(
                                isStreamExpired: appState.isStreamExpired(runID: latestRun.id)
                            )
                        } else {
                            ForEach(timelineItems) { item in
                                ChatTimelineRow(item: item)
                                    .id(item.id)
                            }
                        }

                        if appState.isObserving(runID: latestRun.id) {
                            CloudRunListeningRow()
                        }
                    } else {
                        ContentUnavailableView(
                            "No Runs",
                            systemImage: "message",
                            description: Text("Runs appear after launch or follow-up.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, showsComposer ? 170 : 20)
            }
            .background(Color(uiColor: .systemBackground))
            .onChange(of: timelineItems.map(\.id)) { _, _ in
                withAnimation(.snappy(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .overlay(alignment: .bottom) {
            if showsComposer {
                followUpComposer(agent: currentAgent, run: latestRun)
            }
        }
        .navigationTitle(currentAgent.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await appState.refreshAgentDetail(agentID: currentAgent.id)
            if let latestRun = appState.runs(for: currentAgent).first {
                await appState.loadEvents(for: currentAgent, run: latestRun)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let latestRun, !latestRun.status.isTerminal {
                        Button(role: .destructive) {
                            Task {
                                await appState.cancel(agent: currentAgent, run: latestRun)
                            }
                        } label: {
                            Label("Cancel Run", systemImage: "stop.circle")
                        }
                    }

                    Button {
                        isArtifactsPresented = true
                    } label: {
                        Label("Artifacts", systemImage: "tray.full")
                    }

                    if let url = currentAgent.pullRequestURL {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Open Pull Request", systemImage: "arrow.up.right.square")
                        }
                    }

                    if appState.capabilities.supportsArchive {
                        if case .archived = currentAgent.status {
                            Button {
                                Task {
                                    await appState.unarchive(agent: currentAgent)
                                }
                            } label: {
                                Label("Unarchive", systemImage: "archivebox")
                            }
                        } else {
                            Button {
                                Task {
                                    await appState.archive(agent: currentAgent)
                                }
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                        }
                    }

                    if appState.capabilities.supportsDelete {
                        Button(role: .destructive) {
                            Task {
                                await appState.delete(agent: currentAgent)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Chat actions")
            }
        }
        .task {
            await appState.refreshAgentDetail(agentID: currentAgent.id)
        }
        .task(id: latestRun?.id) {
            guard let latestRun else { return }
            if latestRun.status.isTerminal {
                await appState.loadEvents(for: currentAgent, run: latestRun)
                _ = await appState.artifacts(for: currentAgent)
            } else {
                await appState.observeRun(agent: currentAgent, run: latestRun)
            }
        }
        .sheet(isPresented: $isArtifactsPresented) {
            ArtifactsSheet(agent: currentAgent)
        }
        .fileImporter(
            isPresented: $isFollowUpFileImporterPresented,
            allowedContentTypes: PromptFileLoader.allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            Task {
                await loadFollowUpFiles(from: result)
            }
        }
    }

    private func shouldShowComposer(agent: Agent, run: AgentRun?) -> Bool {
        guard run != nil else { return false }
        if case .active = agent.status {
            return true
        }
        return false
    }

    private func followUpComposer(agent: Agent, run: AgentRun?) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 10) {
                    followUpComposerContent(agent: agent, run: run)
                }
            } else {
                followUpComposerContent(agent: agent, run: run)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func followUpComposerContent(agent: Agent, run: AgentRun?) -> some View {
        VStack(spacing: 8) {
            if let run, !run.status.isTerminal {
                CloudRunProgressBar(status: run.status)
            }

            if shouldShowFollowUpAttachments {
                followUpAttachmentStrip
            }

            if let followUpFileImportMessage {
                Text(followUpFileImportMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }

            composerInputSurface(agent: agent, run: run)
        }
    }

    private func composerInputSurface(agent: Agent, run: AgentRun?) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(run?.status.isTerminal == false ? "Steer this run" : "Ask for follow-up changes")
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                        .padding(.horizontal, 18)
                        .padding(.top, 15)
                }

                TextField("", text: $followUpText, axis: .vertical)
                    .lineLimit(2...7)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .focused($isComposerFocused)
                    .padding(.horizontal, 18)
                    .padding(.top, 15)
                    .padding(.bottom, 12)
            }

            Divider()
                .opacity(0.32)

            HStack(spacing: 10) {
                attachmentMenuButton

                CloudComposerModelMenu(
                    models: appState.models,
                    selection: followUpModelBinding(for: agent)
                )

                Spacer(minLength: 0)

                if let run, !run.status.isTerminal {
                    Button {
                        Task {
                            await appState.cancel(agent: agent, run: run)
                        }
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.red)
                            .frame(width: Self.composerControlSize, height: Self.composerControlSize)
                            .composerGlassSurface(cornerRadius: Self.composerControlSize / 2, interactive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel run")
                }

                Button {
                    sendFollowUp(agent: agent)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(canSendFollowUp ? Color.white : Color(uiColor: .systemGray))
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(canSendFollowUp ? Color(uiColor: .systemBlue) : Color(uiColor: .systemGray5))
                        )
                        .shadow(color: canSendFollowUp ? Color.blue.opacity(0.28) : .clear, radius: 10, y: 5)
                }
                .buttonStyle(.plain)
                .disabled(!canSendFollowUp)
                .accessibilityLabel("Send follow-up")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.90)
        )
        .composerGlassSurface(cornerRadius: 28)
        .shadow(color: Color.black.opacity(0.10), radius: 18, y: 8)
    }

    private var attachmentMenuButton: some View {
        Menu {
            if appState.capabilities.supportsImagesInPrompt {
                PhotosPicker(
                    selection: $selectedFollowUpPhotoItems,
                    maxSelectionCount: Self.maxPromptImages,
                    matching: .images
                ) {
                    Label("Photos", systemImage: "photo")
                }
                .disabled(isLoadingFollowUpImages || followUpImages.count >= Self.maxPromptImages)
            }

            Button {
                isFollowUpFileImporterPresented = true
            } label: {
                Label("Files", systemImage: "doc")
            }
            .disabled(isLoadingFollowUpFiles || followUpFiles.count >= PromptFileLoader.maxFiles)
        } label: {
            Image(systemName: "paperclip")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(uiColor: .systemBlue))
                .frame(width: Self.composerControlSize, height: Self.composerControlSize)
                .composerGlassSurface(cornerRadius: Self.composerControlSize / 2, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Attach files or images")
        .onChange(of: selectedFollowUpPhotoItems) { _, items in
            Task {
                await loadFollowUpImages(from: items)
            }
        }
    }

    private var shouldShowFollowUpAttachments: Bool {
        !followUpImages.isEmpty || !followUpFiles.isEmpty || isLoadingFollowUpImages || isLoadingFollowUpFiles
    }

    private var followUpAttachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(followUpImages) { image in
                    HStack(spacing: 6) {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                        Text("\(image.width) x \(image.height)")
                            .font(.caption)
                        Button {
                            removeFollowUpImage(image)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove image")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .composerGlassSurface(cornerRadius: 14)
                }

                ForEach(followUpFiles) { file in
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                        Text("\(file.filename) - \(file.sizeDescription)")
                            .font(.caption)
                        Button {
                            removeFollowUpFile(file)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove file")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .composerGlassSurface(cornerRadius: 14)
                }

                if isLoadingFollowUpImages || isLoadingFollowUpFiles {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.horizontal, 10)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var canSendFollowUp: Bool {
        !isLoadingFollowUpImages
            && !isLoadingFollowUpFiles
            && !followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendFollowUp(agent: Agent) {
        guard canSendFollowUp else { return }
        let prompt = AgentPrompt(
            text: followUpText.trimmingCharacters(in: .whitespacesAndNewlines),
            images: followUpImages,
            files: followUpFiles
        )
        followUpText = ""
        followUpImages = []
        followUpFiles = []
        selectedFollowUpPhotoItems = []
        followUpFileImportMessage = nil
        isComposerFocused = false
        Task {
            await appState.createFollowUp(
                agent: agent,
                prompt: prompt,
                modelID: selectedFollowUpModelID(for: agent)
            )
            if let latestRun = appState.runs(for: agent).first {
                await appState.observeRun(agent: agent, run: latestRun)
            }
        }
    }

    private func followUpModelBinding(for agent: Agent) -> Binding<String?> {
        Binding {
            selectedFollowUpModelID(for: agent)
        } set: { modelID in
            followUpModelAgentID = agent.id
            selectedFollowUpModelID = NewChatModelPickerOptions.modelID(from: modelID)
        }
    }

    private func selectedFollowUpModelID(for agent: Agent) -> String? {
        if followUpModelAgentID == agent.id {
            return selectedFollowUpModelID
        }
        return NewChatModelPickerOptions.modelID(from: agent.modelID)
    }

    private func loadFollowUpImages(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        isLoadingFollowUpImages = true
        defer {
            isLoadingFollowUpImages = false
            selectedFollowUpPhotoItems = []
        }

        var images = followUpImages
        for item in items where images.count < Self.maxPromptImages {
            guard let originalData = try? await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: originalData),
                  let promptImage = normalizedPromptImage(from: uiImage) else {
                continue
            }
            images.append(promptImage)
        }
        followUpImages = images
    }

    private func normalizedPromptImage(from image: UIImage) -> PromptImage? {
        let largestDimension = max(image.size.width, image.size.height)
        let scale = largestDimension > Self.promptImageMaxDimension ? Self.promptImageMaxDimension / largestDimension : 1
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let normalizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let data = normalizedImage.jpegData(compressionQuality: Self.promptImageJPEGQuality) else { return nil }
        return PromptImage(data: data, width: Int(targetSize.width), height: Int(targetSize.height))
    }

    private func removeFollowUpImage(_ image: PromptImage) {
        followUpImages.removeAll { $0.id == image.id }
        selectedFollowUpPhotoItems = []
    }

    private func loadFollowUpFiles(from result: Result<[URL], Error>) async {
        isLoadingFollowUpFiles = true
        defer { isLoadingFollowUpFiles = false }

        switch result {
        case .success(let urls):
            let loadResult = PromptFileLoader.loadFiles(from: urls, existingFiles: followUpFiles)
            followUpFiles = loadResult.files
            followUpFileImportMessage = fileImportMessage(from: loadResult)
        case .failure(let error):
            followUpFileImportMessage = "Could not load files: \(error.localizedDescription)"
        }
    }

    private func removeFollowUpFile(_ file: PromptFile) {
        followUpFiles.removeAll { $0.id == file.id }
        followUpFileImportMessage = nil
    }

    private func fileImportMessage(from result: PromptFileLoadResult) -> String? {
        guard !result.skippedFilenames.isEmpty else { return nil }
        return "Skipped unsupported or large files: \(result.skippedFilenames.joined(separator: ", "))"
    }
}

private struct CloudChatHeaderCard: View {
    var agent: Agent
    var run: AgentRun?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("Cursor Cloud", systemImage: "cloud.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)

                Spacer(minLength: 8)

                if let run {
                    RunStatusBadge(status: run.status)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(agent.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)

                Text(agent.repository.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CloudChatContextChip(systemName: "arrow.triangle.branch", title: agent.branchName)
                    CloudChatContextChip(systemName: "cpu", title: agent.modelID)
                    if let run {
                        CloudChatContextChip(systemName: "clock", title: run.updatedAtDescription)
                    }

                    if agent.artifactCount > 0 {
                        CloudChatContextChip(systemName: "tray.full", title: "\(agent.artifactCount) artifact\(agent.artifactCount == 1 ? "" : "s")")
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct CloudChatContextChip: View {
    var systemName: String
    var title: String

    var body: some View {
        Label(title, systemImage: systemName)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color(uiColor: .tertiarySystemGroupedBackground)))
    }
}

private struct CloudChatEmptyTimeline: View {
    var isStreamExpired: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CloudAvatar(
                systemName: isStreamExpired ? "clock.badge.exclamationmark" : "dot.radiowaves.left.and.right",
                tint: isStreamExpired ? .orange : .blue
            )

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Cursor")
                        .font(.caption.weight(.semibold))
                    Text(isStreamExpired ? "Paused" : "Starting")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(isStreamExpired ? "Live updates are paused for this run. Pull to refresh for the latest Cloud Agent state." : "Waiting for the first Cloud Agent update.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 8)
            }

            Spacer(minLength: 24)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ChatTimelineRow: View {
    var item: ChatTimelineItem

    var body: some View {
        switch item.kind {
        case .user:
            UserMessageRow(item: item)
        case .assistant:
            AssistantMessageRow(item: item)
        case .status, .done, .heartbeat:
            CloudStatusEventPill(item: item)
        default:
            CloudActivityDisclosureRow(item: item)
        }
    }
}

private struct UserMessageRow: View {
    var item: ChatTimelineItem

    var body: some View {
        HStack(alignment: .top) {
            Spacer(minLength: 52)

            VStack(alignment: .trailing, spacing: 5) {
                TimelineMessageText(
                    message: item.message,
                    isTechnical: false,
                    rendersMarkdown: false,
                    foregroundColor: .white
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.blue)
                )

                Text(item.timestamp)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 560, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AssistantMessageRow: View {
    var item: ChatTimelineItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CloudAvatar(systemName: "sparkles", tint: .blue)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Cursor")
                        .font(.caption.weight(.semibold))
                    Text(item.timestamp)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                TimelineMessageText(
                    message: item.message,
                    isTechnical: false,
                    rendersMarkdown: true,
                    foregroundColor: .primary
                )
                .padding(.trailing, 8)
            }
            .frame(maxWidth: 680, alignment: .leading)

            Spacer(minLength: 24)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CloudActivityDisclosureRow: View {
    var item: ChatTimelineItem
    @State private var isExpanded: Bool

    init(item: ChatTimelineItem) {
        self.item = item
        _isExpanded = State(initialValue: item.kind == .error || item.kind == .request)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if isExpanded {
                TimelineMessageText(
                    message: item.message,
                    isTechnical: isTechnical,
                    rendersMarkdown: rendersMarkdown,
                    foregroundColor: messageColor
                )
                .padding(.top, 8)
                .padding(.leading, 34)
            }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 20)

                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(item.timestamp)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .tint(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.65), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        case .status:
            "checkmark.circle"
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
        default:
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

private struct CloudStatusEventPill: View {
    var item: ChatTimelineItem

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            Label(item.title, systemImage: symbolName)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(color.opacity(0.10)))
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var symbolName: String {
        switch item.kind {
        case .done:
            "checkmark.seal"
        case .heartbeat:
            "waveform.path.ecg"
        default:
            "checkmark.circle"
        }
    }

    private var color: Color {
        switch item.kind {
        case .done, .status:
            .green
        default:
            .secondary
        }
    }
}

private struct CloudComposerModelMenu: View {
    var models: [AgentModel]
    @Binding var selection: String?

    var body: some View {
        Menu {
            Button {
                selection = nil
            } label: {
                modelMenuLabel(title: "Default", isSelected: selection == nil)
            }

            ForEach(NewChatModelPickerOptions.visibleModels(from: models)) { model in
                Button {
                    selection = model.id
                } label: {
                    modelMenuLabel(title: model.displayName, isSelected: selection == model.id)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cloud")
                    .font(.caption.weight(.semibold))

                Text("Cloud")
                    .font(.caption.weight(.medium))

                Rectangle()
                    .fill(Color(uiColor: .separator).opacity(0.45))
                    .frame(width: 1, height: 12)

                Text(modelTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .composerGlassSurface(cornerRadius: 16, interactive: true)
        }
        .menuIndicator(.hidden)
        .tint(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Select Cloud Agent model. Current model \(modelTitle)")
    }

    private var modelTitle: String {
        guard let selection else { return "Default" }
        if let model = models.first(where: { $0.id == selection }) {
            return model.displayName
        }
        return selection
    }

    private func modelMenuLabel(title: String, isSelected: Bool) -> some View {
        Label(title, systemImage: isSelected ? "checkmark" : "cpu")
    }
}

private struct CloudAvatar: View {
    var systemName: String
    var tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(Circle().fill(tint.opacity(0.12)))
    }
}

private struct CloudRunListeningRow: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Listening for Cursor events")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct CloudRunProgressBar: View {
    var status: RunStatus

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(status == .creating ? "Starting Cloud Agent" : "Cloud Agent running")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }
}

private extension View {
    @ViewBuilder
    func composerGlassSurface(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            if interactive {
                self
                    .glassEffect(.regular.interactive(), in: shape)
                    .overlay(shape.stroke(Color(uiColor: .separator).opacity(0.26), lineWidth: 0.5))
            } else {
                self
                    .glassEffect(.regular, in: shape)
                    .overlay(shape.stroke(Color(uiColor: .separator).opacity(0.24), lineWidth: 0.5))
            }
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color(uiColor: .separator).opacity(0.26), lineWidth: 0.5))
        }
    }
}

struct ArtifactsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    var agent: Agent
    @State private var artifacts: [Artifact] = []
    @State private var selectedArtifact: Artifact?

    var body: some View {
        NavigationStack {
            List {
                if artifacts.isEmpty {
                    ContentUnavailableView(
                        "No Artifacts",
                        systemImage: "tray",
                        description: Text("Artifacts appear after Cursor produces files.")
                    )
                } else {
                    Section("Artifacts") {
                        ForEach(artifacts) { artifact in
                            Button {
                                selectedArtifact = artifact
                            } label: {
                                ArtifactListRow(artifact: artifact)
                            }
                        }
                    }
                }

                if let pullRequestURL = agent.pullRequestURL {
                    Section {
                        Link(destination: pullRequestURL) {
                            Label("Open Pull Request", systemImage: "arrow.up.right.square")
                        }
                    }
                }
            }
            .navigationTitle("Artifacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                artifacts = await appState.artifacts(for: agent, forceRefresh: true)
            }
            .sheet(item: $selectedArtifact) { artifact in
                ArtifactPreviewView(agentID: agent.id, artifact: artifact)
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

private struct ArtifactPreviewView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    var agentID: Agent.ID
    var artifact: Artifact
    @State private var signedURL: URL?
    @State private var textPreview = ""
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                preview

                VStack(alignment: .leading, spacing: 4) {
                    Text(artifact.path)
                        .font(.caption.monospaced())
                        .lineLimit(2)
                        .textSelection(.enabled)

                    Text("\(artifact.sizeDescription) / \(artifact.updatedAtDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .navigationTitle("Artifact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let signedURL {
                        ShareLink(item: signedURL)
                        Button {
                            openURL(signedURL)
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                        }
                        .accessibilityLabel("Open artifact")
                    }
                }
            }
            .task(id: artifact.id) {
                await loadSignedURL()
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 220)
        } else if let signedURL {
            switch artifact.kind {
            case .screenshot:
                AsyncImage(url: signedURL) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    ProgressView()
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            case .video:
                VideoPlayer(player: AVPlayer(url: signedURL))
                    .frame(height: 240)
            case .log:
                if textPreview.isEmpty {
                    ContentUnavailableView("Log Preview", systemImage: "doc.text")
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    ScrollView {
                        Text(textPreview)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                }
            case .file:
                ContentUnavailableView("File Artifact", systemImage: "doc")
                    .frame(maxWidth: .infinity, minHeight: 220)
            }
        } else {
            ContentUnavailableView("Artifact Unavailable", systemImage: "exclamationmark.triangle")
                .frame(maxWidth: .infinity, minHeight: 220)
        }
    }

    private func loadSignedURL() async {
        isLoading = true
        signedURL = await appState.downloadArtifact(agentID: agentID, path: artifact.path)
        if artifact.kind == .log, let signedURL {
            textPreview = await loadTextPreview(from: signedURL)
        }
        isLoading = false
    }

    private func loadTextPreview(from url: URL) async -> String {
        guard let (data, _) = try? await URLSession.shared.data(from: url), !data.isEmpty else {
            return ""
        }
        let maxBytes = 16 * 1024
        let clipped = data.prefix(maxBytes)
        let text = String(decoding: clipped, as: UTF8.self)
        return data.count > maxBytes ? text + "\n..." : text
    }
}
