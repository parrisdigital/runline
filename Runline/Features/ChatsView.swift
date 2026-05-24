import PhotosUI
import SwiftUI
import UIKit

struct CursorCloudView: View {
    @Environment(AppState.self) private var appState
    @State private var path: [Agent.ID] = []
    @State private var isNewChatPresented = false
    @State private var query = ""

    var body: some View {
        NavigationStack(path: $path) {
            ChatListContent(
                runtimeMode: .cloud,
                experience: .cursorCloud,
                query: $query,
                currentAgentID: nil,
                presentation: .navigation
            )
                .navigationTitle("Cursor Cloud")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            appState.launchDraft.applyRuntimeMode(.cloud)
                            isNewChatPresented = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("New Cursor Cloud run")
                    }
                }
                .navigationDestination(for: Agent.ID.self) { agentID in
                    if let agent = appState.agent(id: agentID) {
                        ChatDetailView(agent: agent)
                    } else {
                        ContentUnavailableView(
                            "Chat Unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text("This agent is no longer in the local cache.")
                        )
                        .navigationTitle("Chat")
                    }
                }
                .onChange(of: appState.focusedAgentID) { _, agentID in
                    guard let agentID else { return }
                    let agent = appState.agent(id: agentID)
                    guard agent?.runtimeMode == .cloud else { return }
                    path = [agentID]
                    appState.focusedAgentID = nil
                }
                .sheet(isPresented: $isNewChatPresented) {
                    NewChatSheet(runtimeMode: .cloud)
                }
        }
    }
}

struct CursorChatView: View {
    private static let maxPromptImages = 5
    private static let promptImageMaxDimension: CGFloat = 1600
    private static let promptImageJPEGQuality: CGFloat = 0.82
    private static let composerControlSize: CGFloat = 40
    private static let drawerAnimation = Animation.spring(response: 0.34, dampingFraction: 0.86)

    @Environment(AppState.self) private var appState
    @State private var activeAgentID: Agent.ID?
    @State private var isConversationDrawerOpen = false
    @State private var selectedDrawerAgentID: Agent.ID?
    @State private var query = ""
    @State private var prompt = ""
    @State private var promptImages: [PromptImage] = []
    @State private var promptFiles: [PromptFile] = []
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isLoadingPromptImages = false
    @State private var isFileImporterPresented = false
    @State private var isLoadingPromptFiles = false
    @State private var fileImportMessage: String?
    @State private var selectedRepositoryURL: URL?
    @State private var isGeneralConversation = true
    @AppStorage(CursorChatModelPreference.selectedModelIDKey) private var selectedModelID = AgentRuntimeMode.cursorChatPreferredModelID
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            NavigationStack {
                cursorChatContent
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                openConversationDrawer()
                            } label: {
                                Image(systemName: "sidebar.left")
                            }
                            .accessibilityLabel("Show conversations")
                        }

                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                resetCursorChatDraft(focusComposer: true)
                            } label: {
                                Image(systemName: "square.and.pencil")
                            }
                            .accessibilityLabel("New Cursor Chat")
                        }
                    }
                    .onChange(of: appState.focusedAgentID) { _, agentID in
                        guard let agentID,
                              appState.agent(id: agentID)?.runtimeMode == .sdkBridge else { return }
                        activeAgentID = agentID
                        appState.focusedAgentID = nil
                    }
                    .task {
                        prepareSDKDraft()
                    }
                    .onChange(of: selectedDrawerAgentID) { _, agentID in
                        guard let agentID else { return }
                        activeAgentID = agentID
                        selectedDrawerAgentID = nil
                        closeConversationDrawer()
                    }
                    .fileImporter(
                        isPresented: $isFileImporterPresented,
                        allowedContentTypes: PromptFileLoader.allowedContentTypes,
                        allowsMultipleSelection: true
                    ) { result in
                        Task {
                            await loadPromptFiles(from: result)
                        }
                    }
            }

            if isConversationDrawerOpen {
                cursorChatConversationDrawer
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .toolbar(isConversationDrawerOpen ? .hidden : .visible, for: .tabBar)
        .animation(Self.drawerAnimation, value: isConversationDrawerOpen)
    }

    @ViewBuilder
    private var cursorChatContent: some View {
        if let activeAgentID {
            if let agent = appState.agent(id: activeAgentID) {
                ChatDetailView(agent: agent)
                    .id(agent.id)
            } else {
                ContentUnavailableView(
                    "Chat Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This chat is no longer in the local cache.")
                )
                .navigationTitle("Cursor Chat")
                .navigationBarTitleDisplayMode(.inline)
            }
        } else {
            cursorChatHome
                .navigationTitle("Cursor Chat")
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    cursorChatComposer
                }
        }
    }

    private var cursorChatHome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !runningCursorChatAgents.isEmpty {
                    activeSessionsSection
                }

                cursorChatHomePrompt
                    .padding(.top, cursorChatAgents.isEmpty ? 122 : 22)

                if !recentCursorChatAgents.isEmpty {
                    cursorChatRecentSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 180)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            isPromptFocused = false
        }
    }

    private var cursorChatHomePrompt: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(uiColor: .systemGreen).opacity(0.12))

                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .systemGreen))
            }
            .frame(width: 58, height: 58)

            Text("What are we building?")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var cursorChatRecentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button {
                    openConversationDrawer()
                } label: {
                    Text("View all")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(uiColor: .systemBlue))
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                ForEach(Array(recentCursorChatAgents.prefix(4).enumerated()), id: \.element.id) { index, agent in
                    Button {
                        activeAgentID = agent.id
                    } label: {
                        CursorChatRecentConversationRow(agent: agent, run: appState.runs(for: agent).first)
                    }
                    .buttonStyle(.plain)

                    if index < min(recentCursorChatAgents.count, 4) - 1 {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.12), lineWidth: 0.5)
            )
        }
    }

    private var activeSessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Active Now")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text("\(runningCursorChatAgents.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                ForEach(Array(runningCursorChatAgents.prefix(3).enumerated()), id: \.element.id) { index, agent in
                    Button {
                        activeAgentID = agent.id
                    } label: {
                        CursorChatActiveSessionRow(agent: agent, run: appState.runs(for: agent).first)
                    }
                    .buttonStyle(.plain)

                    if index < min(runningCursorChatAgents.count, 3) - 1 {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.12), lineWidth: 0.5)
            )
        }
    }

    private var cursorChatConversationDrawer: some View {
        GeometryReader { proxy in
            let width = min(max(proxy.size.width * 0.90, 300), 380)

            ZStack(alignment: .leading) {
                Color.black
                    .opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeConversationDrawer()
                    }

                VStack(spacing: 0) {
                    cursorChatDrawerHeader

                    ChatListContent(
                        runtimeMode: .sdkBridge,
                        experience: .cursorChat,
                        query: $query,
                        currentAgentID: activeAgentID,
                        presentation: .selection($selectedDrawerAgentID)
                    )
                }
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .background(Color(uiColor: .systemGroupedBackground))
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 26,
                        topTrailingRadius: 26,
                        style: .continuous
                    )
                )
                .shadow(color: Color.black.opacity(0.18), radius: 24, x: 12, y: 0)
                .gesture(
                    DragGesture(minimumDistance: 15)
                        .onEnded { value in
                            if value.translation.width < -48 {
                                closeConversationDrawer()
                            }
                        }
                )
            }
        }
        .ignoresSafeArea()
    }

    private var cursorChatDrawerHeader: some View {
        HStack(spacing: 10) {
            Text("Conversations")
                .font(.headline.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                closeConversationDrawer()
                resetCursorChatDraft(focusComposer: true)
            } label: {
                Image(systemName: "square.and.pencil")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New Cursor Chat")

            Button {
                closeConversationDrawer()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close conversations")
        }
        .padding(.horizontal, 16)
        .padding(.top, 60)
        .padding(.bottom, 10)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var cursorChatComposer: some View {
        VStack(spacing: 8) {
            cursorChatWorkspaceStrip

            if shouldShowPromptAttachments {
                promptAttachmentStrip
            }

            if let fileImportMessage {
                Text(fileImportMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }

            cursorChatInputSurface
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var cursorChatWorkspaceStrip: some View {
        HStack(spacing: 8) {
            repositoryMenu

            if let selectedRepository {
                ComposerControlPill(
                    systemName: "arrow.triangle.branch",
                    title: selectedRepository.defaultBranch.nilIfBlank ?? "main",
                    showsChevron: false,
                    maxWidth: 122
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    private var cursorChatInputSurface: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Ask Cursor to build, fix, review, or iterate...")
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                        .padding(.horizontal, 18)
                        .padding(.top, 15)
                }

                TextField("", text: $prompt, axis: .vertical)
                    .lineLimit(2...7)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .focused($isPromptFocused)
                    .padding(.horizontal, 18)
                    .padding(.top, 15)
                    .padding(.bottom, 12)
            }

            HStack(spacing: 10) {
                attachmentMenuButton
                modelMenu

                Spacer(minLength: 0)

                cursorChatSendButton
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.90)
        )
        .cursorChatComposerSurface(cornerRadius: 28)
        .shadow(color: Color.black.opacity(0.10), radius: 18, y: 8)
    }

    private var cursorChatSendButton: some View {
        Button {
            startCursorChat()
        } label: {
            if appState.isLaunching {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                    .frame(width: Self.composerControlSize, height: Self.composerControlSize)
            } else {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(canStartCursorChat ? Color.white : Color(uiColor: .systemGray))
                    .frame(width: Self.composerControlSize, height: Self.composerControlSize)
            }
        }
        .background(
            Circle()
                .fill(canStartCursorChat ? Color(uiColor: .systemBlue) : Color(uiColor: .systemGray5))
        )
        .shadow(color: canStartCursorChat ? Color.blue.opacity(0.28) : .clear, radius: 10, y: 5)
        .disabled(!canStartCursorChat)
        .accessibilityLabel("Start Cursor Chat")
    }

    private var repositoryMenu: some View {
        Menu {
            Button {
                isGeneralConversation = true
                selectedRepositoryURL = nil
                appState.launchDraft.source = .general
            } label: {
                Label("General Chat", systemImage: isGeneralConversation ? "checkmark" : "message")
            }

            ForEach(appState.repositories) { repository in
                Button {
                    isGeneralConversation = false
                    selectedRepositoryURL = repository.url
                    applyRepository(repository)
                } label: {
                    Label(repository.displayName, systemImage: selectedRepository?.id == repository.id ? "checkmark" : "folder")
                }
            }
        } label: {
            ComposerControlPill(
                systemName: selectedRepository == nil ? "message" : "folder",
                title: selectedRepository?.displayName ?? "General Chat",
                maxWidth: selectedRepository == nil ? nil : 210
            )
        }
        .menuIndicator(.hidden)
    }

    private var attachmentMenuButton: some View {
        Menu {
            if appState.capabilities.supportsImagesInPrompt {
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: Self.maxPromptImages,
                    matching: .images
                ) {
                    Label("Photos", systemImage: "photo")
                }
                .disabled(isLoadingPromptImages || promptImages.count >= Self.maxPromptImages)
            }

            Button {
                isFileImporterPresented = true
            } label: {
                Label("Files", systemImage: "doc")
            }
            .disabled(isLoadingPromptFiles || promptFiles.count >= PromptFileLoader.maxFiles)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color(uiColor: .systemBlue))
                .frame(width: Self.composerControlSize, height: Self.composerControlSize)
                .cursorChatComposerSurface(cornerRadius: Self.composerControlSize / 2, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Attach files or images")
        .onChange(of: selectedPhotoItems) { _, items in
            Task {
                await loadPromptImages(from: items)
            }
        }
    }

    private var modelMenu: some View {
        Menu {
            Button {
                selectedModelID = cursorChatPreferredModelID
            } label: {
                Label(
                    ComposerLabelFormatter.modelTitle(AgentRuntimeMode.sdkBridge.preferredLaunchModelTitle),
                    systemImage: currentCursorChatModelID == cursorChatPreferredModelID ? "checkmark" : "cpu"
                )
            }

            ForEach(NewChatModelPickerOptions.visibleModels(from: appState.models, excluding: cursorChatPreferredModelID)) { model in
                Button {
                    selectedModelID = model.id
                } label: {
                    Label(
                        ComposerLabelFormatter.modelTitle(model.displayName),
                        systemImage: currentCursorChatModelID == model.id ? "checkmark" : "cpu"
                    )
                }
            }
        } label: {
            ComposerControlPill(
                systemName: "sparkles",
                title: selectedModelTitle,
                maxWidth: 160
            )
        }
        .menuIndicator(.hidden)
    }

    private var cursorChatPreferredModelID: String {
        AgentRuntimeMode.cursorChatPreferredModelID
    }

    private var currentCursorChatModelID: String {
        CursorChatModelPreference.normalizedModelID(selectedModelID)
    }

    private var selectedRepository: Repository? {
        guard !isGeneralConversation else { return nil }
        if let selectedRepositoryURL,
           let repository = appState.repositories.first(where: { $0.url == selectedRepositoryURL }) {
            return repository
        }
        return appState.selectedRepository ?? appState.repositories.first
    }

    private var selectedModelTitle: String {
        let modelID = currentCursorChatModelID
        let rawTitle = appState.models.first(where: { $0.id == modelID })?.displayName ?? modelID
        return ComposerLabelFormatter.modelTitle(rawTitle)
    }

    private var canStartCursorChat: Bool {
        !appState.isLaunching
            && !isLoadingPromptImages
            && !isLoadingPromptFiles
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldShowPromptAttachments: Bool {
        !promptImages.isEmpty || !promptFiles.isEmpty || isLoadingPromptImages || isLoadingPromptFiles
    }

    private var cursorChatAgents: [Agent] {
        appState.agents.filter { agent in
            guard agent.runtimeMode == .sdkBridge else { return false }
            if case .archived = agent.status { return false }
            return true
        }
    }

    private var runningCursorChatAgents: [Agent] {
        cursorChatAgents.filter { agent in
            let status = appState.runs(for: agent).first?.status
            return status == .running || status == .creating
        }
    }

    private var recentCursorChatAgents: [Agent] {
        cursorChatAgents.filter { agent in
            let status = appState.runs(for: agent).first?.status
            return status != .running && status != .creating
        }
    }

    private var promptAttachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(promptImages) { image in
                    HStack(spacing: 6) {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                        Text("\(image.width) x \(image.height)")
                            .font(.caption)
                        Button {
                            removePromptImage(image)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove image")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .cursorChatComposerSurface(cornerRadius: 14)
                }

                ForEach(promptFiles) { file in
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                        Text("\(file.filename) - \(file.sizeDescription)")
                            .font(.caption)
                        Button {
                            removePromptFile(file)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove file")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .cursorChatComposerSurface(cornerRadius: 14)
                }

                if isLoadingPromptImages || isLoadingPromptFiles {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.horizontal, 10)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func prepareSDKDraft() {
        appState.launchDraft.applyRuntimeMode(.sdkBridge)
        selectedModelID = currentCursorChatModelID
        appState.launchDraft.modelID = currentCursorChatModelID
        if !isGeneralConversation, selectedRepositoryURL == nil {
            selectedRepositoryURL = appState.selectedRepository?.url ?? appState.repositories.first?.url
        }
        if let selectedRepository {
            applyRepository(selectedRepository)
        } else {
            appState.launchDraft.source = .general
        }
    }

    private func applyRepository(_ repository: Repository) {
        appState.launchDraft.source = .repository(
            url: repository.url,
            startingRef: repository.defaultBranch.nilIfBlank
        )
    }

    private func startCursorChat() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let source: AgentSource
        if let selectedRepository {
            source = .repository(url: selectedRepository.url, startingRef: selectedRepository.defaultBranch.nilIfBlank)
        } else {
            source = .general
        }

        isPromptFocused = false
        appState.launchDraft = AgentLaunchDraft(
            prompt: AgentPrompt(text: text, images: promptImages, files: promptFiles),
            modelID: currentCursorChatModelID,
            source: source,
            runtimeMode: .sdkBridge,
            branchName: nil,
            autoGenerateBranch: true,
            autoCreatePullRequest: false,
            skipReviewerRequest: false
        )

        Task {
            if let result = await appState.launchAgent() {
                activeAgentID = result.agent.id
                appState.focusedAgentID = nil
                prompt = ""
                promptImages = []
                promptFiles = []
                selectedPhotoItems = []
                fileImportMessage = nil
            }
        }
    }

    private func loadPromptImages(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        isLoadingPromptImages = true
        defer {
            isLoadingPromptImages = false
            selectedPhotoItems = []
        }

        var images = promptImages
        for item in items where images.count < Self.maxPromptImages {
            guard let originalData = try? await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: originalData),
                  let promptImage = normalizedPromptImage(from: uiImage) else {
                continue
            }
            images.append(promptImage)
        }
        promptImages = images
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

    private func removePromptImage(_ image: PromptImage) {
        promptImages.removeAll { $0.id == image.id }
        selectedPhotoItems = []
    }

    private func loadPromptFiles(from result: Result<[URL], Error>) async {
        isLoadingPromptFiles = true
        defer { isLoadingPromptFiles = false }

        switch result {
        case .success(let urls):
            let loadResult = PromptFileLoader.loadFiles(from: urls, existingFiles: promptFiles)
            promptFiles = loadResult.files
            fileImportMessage = fileImportMessage(from: loadResult)
        case .failure(let error):
            fileImportMessage = "Could not load files: \(error.localizedDescription)"
        }
    }

    private func removePromptFile(_ file: PromptFile) {
        promptFiles.removeAll { $0.id == file.id }
        fileImportMessage = nil
    }

    private func fileImportMessage(from result: PromptFileLoadResult) -> String? {
        guard !result.skippedFilenames.isEmpty else { return nil }
        return "Skipped unsupported or large files: \(result.skippedFilenames.joined(separator: ", "))"
    }

    private func openConversationDrawer() {
        isPromptFocused = false
        selectedDrawerAgentID = activeAgentID
        withAnimation(Self.drawerAnimation) {
            isConversationDrawerOpen = true
        }
    }

    private func closeConversationDrawer() {
        withAnimation(Self.drawerAnimation) {
            isConversationDrawerOpen = false
        }
    }

    private func resetCursorChatDraft(focusComposer: Bool) {
        activeAgentID = nil
        prompt = ""
        promptImages = []
        promptFiles = []
        selectedPhotoItems = []
        fileImportMessage = nil
        prepareSDKDraft()

        guard focusComposer else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            isPromptFocused = true
        }
    }
}

private struct CursorChatActiveSessionRow: View {
    var agent: Agent
    var run: AgentRun?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(uiColor: .systemBlue).opacity(0.12))
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .systemBlue))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(agent.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct CursorChatRecentConversationRow: View {
    var agent: Agent
    var run: AgentRun?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                Image(systemName: agent.repository.isGeneralChat ? "bubble.left.and.bubble.right" : "folder")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(contextTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let run {
                RunStatusBadge(status: run.status)
            } else {
                Text(agent.updatedAtDescription)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var displayTitle: String {
        let title = agent.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Untitled chat" : title
    }

    private var contextTitle: String {
        agent.repository.isGeneralChat ? "General Chat" : agent.repository.displayName
    }

    private var tint: Color {
        if run?.status == .error {
            return .red
        }
        if run?.status == .finished {
            return .green
        }
        return agent.repository.isGeneralChat ? Color(uiColor: .systemGreen) : .secondary
    }
}

private enum CursorChatConversationScope: String, CaseIterable, Identifiable {
    case all
    case general
    case workspaces

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .general:
            "General"
        case .workspaces:
            "Workspaces"
        }
    }

    var systemName: String {
        switch self {
        case .all:
            "rectangle.stack"
        case .general:
            "bubble.left.and.bubble.right"
        case .workspaces:
            "folder"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all:
            "No Cursor Chats"
        case .general:
            "No General Chats"
        case .workspaces:
            "No Workspace Chats"
        }
    }

    var emptyDescription: String {
        switch self {
        case .all:
            "Message Cursor from the composer to start a workspace chat."
        case .general:
            "Start a General Chat from the composer."
        case .workspaces:
            "Choose a repository from the composer to start a workspace chat."
        }
    }
}

private struct CursorChatScopePicker: View {
    @Binding var selection: CursorChatConversationScope

    var body: some View {
        HStack(spacing: 8) {
            ForEach(CursorChatConversationScope.allCases) { scope in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        selection = scope
                    }
                } label: {
                    Label(scope.title, systemImage: scope.systemName)
                        .labelStyle(.titleOnly)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selection == scope ? Color(uiColor: .systemBackground) : .primary)
                        .lineLimit(1)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selection == scope ? Color.primary : Color(uiColor: .secondarySystemGroupedBackground))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color(uiColor: .separator).opacity(selection == scope ? 0 : 0.16), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(scope.title)
                .accessibilityAddTraits(selection == scope ? .isSelected : [])
            }

            Spacer(minLength: 0)
        }
    }
}

struct ChatListContent: View {
    enum Presentation {
        case navigation
        case selection(Binding<Agent.ID?>)
    }

    enum Experience {
        case cursorCloud
        case cursorChat

        var title: String {
            switch self {
            case .cursorCloud:
                "Cursor Cloud"
            case .cursorChat:
                "Cursor Chat"
            }
        }

        var subtitle: String {
            switch self {
            case .cursorCloud:
                "Structured Cloud Agent runs, artifacts, and pull requests."
            case .cursorChat:
                "Start a live workspace conversation and keep iterating."
            }
        }

        var emptyTitle: String {
            switch self {
            case .cursorCloud:
                "No Cloud Runs"
            case .cursorChat:
                "No Cursor Chats"
            }
        }

        var emptyDescription: String {
            switch self {
            case .cursorCloud:
                "Start a Cursor Cloud run from the compose button."
            case .cursorChat:
                "Message Cursor from the composer to start a workspace chat."
            }
        }

        var systemName: String {
            switch self {
            case .cursorCloud:
                "cloud.fill"
            case .cursorChat:
                "message.fill"
            }
        }

        var tint: Color {
            switch self {
            case .cursorCloud:
                Color(uiColor: .systemBlue)
            case .cursorChat:
                Color(uiColor: .systemGreen)
            }
        }

        var statusLabel: String {
            switch self {
            case .cursorCloud:
                "Direct"
            case .cursorChat:
                "Live"
            }
        }

        var overviewSubtitle: String {
            switch self {
            case .cursorCloud:
                "Direct Cloud Agent workflow"
            case .cursorChat:
                "SDK-backed workspace conversations"
            }
        }

        var listSpacing: CGFloat {
            switch self {
            case .cursorCloud:
                18
            case .cursorChat:
                16
            }
        }
    }

    @Environment(AppState.self) private var appState
    var runtimeMode: AgentRuntimeMode
    var experience: Experience
    @Binding var query: String
    var currentAgentID: Agent.ID?
    var presentation: Presentation
    @State private var expandedWorkspaceGroupIDs: Set<WorkspaceAgentGroup.ID> = []
    @State private var cursorChatScope: CursorChatConversationScope = .all

    private static let collapsedWorkspaceThreadLimit = 6

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: experience.listSpacing) {
                AgentSessionScreenHeader(
                    experience: experience,
                    query: $query,
                    activeCount: activeAgents.count,
                    runningCount: runningAgents.count,
                    reviewCount: reviewReadyAgents.count,
                    attentionCount: attentionAgents.count
                )

                if case .cursorChat = experience {
                    CursorChatScopePicker(selection: $cursorChatScope)
                }

                listContent
            }
            .padding(.horizontal, 16)
            .padding(.top, experience == .cursorChat ? 10 : 14)
            .padding(.bottom, 110)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            await appState.reloadWorkspace()
        }
    }

    private var runningAgents: [Agent] {
        filteredActiveAgents.filter { agent in
            let status = appState.runs(for: agent).first?.status
            return status == .running || status == .creating
        }
    }

    private var recentAgents: [Agent] {
        filteredActiveAgents.filter { agent in
            let status = appState.runs(for: agent).first?.status
            return status != .running && status != .creating
        }
    }

    private var archivedAgents: [Agent] {
        scopedFilteredAgents.filter { agent in
            if case .archived = agent.status { return true }
            return false
        }
    }

    private var activeRecentAgents: [Agent] {
        recentAgents.filter { agent in
            if case .archived = agent.status { return false }
            return true
        }
    }

    private var reviewReadyAgents: [Agent] {
        activeRecentAgents.filter { agent in
            switch appState.runs(for: agent).first?.status {
            case .some(.error), .some(.cancelled), .some(.expired):
                return false
            default:
                return true
            }
        }
    }

    private var attentionAgents: [Agent] {
        activeRecentAgents.filter { agent in
            switch appState.runs(for: agent).first?.status {
            case .some(.error), .some(.cancelled), .some(.expired):
                return true
            default:
                return false
            }
        }
    }

    private var workspaceGroups: [WorkspaceAgentGroup] {
        var order: [String] = []
        var repositoriesByID: [String: Repository] = [:]
        var agentsByRepositoryID: [String: [Agent]] = [:]

        for agent in activeRecentAgents {
            let repositoryID = workspaceID(for: agent)
            if agentsByRepositoryID[repositoryID] == nil {
                order.append(repositoryID)
                repositoriesByID[repositoryID] = agent.repository
            }
            agentsByRepositoryID[repositoryID, default: []].append(agent)
        }

        let groups: [WorkspaceAgentGroup] = order.compactMap { repositoryID in
            guard let repository = repositoriesByID[repositoryID],
                  let agents = agentsByRepositoryID[repositoryID] else {
                return nil
            }
            return WorkspaceAgentGroup(
                id: repositoryID,
                title: workspaceTitle(for: repository),
                subtitle: workspaceSubtitle(for: repository),
                repository: repository,
                agents: agents
            )
        }

        return groups.sorted { lhs, rhs in
            if lhs.isGeneralChat != rhs.isGeneralChat {
                return lhs.isGeneralChat
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private var cloudAgents: [Agent] {
        appState.agents.filter { $0.runtimeMode == runtimeMode }
    }

    private var filteredAgents: [Agent] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return cloudAgents }
        return cloudAgents.filter { agent in
            agent.name.localizedCaseInsensitiveContains(trimmedQuery)
                || agent.repository.displayName.localizedCaseInsensitiveContains(trimmedQuery)
                || agent.branchName.localizedCaseInsensitiveContains(trimmedQuery)
                || agent.modelID.localizedCaseInsensitiveContains(trimmedQuery)
                || agent.status.title.localizedCaseInsensitiveContains(trimmedQuery)
                || (appState.runs(for: agent).first?.status.title.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }
    }

    private var scopedFilteredAgents: [Agent] {
        guard experience == .cursorChat else { return filteredAgents }

        switch cursorChatScope {
        case .all:
            return filteredAgents
        case .general:
            return filteredAgents.filter { isGeneralChat($0.repository) }
        case .workspaces:
            return filteredAgents.filter { !isGeneralChat($0.repository) }
        }
    }

    private var activeAgents: [Agent] {
        cloudAgents.filter { agent in
            guard case .archived = agent.status else { return true }
            return false
        }
    }

    private var filteredActiveAgents: [Agent] {
        scopedFilteredAgents.filter { agent in
            guard case .archived = agent.status else { return true }
            return false
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if cloudAgents.isEmpty {
            ContentUnavailableView(
                experience.emptyTitle,
                systemImage: experience.systemName,
                description: Text(experience.emptyDescription)
            )
        } else if filteredAgents.isEmpty {
            ContentUnavailableView(
                "No Matches",
                systemImage: "magnifyingglass",
                description: Text("Try a repository, branch, model, or status.")
            )
        } else if case .cursorChat = experience, scopedFilteredAgents.isEmpty {
            ContentUnavailableView(
                cursorChatScope.emptyTitle,
                systemImage: cursorChatScope.systemName,
                description: Text(cursorChatScope.emptyDescription)
            )
        } else if case .cursorChat = experience {
            cursorChatListContent
        } else {
            cursorCloudListContent
        }
    }

    @ViewBuilder
    private var cursorCloudListContent: some View {
        cloudRunSection(.running, agents: runningAgents)
        cloudRunSection(.review, agents: reviewReadyAgents)
        cloudRunSection(.attention, agents: attentionAgents)
        cloudRunSection(.archived, agents: archivedAgents)
    }

    @ViewBuilder
    private var cursorChatListContent: some View {
        if !runningAgents.isEmpty {
            cursorChatPinnedSection(title: "Active Now", agents: runningAgents)
        }

        ForEach(workspaceGroups) { group in
            cursorChatWorkspaceSection(group)
        }

        if !archivedAgents.isEmpty {
            cursorChatPinnedSection(title: "Archived", agents: archivedAgents)
        }
    }

    @ViewBuilder
    private func cursorChatPinnedSection(title: String, agents: [Agent]) -> some View {
        if !agents.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: title == "Active Now" ? "dot.radiowaves.left.and.right" : "archivebox")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(title == "Active Now" ? Color(uiColor: .systemBlue) : .secondary)
                        .frame(width: 22)

                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .textCase(.uppercase)

                    Spacer(minLength: 8)

                    Text("\(agents.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(uiColor: .tertiarySystemGroupedBackground)))
                }
                .padding(.horizontal, 4)

                VStack(spacing: 1) {
                    ForEach(agents) { agent in
                        conversationRow(agent, style: .drawer)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cursorChatWorkspaceSection(_ group: WorkspaceAgentGroup) -> some View {
        let isExpanded = expandedWorkspaceGroupIDs.contains(group.id)
        let hiddenCount = max(0, group.agents.count - Self.collapsedWorkspaceThreadLimit)
        let visibleAgents = isExpanded || hiddenCount == 0
            ? group.agents
            : Array(group.agents.prefix(Self.collapsedWorkspaceThreadLimit))

        VStack(alignment: .leading, spacing: 2) {
            Button {
                if hiddenCount > 0 {
                    toggleWorkspaceGroup(group.id)
                }
            } label: {
                HStack(alignment: .center, spacing: 9) {
                    Image(systemName: group.isGeneralChat ? "bubble.left.and.bubble.right" : "folder")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(group.isGeneralChat ? Color(uiColor: .systemGreen) : .secondary)
                        .frame(width: 20)

                    Text(group.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)

                    if !group.subtitle.isEmpty, !group.isGeneralChat {
                        Text(group.subtitle)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    if hiddenCount > 0 {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 4)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)

            VStack(spacing: 1) {
                ForEach(visibleAgents) { agent in
                    conversationRow(agent, style: .drawer)
                }

                if hiddenCount > 0, !isExpanded {
                    Button {
                        toggleWorkspaceGroup(group.id)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "ellipsis")
                                .frame(width: 18)
                            Text("Show \(hiddenCount) more")
                            Spacer(minLength: 0)
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 26)
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private func cloudRunSection(_ section: CloudRunSection, agents: [Agent]) -> some View {
        if !agents.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 9) {
                    Image(systemName: section.symbolName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(section.tint)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(section.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(section.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Text("\(agents.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(uiColor: .tertiarySystemGroupedBackground)))
                }
                .padding(.horizontal, 4)

                VStack(spacing: 0) {
                    ForEach(Array(agents.enumerated()), id: \.element.id) { index, agent in
                        cloudRunRow(agent)

                        if index < agents.count - 1 {
                            Divider()
                                .padding(.leading, 58)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(uiColor: .separator).opacity(0.12), lineWidth: 0.5)
                )
            }
        }
    }

    @ViewBuilder
    private func cloudRunRow(_ agent: Agent) -> some View {
        let run = appState.runs(for: agent).first
        let metadata = conversationMetadata(for: agent, run: run)
        switch presentation {
        case .navigation:
            NavigationLink(value: agent.id) {
                CloudRunReviewRow(agent: agent, run: run, metadata: metadata)
            }
            .buttonStyle(.plain)
        case .selection(let selectedAgentID):
            Button {
                selectedAgentID.wrappedValue = agent.id
            } label: {
                CloudRunReviewRow(
                    agent: agent,
                    run: run,
                    metadata: metadata,
                    isSelected: selectedAgentID.wrappedValue == agent.id
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func conversationRow(_ agent: Agent, style: ConversationThreadRowStyle) -> some View {
        let run = appState.runs(for: agent).first
        let metadata = conversationMetadata(for: agent, run: run)
        let isCurrentAgent = currentAgentID == agent.id
        switch presentation {
        case .navigation:
            NavigationLink(value: agent.id) {
                ConversationThreadRow(agent: agent, run: run, metadata: metadata, isSelected: isCurrentAgent, style: style)
            }
            .buttonStyle(.plain)
        case .selection(let selectedAgentID):
            Button {
                selectedAgentID.wrappedValue = agent.id
            } label: {
                ConversationThreadRow(
                    agent: agent,
                    run: run,
                    metadata: metadata,
                    isSelected: selectedAgentID.wrappedValue == agent.id || isCurrentAgent,
                    style: style
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func conversationMetadata(for agent: Agent, run: AgentRun?) -> ConversationThreadMetadata {
        guard let run else {
            return ConversationThreadMetadata(
                preview: workspaceSubtitle(for: agent.repository),
                changedFileCount: 0,
                artifactCount: agent.artifactCount,
                hasPullRequest: agent.pullRequestURL != nil,
                isGeneralChat: isGeneralChat(agent.repository)
            )
        }

        let events = appState.events(for: run.id)
        let changedFileCount = Set(events.suffix(24).compactMap { event in
            WorkspaceChangeSetParser.shouldInspect(event) ? WorkspaceChangeSetParser.changeSet(from: event) : nil
        }
            .flatMap { changeSet in
                changeSet.changes.map(\.path)
            })
            .count
        if let event = events.last(where: { event in
            switch event.kind {
            case .user, .assistant, .result, .task, .request, .status, .done, .error:
                !event.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            default:
                false
            }
        }) {
            return ConversationThreadMetadata(
                preview: conversationPreview(from: event.message),
                changedFileCount: changedFileCount,
                artifactCount: agent.artifactCount,
                hasPullRequest: agent.pullRequestURL != nil,
                isGeneralChat: isGeneralChat(agent.repository)
            )
        }

        return ConversationThreadMetadata(
            preview: run.status.isTerminal ? run.status.title : "\(agent.runtimeMode.title) is \(run.status.title.lowercased())",
            changedFileCount: changedFileCount,
            artifactCount: agent.artifactCount,
            hasPullRequest: agent.pullRequestURL != nil,
            isGeneralChat: isGeneralChat(agent.repository)
        )
    }

    private func workspaceID(for agent: Agent) -> String {
        agent.repository.isGeneralChat ? "general-chat" : agent.repository.id
    }

    private func workspaceTitle(for repository: Repository) -> String {
        repository.isGeneralChat ? "General Chat" : repository.displayName
    }

    private func workspaceSubtitle(for repository: Repository) -> String {
        if repository.isGeneralChat {
            return "Repo-less conversations"
        }
        return repository.defaultBranch.isEmpty ? "Repository workspace" : repository.defaultBranch
    }

    private func conversationPreview(from message: String) -> String {
        let collapsed = message
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return "Workspace conversation" }
        guard collapsed.count > 140 else { return collapsed }
        return String(collapsed.prefix(140)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func isGeneralChat(_ repository: Repository) -> Bool {
        repository.isGeneralChat
    }

    private func toggleWorkspaceGroup(_ id: WorkspaceAgentGroup.ID) {
        if expandedWorkspaceGroupIDs.contains(id) {
            expandedWorkspaceGroupIDs.remove(id)
        } else {
            expandedWorkspaceGroupIDs.insert(id)
        }
    }
}

private struct WorkspaceAgentGroup: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var repository: Repository
    var agents: [Agent]

    var isGeneralChat: Bool {
        id == "general-chat"
    }
}

private enum CloudRunSection {
    case running
    case review
    case attention
    case archived

    var title: String {
        switch self {
        case .running:
            "Running"
        case .review:
            "Ready for Review"
        case .attention:
            "Needs Attention"
        case .archived:
            "Archived"
        }
    }

    var subtitle: String {
        switch self {
        case .running:
            "Live Cloud Agent work"
        case .review:
            "Results, artifacts, and pull requests"
        case .attention:
            "Failed, cancelled, or expired runs"
        case .archived:
            "Completed history"
        }
    }

    var symbolName: String {
        switch self {
        case .running:
            "dot.radiowaves.left.and.right"
        case .review:
            "tray.full"
        case .attention:
            "exclamationmark.triangle"
        case .archived:
            "archivebox"
        }
    }

    var tint: Color {
        switch self {
        case .running:
            Color(uiColor: .systemBlue)
        case .review:
            Color(uiColor: .systemGreen)
        case .attention:
            Color(uiColor: .systemOrange)
        case .archived:
            .secondary
        }
    }
}

private struct ConversationThreadMetadata: Hashable {
    var preview: String
    var changedFileCount: Int
    var artifactCount: Int
    var hasPullRequest: Bool
    var isGeneralChat: Bool
}

private struct CloudRunReviewRow: View {
    var agent: Agent
    var run: AgentRun?
    var metadata: ConversationThreadMetadata
    var isSelected = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))

                Image(systemName: symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 36, height: 36)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(agent.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 6)

                    CloudRunActionBadge(title: actionTitle, tint: tint)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(agent.repository.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(agent.updatedAtDescription)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                cloudRunMetadata
            }

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.blue)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.blue.opacity(0.10))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var cloudRunMetadata: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                CloudRunPill(systemName: "arrow.triangle.branch", title: branchTitle)
                CloudRunPill(systemName: "cpu", title: agent.modelID)
                outputPills
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                CloudRunPill(systemName: "arrow.triangle.branch", title: branchTitle)
                outputPills
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var outputPills: some View {
        if metadata.changedFileCount > 0 {
            CloudRunPill(systemName: "doc.text.magnifyingglass", title: changedFileTitle)
        }

        if metadata.artifactCount > 0 {
            CloudRunPill(systemName: "tray.full", title: "\(metadata.artifactCount)")
        }

        if metadata.hasPullRequest {
            CloudRunPill(systemName: "arrow.up.right.square", title: "PR")
        }
    }

    private var branchTitle: String {
        agent.branchName.nilIfBlank ?? "main"
    }

    private var changedFileTitle: String {
        "\(metadata.changedFileCount) \(metadata.changedFileCount == 1 ? "file" : "files")"
    }

    private var actionTitle: String {
        if case .archived = agent.status {
            return "Archived"
        }

        switch run?.status {
        case .some(.creating):
            return "Creating"
        case .some(.running):
            return "Live"
        case .some(.finished):
            return hasReviewOutput ? "Review" : "Finished"
        case .some(.error):
            return "Issue"
        case .some(.cancelled):
            return "Cancelled"
        case .some(.expired):
            return "Expired"
        case .some(.unknown(let value)):
            return value
        case .none:
            return "Open"
        }
    }

    private var hasReviewOutput: Bool {
        metadata.changedFileCount > 0 || metadata.artifactCount > 0 || metadata.hasPullRequest
    }

    private var symbolName: String {
        if case .archived = agent.status {
            return "archivebox"
        }

        switch run?.status {
        case .some(.finished):
            return hasReviewOutput ? "tray.full" : "checkmark.circle"
        case .some(.error):
            return "exclamationmark.triangle"
        case .some(.cancelled), .some(.expired):
            return "stop.circle"
        case .some(.running), .some(.creating):
            return "dot.radiowaves.left.and.right"
        case .some(.unknown), .none:
            return "cloud"
        }
    }

    private var tint: Color {
        if case .archived = agent.status {
            return .secondary
        }

        switch run?.status {
        case .some(.finished):
            return hasReviewOutput ? Color(uiColor: .systemGreen) : .green
        case .some(.error):
            return .red
        case .some(.cancelled), .some(.expired):
            return .secondary
        case .some(.running), .some(.creating):
            return Color(uiColor: .systemBlue)
        case .some(.unknown), .none:
            return Color(uiColor: .systemBlue)
        }
    }
}

private struct CloudRunPill: View {
    var systemName: String
    var title: String

    var body: some View {
        Label(title, systemImage: systemName)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(uiColor: .tertiarySystemGroupedBackground)))
    }
}

private struct CloudRunActionBadge: View {
    var title: String
    var tint: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.11)))
    }
}

private enum ConversationThreadRowStyle {
    case card
    case drawer
}

private struct ConversationThreadRow: View {
    var agent: Agent
    var run: AgentRun?
    var metadata: ConversationThreadMetadata
    var isSelected = false
    var style: ConversationThreadRowStyle = .card

    var body: some View {
        switch style {
        case .card:
            cardBody
        case .drawer:
            drawerBody
        }
    }

    private var cardBody: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                Image(systemName: symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 36, height: 36)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(agent.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(agent.updatedAtDescription)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Text(metadata.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                metadataRow
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.blue.opacity(0.10))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var drawerBody: some View {
        HStack(alignment: .center, spacing: 8) {
            runningIndicator

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(displayTitle)
                        .font(.body.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 6)

                    drawerTrailingStatus
                }

                if shouldShowDrawerPreview {
                    HStack(spacing: 6) {
                        Text(metadata.preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 0)

                        drawerOutputIndicators
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var runningIndicator: some View {
        if run?.status == .running || run?.status == .creating {
            Circle()
                .fill(Color(uiColor: .systemBlue))
                .frame(width: 7, height: 7)
        } else {
            Color.clear
                .frame(width: 7, height: 7)
        }
    }

    @ViewBuilder
    private var drawerTrailingStatus: some View {
        if let run, !run.status.isTerminal {
            Text(run.status.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color(uiColor: .systemBlue))
                .lineLimit(1)
        } else {
            Text(agent.updatedAtDescription)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private var shouldShowDrawerPreview: Bool {
        let preview = metadata.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        return !preview.isEmpty && preview.localizedCaseInsensitiveCompare(displayTitle) != .orderedSame
    }

    @ViewBuilder
    private var drawerOutputIndicators: some View {
        if metadata.changedFileCount > 0 {
            Label("\(metadata.changedFileCount)", systemImage: "doc.text.magnifyingglass")
                .labelStyle(.iconOnly)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        if metadata.artifactCount > 0 {
            Image(systemName: "tray.full")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        if metadata.hasPullRequest {
            Image(systemName: "arrow.up.right.square")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var metadataRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                contextPill
                ConversationThreadPill(systemName: "cpu", title: agent.modelID)
                outputPills
                Spacer(minLength: 0)
                statusAccessories
            }

            HStack(spacing: 6) {
                contextPill
                outputPills
                Spacer(minLength: 0)
                statusAccessories
            }
        }
    }

    @ViewBuilder
    private var contextPill: some View {
        if metadata.isGeneralChat {
            ConversationThreadPill(systemName: "bubble.left.and.bubble.right", title: "General")
        } else {
            ConversationThreadPill(systemName: "arrow.triangle.branch", title: agent.branchName.nilIfBlank ?? "Branch")
        }
    }

    @ViewBuilder
    private var outputPills: some View {
        if metadata.changedFileCount > 0 {
            ConversationThreadPill(systemName: "doc.text.magnifyingglass", title: changedFileTitle)
        }

        if metadata.artifactCount > 0 {
            ConversationThreadPill(systemName: "tray.full", title: "\(metadata.artifactCount)")
        }

        if metadata.hasPullRequest {
            ConversationThreadPill(systemName: "arrow.up.right.square", title: "PR")
        }
    }

    @ViewBuilder
    private var statusAccessories: some View {
        if let run {
            RunStatusBadge(status: run.status)
        }

        if isSelected {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.blue)
        }
    }

    private var changedFileTitle: String {
        "\(metadata.changedFileCount) \(metadata.changedFileCount == 1 ? "file" : "files")"
    }

    private var displayTitle: String {
        let title = agent.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Untitled chat" : title
    }

    private var symbolName: String {
        switch run?.status {
        case .some(.finished):
            "checkmark.circle"
        case .some(.error):
            "exclamationmark.triangle"
        case .some(.cancelled), .some(.expired):
            "stop.circle"
        case .some(.running), .some(.creating):
            "dot.radiowaves.left.and.right"
        case .some(.unknown), .none:
            metadata.isGeneralChat ? "bubble.left.and.bubble.right" : "message"
        }
    }

    private var tint: Color {
        switch run?.status {
        case .some(.finished):
            .green
        case .some(.error):
            .red
        case .some(.cancelled), .some(.expired):
            .secondary
        case .some(.running), .some(.creating):
            .blue
        case .some(.unknown), .none:
            Color(uiColor: .systemGreen)
        }
    }
}

private struct ConversationThreadPill: View {
    var systemName: String
    var title: String

    var body: some View {
        Label(title, systemImage: systemName)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(uiColor: .tertiarySystemGroupedBackground)))
    }
}

private struct AgentSessionScreenHeader: View {
    var experience: ChatListContent.Experience
    @Binding var query: String
    var activeCount: Int
    var runningCount: Int
    var reviewCount: Int
    var attentionCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CloudChatSearchField(
                query: $query,
                placeholder: experience == .cursorCloud ? "Search runs" : "Search chats"
            )

            if case .cursorCloud = experience {
                CloudChatOverviewPanel(
                    experience: experience,
                    activeCount: activeCount,
                    runningCount: runningCount,
                    reviewCount: reviewCount,
                    attentionCount: attentionCount
                )
            }
        }
    }
}

private struct CloudChatSearchField: View {
    @Binding var query: String
    var placeholder: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .font(.body)
        .padding(.horizontal, 13)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 0.5)
        )
    }
}

private struct CloudChatOverviewPanel: View {
    var experience: ChatListContent.Experience
    var activeCount: Int
    var runningCount: Int
    var reviewCount: Int
    var attentionCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(experience.tint.opacity(0.12))
                    Image(systemName: experience.systemName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(experience.tint)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(experience.title)
                        .font(.headline.weight(.semibold))
                    Text(experience.overviewSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Label(summaryStatusTitle, systemImage: summaryStatusSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(summaryStatusTint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(summaryStatusTint.opacity(0.11)))
            }

            HStack(spacing: 8) {
                CloudChatMetric(title: "Running", value: runningCount)
                CloudChatMetric(title: "Review", value: reviewCount)
                CloudChatMetric(title: "Attention", value: attentionCount)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.12), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }

    private var summaryStatusTitle: String {
        if attentionCount > 0 {
            return "\(attentionCount) attention"
        }
        if runningCount > 0 {
            return "\(runningCount) live"
        }
        if reviewCount > 0 {
            return "\(reviewCount) ready"
        }
        return "\(activeCount) active"
    }

    private var summaryStatusSymbol: String {
        if attentionCount > 0 {
            return "exclamationmark.triangle.fill"
        }
        if runningCount > 0 {
            return "dot.radiowaves.left.and.right"
        }
        if reviewCount > 0 {
            return "tray.full.fill"
        }
        return "checkmark.circle.fill"
    }

    private var summaryStatusTint: Color {
        if attentionCount > 0 {
            return Color(uiColor: .systemOrange)
        }
        if runningCount > 0 {
            return Color(uiColor: .systemBlue)
        }
        if reviewCount > 0 {
            return Color(uiColor: .systemGreen)
        }
        return experience.tint
    }
}

private struct CloudChatMetric: View {
    var title: String
    var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)")
                .font(.headline.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
    }
}

private extension View {
    @ViewBuilder
    func cursorChatComposerSurface(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
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
