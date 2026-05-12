import PhotosUI
import SwiftUI
import UIKit

struct SDKNewSessionSheet: View {
    var body: some View {
        NavigationStack {
            SDKNewSessionView(presentation: .sheet)
        }
    }
}

enum SDKNewSessionPresentation: Equatable {
    case sheet
    case detail
}

struct SDKNewSessionView: View {
    private enum SourceMode: String, CaseIterable, Identifiable {
        case installed = "Installed"
        case manual = "Manual URL"
        case pullRequest = "Pull Request"

        var id: String { rawValue }
    }

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    var presentation: SDKNewSessionPresentation
    @State private var sourceMode: SourceMode = .installed
    @State private var manualRepositoryURL = ""
    @State private var pullRequestURL = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isLoadingPromptImages = false
    @State private var isPromptFileImporterPresented = false
    @State private var isLoadingPromptFiles = false
    @State private var promptFileImportMessage: String?
    @State private var cursorSDKOnboardingSheet: CursorSDKOnboardingSheet?
    @FocusState private var focusedField: Field?

    private enum Field {
        case manualURL
        case pullRequestURL
        case startingRef
        case branchName
        case prompt
    }

    var body: some View {
        @Bindable var appState = appState

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SDKNewSessionReadinessCard(
                    isReady: appState.isSDKBridgeReadyForLaunch,
                    issue: appState.sdkBridgeReadinessIssue,
                    openSetup: { cursorSDKOnboardingSheet = .setup }
                )

                SDKSessionCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SDKSectionHeader(
                            title: "Workspace",
                            detail: "Choose where Cursor SDK should work before you send the first message.",
                            systemImage: "folder"
                        )

                        Picker("Source", selection: $sourceMode) {
                            ForEach(SourceMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: sourceMode) { _, mode in
                            updateSourceMode(mode)
                        }

                        sourceControls
                    }
                }

                SDKSessionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SDKSectionHeader(
                            title: "Output",
                            detail: "Decide whether Cursor should open a PR and how the branch should be named.",
                            systemImage: "arrow.triangle.branch"
                        )

                        Toggle("Open pull request", isOn: autoCreatePRBinding)

                        if appState.launchDraft.autoCreatePullRequest {
                            Toggle("Request reviewers", isOn: requestReviewersBinding)
                        }

                        Toggle("Let Cursor name branch", isOn: autoNameBranchBinding)

                        if !appState.launchDraft.autoGenerateBranch {
                            TextField("Working branch name", text: branchNameBinding)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .branchName)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("New SDK Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if presentation == .sheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            sdkLaunchComposer
        }
        .task {
            appState.launchDraft.runMode = .sdkBridge
            appState.syncSDKBridgeConfiguration()
            seedSourceFields()
            if appState.isSDKBridgePaired {
                await appState.reloadSDKBridgeProfiles()
            }
        }
        .onChange(of: appState.sdkBridgeConnectionState) { _, _ in
            appState.launchDraft.runMode = .sdkBridge
        }
        .fileImporter(
            isPresented: $isPromptFileImporterPresented,
            allowedContentTypes: PromptFileLoader.allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            Task {
                await loadPromptFiles(from: result)
            }
        }
        .sheet(item: $cursorSDKOnboardingSheet) { _ in
            CursorSDKOnboardingView(
                onUseCloud: {
                    appState.launchDraft.runMode = .cloudAgent
                    dismiss()
                },
                onUseSDK: {
                    appState.launchDraft.runMode = .sdkBridge
                },
                onOpenSettings: {
                    appState.selectedTab = .settings
                    dismiss()
                }
            )
        }
    }

    private var sdkLaunchComposer: some View {
        VStack(spacing: 10) {
            if let issue = appState.sdkBridgeLaunchIssue {
                Text(issue)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if shouldShowComposerContext {
                sdkComposerContextStrip
            }

            Picker("Intent", selection: sdkMessageIntentBinding) {
                ForEach(SDKMessageIntent.allCases) { intent in
                    Label(intent.title, systemImage: intent.symbolName)
                        .tag(intent)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("SDK message intent")

            sdkComposerToolRow

            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: 5,
                        matching: .images
                    ) {
                        Label("Images", systemImage: "photo")
                    }
                    .disabled(isLoadingPromptImages)

                    Button {
                        isPromptFileImporterPresented = true
                    } label: {
                        Label("Files", systemImage: "doc")
                    }
                    .disabled(isLoadingPromptFiles)
                } label: {
                    Image(systemName: "plus")
                        .font(.title3)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color(uiColor: .secondarySystemBackground)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Attach context")
                .onChange(of: selectedPhotoItems) { _, items in
                    Task {
                        await loadPromptImages(from: items)
                    }
                }

                TextField("Ask Cursor SDK...", text: sdkPromptTextBinding, axis: .vertical)
                    .lineLimit(1...5)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .focused($focusedField, equals: .prompt)
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
                    .accessibilityIdentifier("sdk.newsession.prompt")

                Button {
                    launch()
                } label: {
                    if appState.isLaunching {
                        ProgressView()
                            .frame(width: 38, height: 38)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 34))
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: 38, height: 38)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!appState.canLaunchAgent || appState.isLaunching)
                .accessibilityLabel("Launch SDK Session")
                .accessibilityIdentifier("sdk.newsession.launch")
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var sdkComposerToolRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("Default") {
                        appState.launchDraft.modelID = nil
                    }
                    ForEach(NewChatModelPickerOptions.visibleModels(from: appState.models)) { model in
                        Button(model.displayName) {
                            appState.launchDraft.modelID = NewChatModelPickerOptions.modelID(from: model.id)
                        }
                    }
                } label: {
                    SDKComposerChip(title: selectedModelTitle, systemImage: "cpu")
                }
                .buttonStyle(.plain)

                Menu {
                    Button("None") {
                        appState.launchDraft.sdkMCPProfileID = nil
                    }
                    ForEach(appState.sdkBridgeProfiles) { profile in
                        Button(profile.name) {
                            appState.launchDraft.sdkMCPProfileID = profile.id
                        }
                    }
                } label: {
                    SDKComposerChip(title: selectedProfileTitle, systemImage: "point.3.connected.trianglepath.dotted")
                }
                .buttonStyle(.plain)

                Text("\(appState.launchDraft.prompt.text.count) chars")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private var sdkComposerContextStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLoadingPromptImages || isLoadingPromptFiles {
                ProgressView("Loading context")
                    .font(.footnote)
            }

            if let promptFileImportMessage {
                Text(promptFileImportMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !appState.launchDraft.prompt.images.isEmpty || !appState.launchDraft.prompt.files.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(appState.launchDraft.prompt.images) { image in
                            SDKContextPill(
                                title: "\(image.width) x \(image.height)",
                                systemImage: "photo",
                                remove: { removePromptImage(image) }
                            )
                        }

                        ForEach(appState.launchDraft.prompt.files) { file in
                            SDKContextPill(
                                title: "\(file.filename) - \(file.sizeDescription)",
                                systemImage: "doc.text",
                                remove: { removePromptFile(file) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var shouldShowComposerContext: Bool {
        isLoadingPromptImages || isLoadingPromptFiles || promptFileImportMessage != nil || !appState.launchDraft.prompt.images.isEmpty || !appState.launchDraft.prompt.files.isEmpty
    }

    private var sdkMessageIntentBinding: Binding<SDKMessageIntent> {
        Binding {
            appState.launchDraft.sdkMessageIntent
        } set: { intent in
            appState.launchDraft.sdkMessageIntent = intent
        }
    }

    private var sdkPromptTextBinding: Binding<String> {
        Binding {
            appState.launchDraft.prompt.text
        } set: { text in
            appState.launchDraft.prompt.text = text
        }
    }

    @ViewBuilder
    private var sourceControls: some View {
        switch sourceMode {
        case .installed:
            if appState.repositories.isEmpty {
                ContentUnavailableView(
                    "No Repositories",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Refresh after Cursor finishes loading connected repositories.")
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                SDKSelectionMenuRow(
                    title: "Repository",
                    value: selectedRepositoryTitle,
                    systemImage: "folder"
                ) {
                    ForEach(appState.repositories) { repository in
                        Button(repository.displayName) {
                            selectRepository(repository)
                        }
                    }
                }

                TextField("Base branch or ref", text: startingRefBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .startingRef)
            }
        case .manual:
            TextField("https://github.com/owner/repository", text: $manualRepositoryURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .manualURL)
                .onChange(of: manualRepositoryURL) { _, value in
                    updateManualRepository(value)
                }

            TextField("Base branch or ref", text: startingRefBinding)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .startingRef)
        case .pullRequest:
            TextField("https://github.com/owner/repository/pull/123", text: $pullRequestURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .pullRequestURL)
                .onChange(of: pullRequestURL) { _, value in
                    updatePullRequest(value)
                }
        }
    }

    private var selectedRepositoryTitle: String {
        appState.selectedRepository?.displayName ?? "Choose repository"
    }

    private var selectedModelTitle: String {
        guard let modelID = NewChatModelPickerOptions.selection(from: appState.launchDraft.modelID) else {
            return "Default"
        }
        return appState.models.first(where: { $0.id == modelID })?.displayName ?? modelID
    }

    private var selectedProfileTitle: String {
        selectedProfile?.name ?? "None"
    }

    private var selectedProfile: SDKBridgeMCPProfile? {
        guard let profileID = appState.launchDraft.sdkMCPProfileID else { return nil }
        return appState.sdkBridgeProfiles.first { $0.id == profileID }
    }

    private var startingRefBinding: Binding<String> {
        Binding {
            if case .repository(_, let startingRef) = appState.launchDraft.source {
                return startingRef ?? ""
            }
            return ""
        } set: { value in
            if case .repository(let url, _) = appState.launchDraft.source {
                appState.launchDraft.source = .repository(url: url, startingRef: value.nilIfBlank)
            }
        }
    }

    private var branchNameBinding: Binding<String> {
        Binding {
            appState.launchDraft.branchName ?? ""
        } set: { value in
            appState.launchDraft.branchName = value.nilIfBlank
        }
    }

    private var autoCreatePRBinding: Binding<Bool> {
        Binding {
            appState.launchDraft.autoCreatePullRequest
        } set: { value in
            appState.launchDraft.autoCreatePullRequest = value
            appState.launchDraft.skipReviewerRequest = value ? appState.launchDraft.skipReviewerRequest ?? false : nil
        }
    }

    private var requestReviewersBinding: Binding<Bool> {
        Binding {
            !(appState.launchDraft.skipReviewerRequest ?? false)
        } set: { value in
            appState.launchDraft.skipReviewerRequest = !value
        }
    }

    private var autoNameBranchBinding: Binding<Bool> {
        Binding {
            appState.launchDraft.autoGenerateBranch
        } set: { value in
            appState.launchDraft.autoGenerateBranch = value
            if value {
                appState.launchDraft.branchName = nil
            }
        }
    }

    private func seedSourceFields() {
        appState.launchDraft.runMode = .sdkBridge
        switch appState.launchDraft.source {
        case .repository(let url, _):
            if appState.repositories.contains(where: { $0.url == url }) {
                sourceMode = .installed
            } else {
                sourceMode = .manual
                manualRepositoryURL = url.absoluteString
            }
        case .pullRequest(let url):
            sourceMode = .pullRequest
            pullRequestURL = url.absoluteString
        }
    }

    private func updateSourceMode(_ mode: SourceMode) {
        focusedField = nil
        switch mode {
        case .installed:
            if let repository = appState.selectedRepository ?? appState.repositories.first {
                selectRepository(repository)
            }
        case .manual:
            updateManualRepository(manualRepositoryURL)
        case .pullRequest:
            updatePullRequest(pullRequestURL)
        }
    }

    private func selectRepository(_ repository: Repository) {
        appState.launchDraft.source = .repository(
            url: repository.url,
            startingRef: repository.defaultBranch.nilIfBlank
        )
    }

    private func updateManualRepository(_ value: String) {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        let currentRef: String?
        if case .repository(_, let startingRef) = appState.launchDraft.source {
            currentRef = startingRef
        } else {
            currentRef = nil
        }
        appState.launchDraft.source = .repository(url: url, startingRef: currentRef)
    }

    private func updatePullRequest(_ value: String) {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        appState.launchDraft.source = .pullRequest(url: url)
    }

    private func launch() {
        focusedField = nil
        appState.launchDraft.runMode = .sdkBridge
        Task {
            await appState.launchAgent()
            if presentation == .sheet, appState.errorMessage == nil {
                dismiss()
            }
        }
    }

    private func loadPromptImages(from items: [PhotosPickerItem]) async {
        isLoadingPromptImages = true
        defer {
            isLoadingPromptImages = false
            selectedPhotoItems = []
        }

        var images = appState.launchDraft.prompt.images
        for item in items where images.count < 5 {
            guard let originalData = try? await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: originalData),
                  let promptImage = normalizedPromptImage(from: uiImage) else {
                continue
            }
            images.append(promptImage)
        }
        appState.launchDraft.prompt.images = images
    }

    private func normalizedPromptImage(from image: UIImage) -> PromptImage? {
        let maxDimension: CGFloat = 1600
        let largestDimension = max(image.size.width, image.size.height)
        let scale = largestDimension > maxDimension ? maxDimension / largestDimension : 1
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let normalizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let data = normalizedImage.jpegData(compressionQuality: 0.82) else { return nil }
        return PromptImage(data: data, width: Int(targetSize.width), height: Int(targetSize.height))
    }

    private func removePromptImage(_ image: PromptImage) {
        appState.launchDraft.prompt.images.removeAll { $0.id == image.id }
        selectedPhotoItems = []
    }

    private func loadPromptFiles(from result: Result<[URL], Error>) async {
        isLoadingPromptFiles = true
        defer { isLoadingPromptFiles = false }

        switch result {
        case .success(let urls):
            let loadResult = PromptFileLoader.loadFiles(
                from: urls,
                existingFiles: appState.launchDraft.prompt.files
            )
            appState.launchDraft.prompt.files = loadResult.files
            promptFileImportMessage = fileImportMessage(from: loadResult)
        case .failure(let error):
            promptFileImportMessage = "Could not load files: \(error.localizedDescription)"
        }
    }

    private func removePromptFile(_ file: PromptFile) {
        appState.launchDraft.prompt.files.removeAll { $0.id == file.id }
        promptFileImportMessage = nil
    }

    private func fileImportMessage(from result: PromptFileLoadResult) -> String? {
        guard !result.skippedFilenames.isEmpty else { return nil }
        return "Skipped unsupported or large files: \(result.skippedFilenames.joined(separator: ", "))"
    }
}

private struct SDKNewSessionReadinessCard: View {
    var isReady: Bool
    var issue: String?
    var openSetup: () -> Void

    var body: some View {
        SDKSessionCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.title2)
                    .foregroundStyle(isReady ? Color.green : Color.orange)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 5) {
                    Text(isReady ? "Cursor SDK Ready" : "Cursor SDK Setup Required")
                        .font(.headline)

                    Text(issue ?? "Bridge, Cursor API key, and pairing are ready for SDK sessions.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !isReady {
                        Button(action: openSetup) {
                            Label("Set Up Cursor SDK", systemImage: "point.3.connected.trianglepath.dotted")
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                    }
                }
            }
        }
    }
}

private struct SDKSessionCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
    }
}

private struct SDKSectionHeader: View {
    var title: String
    var detail: String
    var systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)

                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
        }
    }
}

private struct SDKComposerChip: View {
    var title: String
    var systemImage: String

    var body: some View {
        Label {
            Text(title)
                .lineLimit(1)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color(uiColor: .secondarySystemBackground)))
        .overlay(
            Capsule()
                .stroke(Color(uiColor: .separator).opacity(0.25), lineWidth: 0.5)
        )
    }
}

private struct SDKSelectionMenuRow<MenuContent: View>: View {
    var title: String
    var value: String
    var systemImage: String
    private let menuContent: MenuContent

    init(
        title: String,
        value: String,
        systemImage: String,
        @ViewBuilder menuContent: () -> MenuContent
    ) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.menuContent = menuContent()
    }

    var body: some View {
        Menu {
            menuContent
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(.tint)
                    .frame(width: 24)

                Text(title)
                    .foregroundStyle(.primary)

                Spacer()

                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

private struct SDKProfileSummaryStrip: View {
    var profile: SDKBridgeMCPProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(profile.summary)
                .font(.footnote.weight(.medium))

            if let description = profile.description {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
    }
}

private struct SDKContextPill: View {
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
        .padding(.vertical, 7)
        .background(Capsule().fill(Color(uiColor: .tertiarySystemGroupedBackground)))
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
