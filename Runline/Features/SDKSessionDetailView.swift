import PhotosUI
import SwiftUI
import UIKit

struct SDKSessionDetailView: View {
    private static let maxPromptImages = 5
    private static let promptImageMaxDimension: CGFloat = 1600
    private static let promptImageJPEGQuality: CGFloat = 0.82
    private static let composerControlSize: CGFloat = 38

    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    var agent: Agent
    @State private var messageText = ""
    @State private var messageImages: [PromptImage] = []
    @State private var messageFiles: [PromptFile] = []
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isLoadingImages = false
    @State private var isFileImporterPresented = false
    @State private var isLoadingFiles = false
    @State private var fileImportMessage: String?
    @State private var isArtifactsPresented = false
    @State private var isSDKToolsPresented = false
    @State private var sdkMessageIntent: SDKMessageIntent = .continueConversation
    @State private var selectedSDKModelID: String?
    @State private var selectedSDKMCPProfileID: String?
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        let currentAgent = appState.agent(id: agent.id) ?? agent
        let latestRun = appState.runs(for: currentAgent).first

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                SDKSessionHeaderCard(
                    agent: currentAgent,
                    run: latestRun,
                    profile: appState.sdkBridgeProfile(for: currentAgent)
                )

                if let latestRun {
                    let events = appState.events(for: latestRun.id)
                    let timelineItems = ChatTimelineBuilder.items(from: events)

                    if timelineItems.isEmpty {
                        ContentUnavailableView(
                            appState.isStreamExpired(runID: latestRun.id) ? "Stream Paused" : "Waiting for Cursor SDK",
                            systemImage: appState.isStreamExpired(runID: latestRun.id) ? "clock.badge.exclamationmark" : "dot.radiowaves.left.and.right",
                            description: Text(appState.isStreamExpired(runID: latestRun.id) ? "Refresh the session to poll the latest state." : "Messages, tool activity, and results appear here as the SDK run streams.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        ForEach(timelineItems) { item in
                            SDKTimelineItemView(item: item)
                        }
                    }

                    if appState.isObserving(runID: latestRun.id) {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Listening for Cursor SDK events")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                    }
                } else {
                    ContentUnavailableView(
                        "No SDK Runs",
                        systemImage: "terminal",
                        description: Text("Runs appear after you launch or continue this SDK session.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(currentAgent.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            if let latestRun = appState.runs(for: currentAgent).first {
                await appState.loadEvents(for: currentAgent, run: latestRun)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if shouldShowComposer(agent: currentAgent, run: latestRun) {
                sdkComposer(agent: currentAgent)
            } else if let latestRun, !latestRun.status.isTerminal {
                SDKRunInProgressBar(status: latestRun.status)
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
                        isSDKToolsPresented = true
                    } label: {
                        Label("SDK Tools", systemImage: "wrench.and.screwdriver")
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
                .accessibilityLabel("SDK session actions")
            }
        }
        .task {
            seedComposerDefaults(for: currentAgent)
            if appState.isSDKBridgeAgent(currentAgent) {
                await appState.reloadSDKBridgeProfiles()
            }
        }
        .onChange(of: currentAgent.id) { _, _ in
            seedComposerDefaults(for: currentAgent)
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
        .sheet(isPresented: $isSDKToolsPresented) {
            NavigationStack {
                if let profile = appState.sdkBridgeProfile(for: currentAgent) {
                    SDKBridgeProfileDetailView(profile: profile)
                } else {
                    SDKToolsView()
                }
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: PromptFileLoader.allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            Task {
                await loadFiles(from: result)
            }
        }
    }

    private func shouldShowComposer(agent: Agent, run: AgentRun?) -> Bool {
        guard let run, run.status.isTerminal else { return false }
        if case .active = agent.status {
            return true
        }
        return false
    }

    private func sdkComposer(agent: Agent) -> some View {
        VStack(spacing: 8) {
            if shouldShowAttachments {
                attachmentStrip
            }

            if let fileImportMessage {
                Text(fileImportMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
            }

            sdkComposerControls

            HStack(alignment: .center, spacing: 8) {
                Menu {
                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: Self.maxPromptImages,
                        matching: .images
                    ) {
                        Label("Photos", systemImage: "photo")
                    }
                    .disabled(isLoadingImages || messageImages.count >= Self.maxPromptImages)

                    Button {
                        isFileImporterPresented = true
                    } label: {
                        Label("Files", systemImage: "doc")
                    }
                    .disabled(isLoadingFiles || messageFiles.count >= PromptFileLoader.maxFiles)
                } label: {
                    Image(systemName: "plus")
                        .font(.title3)
                        .frame(width: Self.composerControlSize, height: Self.composerControlSize)
                        .background(Circle().fill(Color(uiColor: .secondarySystemBackground)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Attach context")
                .onChange(of: selectedPhotoItems) { _, items in
                    Task {
                        await loadImages(from: items)
                    }
                }

                TextField("Message Cursor SDK", text: $messageText, axis: .vertical)
                    .lineLimit(1...5)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .focused($isComposerFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 21, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 21, style: .continuous)
                            .stroke(Color(uiColor: .separator).opacity(0.25), lineWidth: 0.5)
                    )

                Button {
                    sendMessage(agent: agent)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: Self.composerControlSize, height: Self.composerControlSize)
                }
                .buttonStyle(.plain)
                .disabled(!canSendMessage)
                .accessibilityLabel("Send SDK message")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private var sdkComposerControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Intent", selection: $sdkMessageIntent) {
                        ForEach(SDKMessageIntent.allCases) { intent in
                            Label(intent.title, systemImage: intent.symbolName)
                                .tag(intent)
                        }
                    }
                } label: {
                    Label(sdkMessageIntent.title, systemImage: sdkMessageIntent.symbolName)
                }
                .buttonStyle(.bordered)

                Menu {
                    Picker("Model", selection: sdkModelSelectionBinding) {
                        Text("Default").tag(Optional<String>.none)
                        ForEach(NewChatModelPickerOptions.visibleModels(from: appState.models)) { model in
                            Text(model.displayName).tag(Optional(model.id))
                        }
                    }
                } label: {
                    Label(selectedSDKModelTitle, systemImage: "cpu")
                }
                .buttonStyle(.bordered)

                Menu {
                    Picker("MCP Profile", selection: sdkMCPProfileSelectionBinding) {
                        Text("No Profile").tag(Optional<String>.none)
                        ForEach(appState.sdkBridgeProfiles) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }
                } label: {
                    Label(selectedSDKProfileTitle, systemImage: "point.3.connected.trianglepath.dotted")
                }
                .buttonStyle(.bordered)

                Button {
                    isSDKToolsPresented = true
                } label: {
                    Label("Tools", systemImage: "wrench.and.screwdriver")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12)
        }
    }

    private var sdkModelSelectionBinding: Binding<String?> {
        Binding {
            selectedSDKModelID
        } set: { modelID in
            selectedSDKModelID = NewChatModelPickerOptions.modelID(from: modelID)
        }
    }

    private var sdkMCPProfileSelectionBinding: Binding<String?> {
        Binding {
            selectedSDKMCPProfileID
        } set: { profileID in
            selectedSDKMCPProfileID = profileID
        }
    }

    private var selectedSDKModelTitle: String {
        guard let selectedSDKModelID else { return "Default" }
        return appState.models.first(where: { $0.id == selectedSDKModelID })?.displayName ?? selectedSDKModelID
    }

    private var selectedSDKProfileTitle: String {
        guard let selectedSDKMCPProfileID else { return "No Profile" }
        return appState.sdkBridgeProfiles.first(where: { $0.id == selectedSDKMCPProfileID })?.name ?? selectedSDKMCPProfileID
    }

    private var shouldShowAttachments: Bool {
        !messageImages.isEmpty || !messageFiles.isEmpty || isLoadingImages || isLoadingFiles
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(messageImages) { image in
                    SDKSessionContextPill(
                        title: "\(image.width) x \(image.height)",
                        systemImage: "photo",
                        remove: { removeImage(image) }
                    )
                }

                ForEach(messageFiles) { file in
                    SDKSessionContextPill(
                        title: "\(file.filename) - \(file.sizeDescription)",
                        systemImage: "doc.text",
                        remove: { removeFile(file) }
                    )
                }

                if isLoadingImages || isLoadingFiles {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.horizontal, 10)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var canSendMessage: Bool {
        !isLoadingImages
            && !isLoadingFiles
            && !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendMessage(agent: Agent) {
        guard canSendMessage else { return }
        let prompt = AgentPrompt(
            text: messageText.trimmingCharacters(in: .whitespacesAndNewlines),
            images: messageImages,
            files: messageFiles
        )
        messageText = ""
        messageImages = []
        messageFiles = []
        selectedPhotoItems = []
        fileImportMessage = nil
        isComposerFocused = false
        Task {
            await appState.createFollowUp(
                agent: agent,
                prompt: prompt,
                intent: sdkMessageIntent,
                sdkModelID: selectedSDKModelID,
                sdkMCPProfileID: selectedSDKMCPProfileID
            )
            sdkMessageIntent = .continueConversation
            if let latestRun = appState.runs(for: agent).first {
                await appState.observeRun(agent: agent, run: latestRun)
            }
        }
    }

    private func seedComposerDefaults(for agent: Agent) {
        selectedSDKModelID = NewChatModelPickerOptions.selection(from: agent.modelID)
        selectedSDKMCPProfileID = appState.sdkBridgeProfileID(for: agent)
    }

    private func loadImages(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        isLoadingImages = true
        defer {
            isLoadingImages = false
            selectedPhotoItems = []
        }

        var images = messageImages
        for item in items where images.count < Self.maxPromptImages {
            guard let originalData = try? await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: originalData),
                  let promptImage = normalizedPromptImage(from: uiImage) else {
                continue
            }
            images.append(promptImage)
        }
        messageImages = images
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

    private func removeImage(_ image: PromptImage) {
        messageImages.removeAll { $0.id == image.id }
        selectedPhotoItems = []
    }

    private func loadFiles(from result: Result<[URL], Error>) async {
        isLoadingFiles = true
        defer { isLoadingFiles = false }

        switch result {
        case .success(let urls):
            let loadResult = PromptFileLoader.loadFiles(from: urls, existingFiles: messageFiles)
            messageFiles = loadResult.files
            fileImportMessage = fileImportMessage(from: loadResult)
        case .failure(let error):
            fileImportMessage = "Could not load files: \(error.localizedDescription)"
        }
    }

    private func removeFile(_ file: PromptFile) {
        messageFiles.removeAll { $0.id == file.id }
        fileImportMessage = nil
    }

    private func fileImportMessage(from result: PromptFileLoadResult) -> String? {
        guard !result.skippedFilenames.isEmpty else { return nil }
        return "Skipped unsupported or large files: \(result.skippedFilenames.joined(separator: ", "))"
    }
}

private struct SDKSessionHeaderCard: View {
    var agent: Agent
    var run: AgentRun?
    var profile: SDKBridgeMCPProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "terminal.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(agent.repository.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(agent.branchName) / \(agent.modelID)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let run {
                    RunStatusBadge(status: run.status)
                }
            }

            if let profile {
                Label(profile.summary, systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let pullRequestURL = agent.pullRequestURL {
                Link(destination: pullRequestURL) {
                    Label("Open Pull Request", systemImage: "arrow.up.right.square")
                }
                .font(.footnote.weight(.medium))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private struct SDKTimelineItemView: View {
    var item: ChatTimelineItem

    var body: some View {
        switch item.kind {
        case .user:
            SDKChatBubble(item: item, role: .user)
        case .assistant:
            SDKChatBubble(item: item, role: .assistant)
        case .thinking, .toolCall, .task, .request, .result, .status, .done, .error:
            SDKTraceDisclosureRow(item: item)
        default:
            SDKTraceDisclosureRow(item: item)
        }
    }
}

private struct SDKChatBubble: View {
    enum Role {
        case user
        case assistant
    }

    var item: ChatTimelineItem
    var role: Role

    var body: some View {
        HStack(alignment: .bottom) {
            if role == .user {
                Spacer(minLength: 36)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label(role == .user ? "You" : "Cursor SDK", systemImage: role == .user ? "person" : "sparkles")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(item.timestamp)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                TimelineMessageText(
                    message: item.message,
                    isTechnical: false,
                    rendersMarkdown: role == .assistant,
                    foregroundColor: .primary
                )
            }
            .padding(14)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .frame(maxWidth: role == .user ? 340 : .infinity, alignment: role == .user ? .trailing : .leading)

            if role == .assistant {
                Spacer(minLength: 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: role == .user ? .trailing : .leading)
    }

    private var background: some ShapeStyle {
        role == .user
            ? AnyShapeStyle(Color.accentColor.opacity(0.14))
            : AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground))
    }
}

private struct SDKTraceDisclosureRow: View {
    var item: ChatTimelineItem
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            TimelineMessageText(
                message: item.message,
                isTechnical: isTechnical,
                rendersMarkdown: rendersMarkdown,
                foregroundColor: .secondary
            )
            .padding(.top, 6)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbolName)
                    .foregroundStyle(color)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Text(item.timestamp)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var title: String {
        switch item.kind {
        case .thinking:
            "Thinking"
        case .toolCall:
            "Tool"
        case .task:
            "Task"
        case .result:
            "Result"
        case .error:
            "Error"
        case .done:
            "Complete"
        default:
            item.title
        }
    }

    private var summary: String {
        item.message.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? item.title
    }

    private var isTechnical: Bool {
        item.kind == .toolCall || item.kind == .result || item.kind == .error
    }

    private var rendersMarkdown: Bool {
        switch item.kind {
        case .thinking, .task, .request:
            true
        default:
            false
        }
    }

    private var symbolName: String {
        switch item.kind {
        case .thinking:
            "brain"
        case .toolCall:
            "terminal"
        case .task:
            "checklist"
        case .result:
            "doc.text"
        case .error:
            "exclamationmark.triangle"
        case .done:
            "checkmark.seal"
        default:
            "gearshape"
        }
    }

    private var color: Color {
        switch item.kind {
        case .thinking:
            .orange
        case .error:
            .red
        case .done, .status:
            .green
        default:
            .blue
        }
    }
}

private struct SDKRunInProgressBar: View {
    var status: RunStatus

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Cursor SDK is \(status.title.lowercased()). You can continue when this run finishes.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}

private struct SDKSessionContextPill: View {
    var title: String
    var systemImage: String
    var remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption)
                .lineLimit(1)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove context")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(uiColor: .secondarySystemBackground)))
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
