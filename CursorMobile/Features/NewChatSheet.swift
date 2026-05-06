import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct NewChatSheet: View {
    var body: some View {
        NavigationStack {
            NewChatForm(presentation: .sheet)
        }
    }
}

enum NewChatPresentation: Equatable {
    case sheet
    case detail
}

enum NewChatModelPickerOptions {
    static func visibleModels(from models: [AgentModel]) -> [AgentModel] {
        models.filter { !$0.isCursorDefaultModel }
    }

    static func selection(from modelID: String?) -> String? {
        guard let modelID = modelID?.nilIfBlank else { return nil }
        return modelID.isCursorDefaultModelIdentifier ? nil : modelID
    }

    static func modelID(from selection: String?) -> String? {
        guard let selection = selection?.nilIfBlank else { return nil }
        return selection.isCursorDefaultModelIdentifier ? nil : selection
    }
}

struct NewChatForm: View {
    private enum SourceMode: String, CaseIterable, Identifiable {
        case installed = "Installed"
        case manual = "Manual URL"
        case pullRequest = "Pull Request"

        var id: String { rawValue }
    }

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    var presentation: NewChatPresentation
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

        Form {
            Section("Runtime") {
                Picker("Runtime", selection: runModeBinding) {
                    ForEach(availableRunModes) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Selected", value: appState.launchDraft.runMode.detail)

                if let issue = appState.sdkBridgeReadinessIssue {
                    Label(issue, systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        cursorSDKOnboardingSheet = .setup
                    } label: {
                        Label("Set Up Cursor SDK", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                }
            }

            if appState.launchDraft.runMode == .sdkBridge {
                Section("Cursor SDK Tools") {
                    Picker("MCP Profile", selection: sdkMCPProfileBinding) {
                        Text("None").tag(Optional<String>.none)
                        ForEach(appState.sdkBridgeProfiles) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }

                    if let selectedProfile = selectedSDKProfile {
                        LabeledContent("Profile", value: selectedProfile.summary)
                        if let description = selectedProfile.description {
                            Text(description)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else if appState.sdkBridgeProfiles.isEmpty {
                        Text("No bridge profiles are published. Add MCP or subagent profiles on Runline Bridge to make them available here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Source") {
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

                if sourceMode != .pullRequest {
                    TextField("Base branch or ref", text: startingRefBinding)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .startingRef)
                }
            }

            Section("Model") {
                Picker("Model", selection: modelSelectionBinding) {
                    Text("Default").tag(Optional<String>.none)
                    ForEach(NewChatModelPickerOptions.visibleModels(from: appState.models)) { model in
                        Text(model.displayName).tag(Optional(model.id))
                    }
                }
            }

            Section("Prompt") {
                TextEditor(text: $appState.launchDraft.prompt.text)
                    .frame(minHeight: 150)
                    .focused($focusedField, equals: .prompt)
                    .accessibilityIdentifier("newchat.prompt")

                LabeledContent("Characters", value: "\(appState.launchDraft.prompt.text.count)")

                if appState.capabilities.supportsImagesInPrompt {
                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: 5,
                        matching: .images
                    ) {
                        Label("Attach Images", systemImage: "photo.badge.plus")
                    }
                    .onChange(of: selectedPhotoItems) { _, items in
                        Task {
                            await loadPromptImages(from: items)
                        }
                    }

                    if isLoadingPromptImages {
                        ProgressView("Loading images")
                    }

                    if !appState.launchDraft.prompt.images.isEmpty {
                        ForEach(appState.launchDraft.prompt.images) { image in
                            HStack {
                                Label("\(image.width) x \(image.height)", systemImage: "photo")
                                Spacer()
                                Button("Remove", role: .destructive) {
                                    removePromptImage(image)
                                }
                            }
                        }
                    }
                }

                Button {
                    isPromptFileImporterPresented = true
                } label: {
                    Label("Attach Files", systemImage: "doc.badge.plus")
                }

                if isLoadingPromptFiles {
                    ProgressView("Loading files")
                }

                if let promptFileImportMessage {
                    Text(promptFileImportMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !appState.launchDraft.prompt.files.isEmpty {
                    ForEach(appState.launchDraft.prompt.files) { file in
                        HStack {
                            Label("\(file.filename) - \(file.sizeDescription)", systemImage: "doc.text")
                            Spacer()
                            Button("Remove", role: .destructive) {
                                removePromptFile(file)
                            }
                        }
                    }
                }
            }

            Section {
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
            } header: {
                Text("Output")
            } footer: {
                Text("Cursor bills this run through your Cursor account. Runline does not include Cursor credits.")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("New Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if presentation == .sheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    launch()
                } label: {
                    if appState.isLaunching {
                        ProgressView()
                    } else {
                        Text("Launch")
                    }
                }
                .disabled(!appState.canLaunchAgent || appState.isLaunching)
                .accessibilityIdentifier("newchat.launch")
            }
        }
        .task {
            appState.syncSDKBridgeConfiguration()
            appState.ensureLaunchRunModeIsAvailable()
            seedSourceFields()
            if appState.launchDraft.runMode == .sdkBridge {
                await appState.reloadSDKBridgeProfiles()
            }
        }
        .onChange(of: appState.sdkBridgeConnectionState) { _, _ in
            appState.ensureLaunchRunModeIsAvailable()
        }
        .onChange(of: appState.launchDraft.runMode) { _, mode in
            guard mode == .sdkBridge else { return }
            Task {
                await appState.reloadSDKBridgeProfiles()
            }
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
                },
                onOpenSettings: {
                    appState.launchDraft.runMode = .cloudAgent
                    appState.selectedTab = .settings
                    dismiss()
                }
            )
        }
    }

    @ViewBuilder
    private var sourceControls: some View {
        switch sourceMode {
        case .installed:
            if appState.repositories.isEmpty {
                ContentUnavailableView("No Repositories", systemImage: "folder.badge.questionmark")
            } else {
                Picker("Repository", selection: installedRepositoryBinding) {
                    ForEach(appState.repositories) { repository in
                        Text(repository.displayName).tag(repository.url)
                    }
                }
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

    private var installedRepositoryBinding: Binding<URL> {
        Binding {
            if case .repository(let url, _) = appState.launchDraft.source,
               appState.repositories.contains(where: { $0.url == url }) {
                return url
            }
            return appState.repositories.first?.url ?? URL(string: "https://github.com/owner/repository")!
        } set: { url in
            guard let repository = appState.repositories.first(where: { $0.url == url }) else { return }
            selectRepository(repository)
        }
    }

    private var runModeBinding: Binding<AgentRunMode> {
        Binding {
            appState.launchDraft.runMode
        } set: { mode in
            if mode == .sdkBridge, !appState.isSDKBridgeReadyForLaunch {
                cursorSDKOnboardingSheet = .setup
                appState.launchDraft.runMode = .cloudAgent
                return
            }
            appState.launchDraft.runMode = mode
        }
    }

    private var availableRunModes: [AgentRunMode] {
        AgentRunMode.allCases
    }

    private var modelSelectionBinding: Binding<String?> {
        Binding {
            NewChatModelPickerOptions.selection(from: appState.launchDraft.modelID)
        } set: { modelID in
            appState.launchDraft.modelID = NewChatModelPickerOptions.modelID(from: modelID)
        }
    }

    private var sdkMCPProfileBinding: Binding<String?> {
        Binding {
            appState.launchDraft.sdkMCPProfileID
        } set: { profileID in
            appState.launchDraft.sdkMCPProfileID = profileID
        }
    }

    private var selectedSDKProfile: SDKBridgeMCPProfile? {
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
        Task {
            await appState.launchAgent()
            if presentation == .sheet, appState.errorMessage == nil {
                dismiss()
            }
        }
    }

    private func loadPromptImages(from items: [PhotosPickerItem]) async {
        isLoadingPromptImages = true
        defer { isLoadingPromptImages = false }

        var images: [PromptImage] = []
        for item in items.prefix(5) {
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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
