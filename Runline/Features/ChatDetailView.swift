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
    @State private var queuedFollowUp: QueuedFollowUpDraft?
    @State private var isTimelineScrollPaused = false
    @State private var timelineScrollResumeTask: Task<Void, Never>?
    @State private var timelineSnapshot = ChatTimelineSnapshot.empty
    @State private var workspaceHandoffPresentation: WorkspaceHandoffPresentation?
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        let currentAgent = appState.agent(id: agent.id) ?? agent
        let latestRun = appState.runs(for: currentAgent).first
        let events = latestRun.map { appState.events(for: $0.id) } ?? []
        let timelineSignature = ChatTimelineEventSignature(runID: latestRun?.id, events: events)
        let timelineItems = timelineSnapshot.runID == latestRun?.id ? timelineSnapshot.items : []
        let timelineSections = timelineSnapshot.runID == latestRun?.id ? timelineSnapshot.sections : []
        let timelineItemIDs = timelineSnapshot.runID == latestRun?.id ? timelineSnapshot.itemIDs : []
        let showsComposer = shouldShowComposer(agent: currentAgent, run: latestRun)

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ConversationHeaderCard(
                        agent: currentAgent,
                        run: latestRun,
                        onCreateWorkspace: canCreateWorkspaceFromGeneralChat(agent: currentAgent) ? {
                            workspaceHandoffPresentation = WorkspaceHandoffPresentation(
                                agent: currentAgent,
                                events: events
                            )
                        } : nil
                    )

                    if let latestRun {
                        if timelineItems.isEmpty {
                            CloudChatEmptyTimeline(
                                runtimeMode: currentAgent.runtimeMode,
                                runStatus: latestRun.status,
                                isStreamExpired: appState.isStreamExpired(runID: latestRun.id)
                            )
                        } else {
                            ForEach(timelineSections) { section in
                                ChatTimelineSectionView(section: section)
                                    .id(section.id)
                            }
                        }

                        if appState.isObserving(runID: latestRun.id) {
                            CloudRunListeningRow(runtimeMode: currentAgent.runtimeMode)
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
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { _ in
                        pauseTimelineAutoScroll()
                    }
                    .onEnded { _ in
                        resumeTimelineAutoScrollAfterInteraction()
                    }
            )
            .onChange(of: timelineItemIDs) { _, _ in
                guard !isTimelineScrollPaused else { return }
                if currentAgent.runtimeMode == .sdkBridge {
                    proxy.scrollTo("bottom", anchor: .bottom)
                } else {
                    withAnimation(.snappy(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
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

                    if canCreateWorkspaceFromGeneralChat(agent: currentAgent) {
                        Button {
                            workspaceHandoffPresentation = WorkspaceHandoffPresentation(
                                agent: currentAgent,
                                events: events
                            )
                        } label: {
                            Label("Create Workspace", systemImage: "folder.badge.plus")
                        }
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
        .task(id: timelineSignature) {
            await rebuildTimelineSnapshot(
                runID: latestRun?.id,
                events: events,
                signature: timelineSignature
            )
        }
        .task(id: latestRun?.id) {
            guard let latestRun else { return }
            if latestRun.status.isTerminal {
                await appState.loadEvents(for: currentAgent, run: latestRun)
                _ = await appState.artifacts(for: currentAgent)
                await sendQueuedFollowUpIfNeeded(agent: currentAgent)
            } else {
                await appState.observeRun(agent: currentAgent, run: latestRun)
                if let refreshedRun = appState.runs(for: currentAgent).first,
                   refreshedRun.status.isTerminal {
                    await sendQueuedFollowUpIfNeeded(agent: currentAgent)
                }
            }
        }
        .onChange(of: latestRun?.status) { _, status in
            guard status?.isTerminal == true else { return }
            Task {
                await sendQueuedFollowUpIfNeeded(agent: currentAgent)
            }
        }
        .sheet(isPresented: $isArtifactsPresented) {
            ArtifactsSheet(agent: currentAgent)
        }
        .sheet(item: $workspaceHandoffPresentation) { presentation in
            GeneralChatWorkspaceHandoffSheet(presentation: presentation) { repository, branch, instruction in
                await createWorkspaceFromGeneralChat(
                    presentation: presentation,
                    repository: repository,
                    branch: branch,
                    instruction: instruction
                ) != nil
            }
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
        .onDisappear {
            timelineScrollResumeTask?.cancel()
            timelineScrollResumeTask = nil
        }
    }

    private func shouldShowComposer(agent: Agent, run: AgentRun?) -> Bool {
        guard run != nil else { return false }
        if case .active = agent.status {
            return true
        }
        return false
    }

    private func canCreateWorkspaceFromGeneralChat(agent: Agent) -> Bool {
        agent.runtimeMode == .sdkBridge && agent.repository.url.absoluteString.contains("general-chat")
    }

    private func createWorkspaceFromGeneralChat(
        presentation: WorkspaceHandoffPresentation,
        repository: Repository,
        branch: String?,
        instruction: String
    ) async -> AgentLaunchResult? {
        await appState.createWorkspaceFromGeneralChat(
            agent: presentation.agent,
            events: presentation.events,
            repository: repository,
            branch: branch,
            instruction: instruction
        )
    }

    private func rebuildTimelineSnapshot(
        runID: AgentRun.ID?,
        events: [AgentStreamEvent],
        signature: ChatTimelineEventSignature
    ) async {
        guard timelineSnapshot.signature != signature else { return }
        try? await Task.sleep(nanoseconds: 90_000_000)
        guard !Task.isCancelled else { return }
        let items = ChatTimelineBuilder.items(from: events)
        timelineSnapshot = ChatTimelineSnapshot(runID: runID, signature: signature, items: items)
    }

    private func pauseTimelineAutoScroll() {
        timelineScrollResumeTask?.cancel()
        timelineScrollResumeTask = nil
        guard !isTimelineScrollPaused else { return }
        isTimelineScrollPaused = true
    }

    private func resumeTimelineAutoScrollAfterInteraction() {
        timelineScrollResumeTask?.cancel()
        timelineScrollResumeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            isTimelineScrollPaused = false
        }
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
                CloudRunProgressBar(status: run.status, runtimeMode: agent.runtimeMode, hasQueuedFollowUp: queuedFollowUp != nil)
            }

            if let queuedFollowUp {
                QueuedFollowUpRow(draft: queuedFollowUp) {
                    restoreQueuedFollowUp(queuedFollowUp)
                } onCancel: {
                    self.queuedFollowUp = nil
                }
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
                    Text(composerPlaceholder(agent: agent, run: run))
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
                    runtimeMode: agent.runtimeMode,
                    selection: followUpModelBinding(for: agent)
                )

                Spacer(minLength: 0)

                primaryComposerActionButton(agent: agent, run: run)
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
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .regular))
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

    @ViewBuilder
    private func primaryComposerActionButton(agent: Agent, run: AgentRun?) -> some View {
        if let run, !run.status.isTerminal {
            if agent.runtimeMode == .sdkBridge, canSendFollowUp {
                Button {
                    queueFollowUp(agent: agent)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color(uiColor: .systemBlue)))
                        .shadow(color: Color.blue.opacity(0.28), radius: 10, y: 5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(queuedFollowUp == nil ? "Queue follow-up" : "Replace queued follow-up")
            } else {
                Button {
                    Task {
                        await appState.cancel(agent: agent, run: run)
                    }
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color(uiColor: .systemRed)))
                        .shadow(color: Color.red.opacity(0.26), radius: 10, y: 5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel run")
            }
        } else {
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

    private func composerPlaceholder(agent: Agent, run: AgentRun?) -> String {
        guard run?.status.isTerminal == false else { return "Ask for follow-up changes" }
        return agent.runtimeMode == .sdkBridge ? "Message Cursor while it works" : "Steer this run"
    }

    private func sendFollowUp(agent: Agent) {
        guard let draft = currentFollowUpDraft(agent: agent) else { return }
        clearFollowUpComposer()
        isComposerFocused = false
        Task {
            await appState.createFollowUp(
                agent: agent,
                prompt: draft.prompt,
                modelID: draft.modelID
            )
            if let latestRun = appState.runs(for: agent).first {
                await appState.observeRun(agent: agent, run: latestRun)
            }
        }
    }

    private func queueFollowUp(agent: Agent) {
        guard let draft = currentFollowUpDraft(agent: agent) else { return }
        queuedFollowUp = draft
        clearFollowUpComposer()
        isComposerFocused = false
    }

    private func restoreQueuedFollowUp(_ draft: QueuedFollowUpDraft) {
        queuedFollowUp = nil
        followUpText = draft.prompt.text
        followUpImages = draft.prompt.images
        followUpFiles = draft.prompt.files
        selectedFollowUpModelID = draft.modelID
        followUpModelAgentID = draft.agentID
        isComposerFocused = true
    }

    private func sendQueuedFollowUpIfNeeded(agent: Agent) async {
        guard let draft = queuedFollowUp, draft.agentID == agent.id else { return }
        queuedFollowUp = nil
        await appState.createFollowUp(
            agent: agent,
            prompt: draft.prompt,
            modelID: draft.modelID
        )
        if let latestRun = appState.runs(for: agent).first {
            await appState.observeRun(agent: agent, run: latestRun)
        }
    }

    private func currentFollowUpDraft(agent: Agent) -> QueuedFollowUpDraft? {
        guard canSendFollowUp else { return nil }
        return QueuedFollowUpDraft(
            agentID: agent.id,
            prompt: AgentPrompt(
                text: followUpText.trimmingCharacters(in: .whitespacesAndNewlines),
                images: followUpImages,
                files: followUpFiles
            ),
            modelID: selectedFollowUpModelID(for: agent)
        )
    }

    private func clearFollowUpComposer() {
        followUpText = ""
        followUpImages = []
        followUpFiles = []
        selectedFollowUpPhotoItems = []
        followUpFileImportMessage = nil
    }

    private func followUpModelBinding(for agent: Agent) -> Binding<String?> {
        Binding {
            selectedFollowUpModelID(for: agent)
        } set: { modelID in
            followUpModelAgentID = agent.id
            selectedFollowUpModelID = NewChatModelPickerOptions.modelID(
                from: modelID,
                runtimeMode: agent.runtimeMode
            )
        }
    }

    private func selectedFollowUpModelID(for agent: Agent) -> String? {
        if followUpModelAgentID == agent.id {
            return selectedFollowUpModelID
        }
        return NewChatModelPickerOptions.modelID(from: agent.modelID, runtimeMode: agent.runtimeMode)
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

private struct QueuedFollowUpDraft: Identifiable, Hashable {
    var id = UUID()
    var agentID: Agent.ID
    var prompt: AgentPrompt
    var modelID: String?
}

private struct QueuedFollowUpRow: View {
    var draft: QueuedFollowUpDraft
    var onEdit: () -> Void
    var onCancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "text.bubble")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.blue.opacity(0.12)))

            VStack(alignment: .leading, spacing: 4) {
                Text("Queued follow-up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(draft.prompt.text)
                    .font(.callout)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                if !draft.prompt.files.isEmpty || !draft.prompt.images.isEmpty {
                    Text(attachmentSummary)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit queued follow-up")

            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel queued follow-up")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.70), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.16), lineWidth: 0.5)
        )
    }

    private var attachmentSummary: String {
        var parts: [String] = []
        if !draft.prompt.images.isEmpty {
            parts.append("\(draft.prompt.images.count) image\(draft.prompt.images.count == 1 ? "" : "s")")
        }
        if !draft.prompt.files.isEmpty {
            parts.append("\(draft.prompt.files.count) file\(draft.prompt.files.count == 1 ? "" : "s")")
        }
        return parts.joined(separator: ", ")
    }
}

private struct WorkspaceHandoffPresentation: Identifiable {
    var agent: Agent
    var events: [AgentStreamEvent]

    var id: Agent.ID { agent.id }

    var preview: String {
        WorkspaceHandoffPromptBuilder.contextPreview(from: events)
    }
}

private struct GeneralChatWorkspaceHandoffSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    var presentation: WorkspaceHandoffPresentation
    var onCreate: (Repository, String?, String) async -> Bool

    @State private var selectedRepositoryID = ""
    @State private var branchText = ""
    @State private var instruction = "Use this conversation as context and continue with the next concrete implementation step."
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    handoffRouteCard

                    if availableRepositories.isEmpty {
                        emptyRepositoriesView
                    } else {
                        repositorySection
                        instructionSection

                        if !presentation.preview.isEmpty {
                            contextSection
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 112)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Continue in Workspace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isCreating)
                }

            }
            .safeAreaInset(edge: .bottom) {
                createButtonBar
            }
            .onAppear {
                configureInitialRepositoryIfNeeded()
            }
            .onChange(of: selectedRepositoryID) { _, _ in
                guard let selectedRepository else { return }
                branchText = selectedRepository.defaultBranch
            }
        }
    }

    private var handoffRouteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(presentation.agent.name)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            HStack(spacing: 8) {
                handoffRouteChip(
                    systemName: "bubble.left.and.bubble.right",
                    title: "General Chat",
                    tint: Color(uiColor: .systemGreen)
                )

                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)

                handoffRouteChip(
                    systemName: "folder",
                    title: selectedRepository?.displayName ?? "Repository",
                    tint: Color(uiColor: .systemBlue)
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.12), lineWidth: 0.5)
        )
    }

    private func handoffRouteChip(systemName: String, title: String, tint: Color) -> some View {
        Label(title, systemImage: systemName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Capsule().fill(tint.opacity(0.10)))
    }

    private var repositorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Repository")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            Menu {
                ForEach(availableRepositories) { repository in
                    Button {
                        selectedRepositoryID = repository.id
                        branchText = repository.defaultBranch
                    } label: {
                        Label(repository.displayName, systemImage: selectedRepositoryID == repository.id ? "checkmark" : "folder")
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedRepository?.displayName ?? "Repository")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(selectedRepository?.defaultBranch.nilIfBlank ?? "Choose where Cursor should work")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .frame(height: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            TextField("Branch or ref", text: $branchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var instructionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Next step")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            TextField("Tell Cursor what to do in this repository", text: $instruction, axis: .vertical)
                .lineLimit(3...7)
                .padding(14)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Conversation context")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            Text(presentation.preview)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var emptyRepositoriesView: some View {
        VStack(spacing: 14) {
            ContentUnavailableView(
                "No Repository Workspaces",
                systemImage: "folder.badge.questionmark",
                description: Text("Refresh repositories before continuing this chat in a workspace.")
            )

            Button {
                Task {
                    await appState.reloadWorkspace()
                    configureInitialRepositoryIfNeeded()
                }
            } label: {
                Label("Refresh Repositories", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
    }

    private var createButtonBar: some View {
        Button {
            createWorkspace()
        } label: {
            if isCreating {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            } else {
                Label("Continue in Workspace", systemImage: "arrow.right")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canCreate)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.regularMaterial)
    }

    private var selectedRepository: Repository? {
        availableRepositories.first { $0.id == selectedRepositoryID } ?? availableRepositories.first
    }

    private var availableRepositories: [Repository] {
        appState.repositories.filter { !$0.isGeneralChat }
    }

    private var canCreate: Bool {
        selectedRepository != nil
            && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isCreating
    }

    private func configureInitialRepositoryIfNeeded() {
        guard selectedRepositoryID.isEmpty, let repository = availableRepositories.first else { return }
        selectedRepositoryID = repository.id
        branchText = repository.defaultBranch
    }

    private func createWorkspace() {
        guard let repository = selectedRepository else { return }
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        isCreating = true
        Task {
            let didCreate = await onCreate(repository, branchText.nilIfBlank, trimmedInstruction)
            isCreating = false
            if didCreate {
                dismiss()
            }
        }
    }
}

enum WorkspaceHandoffPromptBuilder {
    static func prompt(from events: [AgentStreamEvent], instruction: String, sourceTitle: String? = nil) -> String {
        let context = conversationContext(from: events)
        let title = normalizedSourceTitle(sourceTitle, events: events)
        return """
        \(title)

        Continue this Cursor Chat in a repository-backed workspace.

        Prior conversation context:
        \(context)

        Workspace instruction:
        \(instruction.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }

    static func contextPreview(from events: [AgentStreamEvent]) -> String {
        let context = conversationContext(from: events)
        guard context != "No prior message context was available." else { return "" }
        return context.timelineSingleLinePreview(maxCharacters: 320)
    }

    private static func normalizedSourceTitle(_ sourceTitle: String?, events: [AgentStreamEvent]) -> String {
        let trimmedTitle = sourceTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedTitle.isEmpty,
           trimmedTitle.localizedCaseInsensitiveCompare("General Chat") != .orderedSame {
            return trimmedTitle.timelineSingleLinePreview(maxCharacters: 96)
        }
        let prompt = events.first { $0.kind == .user }?.message
        return ConversationTitleGenerator.title(
            from: prompt ?? "Repo workspace",
            repository: Repository(
                owner: "Cursor",
                name: "General Chat",
                url: URL(string: "https://cursor.com/general-chat")!,
                defaultBranch: "",
                isFavorite: false,
                lastUsedDescription: "now"
            )
        ) ?? "Repo Workspace"
    }

    private static func conversationContext(from events: [AgentStreamEvent]) -> String {
        let rows = events
            .filter { event in
                switch event.kind {
                case .user, .assistant, .result:
                    !event.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                default:
                    false
                }
            }
            .suffix(10)
            .map { event -> String in
                let role = event.kind == .user ? "User" : "Cursor"
                let message = event.message
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .timelineBoundedText(maxCharacters: 900)
                return "\(role): \(message)"
            }

        if rows.isEmpty {
            return "No prior message context was available."
        }

        return rows.joined(separator: "\n\n").timelineBoundedText(maxCharacters: 5_000)
    }
}

private struct ConversationHeaderCard: View {
    var agent: Agent
    var run: AgentRun?
    var onCreateWorkspace: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(headerTitle, systemImage: agent.runtimeMode.detailSymbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(agent.runtimeMode.detailTint)

                Spacer(minLength: 8)

                if let run {
                    RunStatusBadge(status: run.status)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(primaryTitle)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if !agent.repository.isGeneralChat, let branchName = agent.branchName.nilIfBlank {
                        CloudChatContextChip(systemName: "arrow.triangle.branch", title: branchName)
                    }
                    CloudChatContextChip(systemName: "cpu", title: agent.modelID)
                    if let run {
                        CloudChatContextChip(systemName: "clock", title: run.updatedAtDescription)
                    }

                    if agent.artifactCount > 0 {
                        CloudChatContextChip(systemName: "tray.full", title: "\(agent.artifactCount) artifact\(agent.artifactCount == 1 ? "" : "s")")
                    }

                    if let onCreateWorkspace {
                        Button(action: onCreateWorkspace) {
                            CloudChatContextChip(systemName: "folder.badge.plus", title: "Continue in Repo", tint: Color(uiColor: .systemBlue))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Create repository workspace from this chat")
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var headerTitle: String {
        agent.runtimeMode == .sdkBridge ? "Live Workspace" : "Cursor Cloud"
    }

    private var primaryTitle: String {
        if agent.runtimeMode == .sdkBridge {
            return agent.repository.isGeneralChat ? "General Chat" : agent.repository.displayName
        }
        return agent.name
    }

    private var subtitle: String {
        if agent.runtimeMode == .sdkBridge {
            return agent.repository.isGeneralChat ? "Repo-less conversation" : agent.name
        }
        return agent.repository.displayName
    }
}

private struct CloudChatContextChip: View {
    var systemName: String
    var title: String
    var tint: Color?

    var body: some View {
        Label(title, systemImage: systemName)
            .font(.caption)
            .foregroundStyle(tint ?? Color(uiColor: .secondaryLabel))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color(uiColor: .tertiarySystemGroupedBackground)))
    }
}

private struct CloudChatEmptyTimeline: View {
    var runtimeMode: AgentRuntimeMode
    var runStatus: RunStatus
    var isStreamExpired: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CloudAvatar(
                systemName: symbolName,
                tint: tint
            )

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Cursor")
                        .font(.caption.weight(.semibold))
                    Text(stateTitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 8)
            }

            Spacer(minLength: 24)
        }
        .accessibilityElement(children: .combine)
    }

    private var symbolName: String {
        if runStatus.isTerminal {
            return "checkmark.circle"
        }
        return isStreamExpired ? "clock.badge.exclamationmark" : "dot.radiowaves.left.and.right"
    }

    private var tint: Color {
        if runStatus.isTerminal {
            return .secondary
        }
        return isStreamExpired ? .orange : .blue
    }

    private var stateTitle: String {
        if runStatus.isTerminal {
            return "No visible updates"
        }
        return isStreamExpired ? "Paused" : "Starting"
    }

    private var message: String {
        if runStatus.isTerminal {
            return "This turn finished, but no saved timeline messages are available locally."
        }
        if isStreamExpired {
            return "Live updates are paused for this run. Pull to refresh for the latest \(runtimeMode.title) state."
        }
        return "Waiting for the first \(runtimeMode.title) update."
    }
}

private struct ChatTimelineEventDigest: Hashable {
    var id: String
    var kind: StreamEventKind
    var title: String
    var messageCharacterCount: Int

    init(event: AgentStreamEvent) {
        id = event.id
        kind = event.kind
        title = event.title
        messageCharacterCount = event.message.count
    }
}

private struct ChatTimelineEventSignature: Hashable {
    var runID: AgentRun.ID?
    var digests: [ChatTimelineEventDigest]

    init(runID: AgentRun.ID?, events: [AgentStreamEvent]) {
        self.runID = runID
        digests = events.map(ChatTimelineEventDigest.init(event:))
    }

    init(runID: AgentRun.ID?, digests: [ChatTimelineEventDigest]) {
        self.runID = runID
        self.digests = digests
    }
}

private struct ChatTimelineSnapshot {
    var runID: AgentRun.ID?
    var signature: ChatTimelineEventSignature
    var items: [ChatTimelineItem]
    var sections: [ChatTimelineSection]
    var itemIDs: [String]

    init(runID: AgentRun.ID?, signature: ChatTimelineEventSignature, items: [ChatTimelineItem]) {
        self.runID = runID
        self.signature = signature
        self.items = items
        sections = ChatTimelineSection.sections(from: items)
        itemIDs = items.map(\.id)
    }

    static let empty = ChatTimelineSnapshot(
        runID: nil,
        signature: ChatTimelineEventSignature(runID: nil, digests: []),
        items: []
    )
}

private struct ChatTimelineSection: Identifiable, Hashable {
    private static let maxVisibleActivityItems = 4

    var id: String
    var items: [ChatTimelineItem]
    var isActivityLog: Bool
    var hiddenActivityItemCount: Int = 0

    static func sections(from items: [ChatTimelineItem]) -> [ChatTimelineSection] {
        var sections: [ChatTimelineSection] = []
        var activityItems: [ChatTimelineItem] = []

        func flushActivityItems() {
            guard !activityItems.isEmpty else { return }
            let hiddenCount = max(0, activityItems.count - maxVisibleActivityItems)
            let visibleItems = hiddenCount > 0 ? Array(activityItems.suffix(maxVisibleActivityItems)) : activityItems
            sections.append(
                ChatTimelineSection(
                    id: activitySectionID(index: sections.count, items: activityItems),
                    items: visibleItems,
                    isActivityLog: true,
                    hiddenActivityItemCount: hiddenCount
                )
            )
            activityItems = []
        }

        for item in items {
            if item.isActivityLogItem {
                activityItems.append(item)
            } else {
                flushActivityItems()
                sections.append(
                    ChatTimelineSection(
                        id: messageSectionID(index: sections.count, item: item),
                        items: [item],
                        isActivityLog: false
                    )
                )
            }
        }

        flushActivityItems()
        return sections
    }

    private static func activitySectionID(index: Int, items: [ChatTimelineItem]) -> String {
        let firstID = items.first?.id.timelineStableIDFragment ?? "empty"
        return "activity-\(index)-\(firstID)"
    }

    private static func messageSectionID(index: Int, item: ChatTimelineItem) -> String {
        "message-\(index)-\(item.id.timelineStableIDFragment)"
    }
}

private struct ChatTimelineSectionView: View {
    var section: ChatTimelineSection

    var body: some View {
        if section.isActivityLog {
            CloudActivityLog(items: section.items, hiddenItemCount: section.hiddenActivityItemCount)
        } else if let item = section.items.first {
            ChatTimelineRow(item: item)
        }
    }
}

private struct ChatTimelineRow: View {
    var item: ChatTimelineItem

    var body: some View {
        if let changeSet = item.changeSet {
            WorkspaceChangeSetCard(changeSet: changeSet, timestamp: item.timestamp)
        } else {
            switch item.kind {
            case .user:
                UserMessageRow(item: item)
            case .assistant, .result:
                AssistantMessageRow(item: item)
            case .status, .done, .heartbeat:
                CloudStatusEventPill(item: item)
            default:
                CloudActivityDisclosureRow(item: item)
            }
        }
    }
}

private struct WorkspaceChangeSetCard: View {
    var changeSet: WorkspaceChangeSet
    var timestamp: String
    @State private var isExpanded = true
    @State private var diffPresentation: WorkspaceDiffPresentation?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded {
                softDivider

                ForEach(Array(visibleInlineChanges.enumerated()), id: \.element.id) { index, change in
                    Button {
                        diffPresentation = WorkspaceDiffPresentation(changeSet: changeSet, focusedPath: change.path)
                    } label: {
                        WorkspaceFileChangeRow(change: change)
                    }
                    .buttonStyle(.plain)

                    if index < visibleInlineChanges.count - 1 {
                        softDivider
                            .padding(.leading, 12)
                    }
                }

                if hiddenInlineChangeCount > 0 {
                    softDivider
                        .padding(.leading, 12)

                    Button {
                        diffPresentation = WorkspaceDiffPresentation(changeSet: changeSet, focusedPath: nil)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "ellipsis")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 18)

                            Text("Show \(hiddenInlineChangeCount) more file\(hiddenInlineChangeCount == 1 ? "" : "s")")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.68))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.16), lineWidth: 0.5)
        )
        .sheet(item: $diffPresentation) { presentation in
            WorkspaceDiffSheet(presentation: presentation)
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Files changed")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    WorkspaceDiffCountsLabel(additions: changeSet.totalAdditions, deletions: changeSet.totalDeletions)
                }

                Text(changeSummary)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(timestamp)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Button {
                diffPresentation = WorkspaceDiffPresentation(changeSet: changeSet, focusedPath: nil)
            } label: {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open diff")

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse file changes" : "Expand file changes")
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.top, 8)
        .padding(.bottom, isExpanded ? 7 : 9)
    }

    private var visibleInlineChanges: [WorkspaceFileChange] {
        Array(changeSet.changes.prefix(4))
    }

    private var hiddenInlineChangeCount: Int {
        max(0, changeSet.changes.count - visibleInlineChanges.count)
    }

    private var changeSummary: String {
        let count = changeSet.changes.count
        return "\(count) file\(count == 1 ? "" : "s") changed"
    }

    private var softDivider: some View {
        Rectangle()
            .fill(Color(uiColor: .separator).opacity(0.35))
            .frame(height: 0.5)
    }
}

private struct WorkspaceFileChangeRow: View {
    var change: WorkspaceFileChange

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Text(change.action.rawValue)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(actionTint)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Capsule().fill(actionTint.opacity(0.11)))

            Text(change.path)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            WorkspaceDiffCountsLabel(additions: change.additions, deletions: change.deletions)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private var actionTint: Color {
        switch change.action {
        case .added:
            .green
        case .deleted:
            .red
        case .renamed:
            .orange
        case .modified:
            .blue
        case .unknown:
            .secondary
        }
    }
}

private struct WorkspaceDiffCountsLabel: View {
    var additions: Int
    var deletions: Int

    var body: some View {
        HStack(spacing: 5) {
            if additions > 0 {
                Text("+\(additions)")
                    .foregroundStyle(.green)
            }
            if deletions > 0 {
                Text("-\(deletions)")
                    .foregroundStyle(.red)
            }
            if additions == 0 && deletions == 0 {
                Text("+0 -0")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption.monospacedDigit().weight(.semibold))
        .lineLimit(1)
    }
}

private struct WorkspaceDiffPresentation: Identifiable {
    var changeSet: WorkspaceChangeSet
    var focusedPath: String?

    var id: String {
        [changeSet.id, focusedPath ?? "all"].joined(separator: ":")
    }

    var title: String {
        focusedPath ?? "Changes"
    }

    var visibleChanges: [WorkspaceFileChange] {
        guard let focusedPath else { return changeSet.changes }
        return changeSet.changes.filter { $0.path == focusedPath }
    }
}

private struct WorkspaceDiffSheet: View {
    var presentation: WorkspaceDiffPresentation
    @Environment(\.dismiss) private var dismiss
    @State private var expandedPaths: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    diffSummaryHeader

                    if presentation.visibleChanges.isEmpty {
                        ContentUnavailableView(
                            "No Diff Available",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text("The runtime reported file changes without raw diff content.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    } else {
                        ForEach(presentation.visibleChanges) { change in
                            diffBlock(change)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(presentation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(allExpanded ? "Collapse" : "Expand") {
                        if allExpanded {
                            expandedPaths.removeAll()
                        } else {
                            expandedPaths = Set(presentation.visibleChanges.map(\.path))
                        }
                    }
                }
            }
            .onAppear {
                expandedPaths = Set(presentation.visibleChanges.prefix(3).map(\.path))
            }
        }
    }

    private var diffSummaryHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.blue.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text("\(presentation.visibleChanges.count) file\(presentation.visibleChanges.count == 1 ? "" : "s") changed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                WorkspaceDiffCountsLabel(
                    additions: presentation.visibleChanges.reduce(0) { $0 + $1.additions },
                    deletions: presentation.visibleChanges.reduce(0) { $0 + $1.deletions }
                )
            }

            Spacer(minLength: 8)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var allExpanded: Bool {
        let paths = Set(presentation.visibleChanges.map(\.path))
        return !paths.isEmpty && paths.isSubset(of: expandedPaths)
    }

    private func diffBlock(_ change: WorkspaceFileChange) -> some View {
        let isExpanded = expandedPaths.contains(change.path)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isExpanded {
                        expandedPaths.remove(change.path)
                    } else {
                        expandedPaths.insert(change.path)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)

                    Text(change.path)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 8)

                    WorkspaceDiffCountsLabel(additions: change.additions, deletions: change.deletions)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().opacity(0.45)
                if let diff = change.diff?.nilIfBlank {
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(diff.timelineBoundedText(maxCharacters: 16_000))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(12)
                    }
                } else {
                    Text("No raw diff was provided for this file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.16), lineWidth: 0.5)
        )
    }
}

private struct CloudActivityDisclosureRow: View {
    var item: ChatTimelineItem
    @State private var detailPresentation: TimelineActivityDetailPresentation?

    var body: some View {
        Group {
            if item.allowsActivityDetailSheet {
                Button {
                    detailPresentation = TimelineActivityDetailPresentation(item: item)
                } label: {
                    rowLabel
                }
                .buttonStyle(.plain)
            } else {
                rowLabel
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.65), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .sheet(item: $detailPresentation) { presentation in
            TimelineActivityDetailSheet(presentation: presentation)
        }
        .accessibilityElement(children: .combine)
    }

    private var rowLabel: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if item.allowsActivityDetailSheet {
                    Text(item.activityPreview(maxCharacters: 150))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Text(item.timestamp)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if item.allowsActivityDetailSheet {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
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

private struct CloudActivityLog: View {
    var items: [ChatTimelineItem]
    var hiddenItemCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CloudAvatar(systemName: groupSymbolName, tint: groupTint)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                if hiddenItemCount > 0 {
                    CloudActivityHiddenRow(count: hiddenItemCount)
                }

                ForEach(items) { item in
                    CloudActivityCompactRow(item: item)
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.top, 2)

            Spacer(minLength: 24)
        }
        .accessibilityElement(children: .contain)
    }

    private var groupSymbolName: String {
        if items.contains(where: { $0.kind == .error }) {
            return "exclamationmark.triangle"
        }
        if items.contains(where: { $0.kind == .toolCall || $0.kind == .task }) {
            return "terminal"
        }
        if items.contains(where: { $0.kind == .thinking }) {
            return "brain"
        }
        return "ellipsis.message"
    }

    private var groupTint: Color {
        if items.contains(where: { $0.kind == .error }) {
            return .red
        }
        if items.contains(where: { $0.kind == .thinking }) {
            return .orange
        }
        if items.contains(where: { $0.kind == .toolCall || $0.kind == .task }) {
            return .blue
        }
        return .secondary
    }
}

private struct CloudActivityHiddenRow: View {
    var count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "ellipsis")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text("\(count) earlier update\(count == 1 ? "" : "s")")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)
        }
        .padding(.vertical, 1)
        .accessibilityElement(children: .combine)
    }
}

private struct CloudActivityCompactRow: View {
    var item: ChatTimelineItem
    @State private var detailPresentation: TimelineActivityDetailPresentation?

    var body: some View {
        Group {
            if item.allowsActivityDetailSheet {
                Button {
                    detailPresentation = TimelineActivityDetailPresentation(item: item)
                } label: {
                    label
                }
                .buttonStyle(.plain)
            } else {
                label
            }
        }
        .padding(.vertical, 1)
        .sheet(item: $detailPresentation) { presentation in
            TimelineActivityDetailSheet(presentation: presentation)
        }
        .accessibilityElement(children: .combine)
    }

    private var label: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbolName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 16)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(compactTitle)
                    .font(.callout)
                    .foregroundStyle(titleColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if shouldShowCollapsedPreview,
                   collapsedPreview.localizedCaseInsensitiveCompare(compactTitle) != .orderedSame {
                    Text(collapsedPreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if item.allowsActivityDetailSheet {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
        .contentShape(Rectangle())
    }

    private var compactTitle: String {
        switch item.kind {
        case .toolCall:
            let preview = item.activityPreview(maxCharacters: 72)
            return preview.isEmpty ? "Tool Call" : toolCallTitle(from: preview)
        case .thinking:
            let preview = item.activityPreview(maxCharacters: 72)
            if !preview.isEmpty, !preview.localizedCaseInsensitiveContains("thinking update") {
                return preview
            }
            return item.title.localizedCaseInsensitiveContains("Completed") ? "Thought briefly" : "Thinking"
        case .task:
            return item.title
        case .done:
            return "Turn Ended"
        default:
            return item.title
        }
    }

    private var collapsedPreview: String {
        item.activityPreview(maxCharacters: 140)
    }

    private var shouldShowCollapsedPreview: Bool {
        item.kind == .error || item.kind == .request
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
        case .toolCall, .task:
            .blue
        default:
            .secondary
        }
    }

    private var titleColor: Color {
        item.kind == .error ? .red : .secondary
    }

    private func toolCallTitle(from preview: String) -> String {
        let parts = preview.split(separator: ":", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard parts.count == 2 else { return preview }
        let name = parts[0].replacingOccurrences(of: "_", with: " ")
        let status = parts[1].lowercased()
        if status.contains("completed") || status.contains("complete") || status.contains("done") {
            return "Ran \(name)"
        }
        if status.contains("running") || status.contains("started") {
            return "Running \(name)"
        }
        return "\(name) \(parts[1])"
    }
}

private struct TimelineActivityDetailPresentation: Identifiable {
    var item: ChatTimelineItem

    var id: String { item.id }
}

private struct TimelineActivityDetailSheet: View {
    var presentation: TimelineActivityDetailPresentation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(presentation.item.title, systemImage: symbolName)
                            .font(.headline)
                            .foregroundStyle(color)

                        Text(presentation.item.timestamp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(detailText)
                        .font(isTechnical ? .caption.monospaced() : .callout)
                        .foregroundStyle(isError ? .red : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var detailText: String {
        let message = presentation.item.normalizedActivityMessage
        guard !message.isEmpty else { return "No additional details were provided." }
        return message.timelineBoundedText(maxCharacters: 6_000)
    }

    private var isTechnical: Bool {
        presentation.item.kind == .toolCall || presentation.item.kind == .error
    }

    private var isError: Bool {
        presentation.item.kind == .error
    }

    private var symbolName: String {
        switch presentation.item.kind {
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
        switch presentation.item.kind {
        case .status, .done:
            .green
        case .error:
            .red
        case .thinking, .request:
            .orange
        case .toolCall, .task:
            .blue
        default:
            .secondary
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

private extension ChatTimelineItem {
    var isActivityLogItem: Bool {
        if changeSet != nil {
            return false
        }
        return switch kind {
        case .system, .status, .thinking, .toolCall, .task, .request, .heartbeat, .error, .done, .unknown:
            true
        case .user, .assistant, .result:
            false
        }
    }

    var hasUsefulActivityDetail: Bool {
        let normalizedMessage = normalizedActivityMessage
        guard !normalizedMessage.isEmpty else { return false }
        return normalizedMessage.localizedCaseInsensitiveCompare(title) != .orderedSame
            && normalizedMessage != "Stream closed"
    }

    var allowsActivityDetailSheet: Bool {
        guard hasUsefulActivityDetail else { return false }
        switch kind {
        case .error:
            return true
        default:
            return false
        }
    }

    var normalizedActivityMessage: String {
        activityDetailText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func activityPreview(maxCharacters: Int = 160) -> String {
        activityPreviewText.timelineBoundedText(maxCharacters: maxCharacters)
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
    var runtimeMode: AgentRuntimeMode
    @Binding var selection: String?

    var body: some View {
        Menu {
            Button {
                selection = preferredModelID
            } label: {
                modelMenuLabel(
                    title: displayTitle(for: runtimeMode.preferredLaunchModelTitle),
                    isSelected: selection == preferredModelID
                )
            }

            ForEach(NewChatModelPickerOptions.visibleModels(from: models, excluding: preferredModelID)) { model in
                Button {
                    selection = model.id
                } label: {
                    modelMenuLabel(title: displayTitle(for: model.displayName), isSelected: selection == model.id)
                }
            }
        } label: {
            if runtimeMode == .sdkBridge {
                ComposerControlPill(
                    systemName: "sparkles",
                    title: modelTitle,
                    maxWidth: 160
                )
            } else {
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
        }
        .menuIndicator(.hidden)
        .tint(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Select Cursor model. Current model \(modelTitle)")
    }

    private var modelTitle: String {
        let modelID = runtimeMode.normalizedLaunchModelID(selection)
        guard let modelID else { return runtimeMode.preferredLaunchModelTitle }
        if let model = models.first(where: { $0.id == modelID }) {
            return displayTitle(for: model.displayName)
        }
        return displayTitle(for: modelID)
    }

    private var preferredModelID: String? {
        runtimeMode.preferredLaunchModelID
    }

    private func modelMenuLabel(title: String, isSelected: Bool) -> some View {
        Label(title, systemImage: isSelected ? "checkmark" : "cpu")
    }

    private func displayTitle(for title: String) -> String {
        runtimeMode == .sdkBridge ? ComposerLabelFormatter.modelTitle(title) : title
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
    var runtimeMode: AgentRuntimeMode

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(runtimeMode == .sdkBridge ? "Cursor is working" : "Listening for Cursor events")
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
    var runtimeMode: AgentRuntimeMode
    var hasQueuedFollowUp: Bool

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    private var statusText: String {
        if hasQueuedFollowUp {
            return "Follow-up queued for the next turn"
        }
        if runtimeMode == .sdkBridge {
            return status == .creating ? "Starting Cursor Chat" : "Cursor is working"
        }
        return status == .creating ? "Starting \(runtimeMode.title)" : "\(runtimeMode.title) running"
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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

private extension String {
    var timelineStableIDFragment: String {
        let flattened = replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let normalized = String(flattened.prefix(48))
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return normalized.isEmpty ? "item" : String(normalized.prefix(48))
    }

    func timelineSingleLinePreview(maxCharacters: Int) -> String {
        let flattened = replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flattened.timelineBoundedText(maxCharacters: maxCharacters)
    }

    func timelineBoundedText(maxCharacters: Int) -> String {
        guard count > maxCharacters else { return self }
        return String(prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
            + "\n\nDetails truncated for smoother chat performance."
    }
}
