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
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        let currentAgent = appState.agent(id: agent.id) ?? agent
        let latestRun = appState.runs(for: currentAgent).first

        List {
            Section {
                LabeledContent("Repository", value: currentAgent.repository.displayName)
                LabeledContent("Branch", value: currentAgent.branchName)
                LabeledContent("Model", value: currentAgent.modelID)
                if let latestRun {
                    LabeledContent("Run", value: latestRun.id)
                    LabeledContent("Updated", value: latestRun.updatedAtDescription)
                    HStack {
                        Text("Status")
                        Spacer()
                        RunStatusBadge(status: latestRun.status)
                    }
                }
            }

            if let latestRun {
                Section("Timeline") {
                    let events = appState.events(for: latestRun.id)
                    let timelineItems = ChatTimelineBuilder.items(from: events)
                    if timelineItems.isEmpty {
                        ContentUnavailableView(
                            appState.isStreamExpired(runID: latestRun.id) ? "Stream Paused" : "No Events Yet",
                            systemImage: appState.isStreamExpired(runID: latestRun.id) ? "clock.badge.exclamationmark" : "dot.radiowaves.left.and.right",
                            description: Text(appState.isStreamExpired(runID: latestRun.id) ? "Cursor stopped returning live events. Refresh the chat to poll the latest state." : "Events appear as Cursor works.")
                        )
                    } else {
                        ForEach(timelineItems) { item in
                            StreamEventListRow(item: item)
                        }
                    }

                    if appState.isObserving(runID: latestRun.id) {
                        HStack {
                            ProgressView()
                            Text("Listening for Cursor events")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Runs",
                    systemImage: "message",
                    description: Text("Runs appear after launch or follow-up.")
                )
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(currentAgent.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await appState.refreshAgentDetail(agentID: currentAgent.id)
            if let latestRun = appState.runs(for: currentAgent).first {
                await appState.loadEvents(for: currentAgent, run: latestRun)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if shouldShowComposer(agent: currentAgent, run: latestRun) {
                followUpComposer(agent: currentAgent)
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
        guard let run, run.status.isTerminal else { return false }
        if case .active = agent.status {
            return true
        }
        return false
    }

    private func followUpComposer(agent: Agent) -> some View {
        VStack(spacing: 8) {
            if shouldShowFollowUpAttachments {
                followUpAttachmentStrip
            }

            if let followUpFileImportMessage {
                Text(followUpFileImportMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
            }

            HStack(alignment: .center, spacing: 8) {
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
                        .font(.title3)
                        .frame(width: Self.composerControlSize, height: Self.composerControlSize)
                        .background(Circle().fill(Color(uiColor: .secondarySystemBackground)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Attach context")
                .onChange(of: selectedFollowUpPhotoItems) { _, items in
                    Task {
                        await loadFollowUpImages(from: items)
                    }
                }

                TextField("Message", text: $followUpText, axis: .vertical)
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
                    sendFollowUp(agent: agent)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: Self.composerControlSize, height: Self.composerControlSize)
                }
                .buttonStyle(.plain)
                .disabled(!canSendFollowUp)
                .accessibilityLabel("Send follow-up")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
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
                    .background(Capsule().fill(Color(uiColor: .secondarySystemBackground)))
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
                    .background(Capsule().fill(Color(uiColor: .secondarySystemBackground)))
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
            await appState.createFollowUp(agent: agent, prompt: prompt)
            if let latestRun = appState.runs(for: agent).first {
                await appState.observeRun(agent: agent, run: latestRun)
            }
        }
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

private struct ArtifactsSheet: View {
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
