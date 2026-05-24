import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct NewChatSheet: View {
    var runtimeMode: AgentRuntimeMode?

    var body: some View {
        NavigationStack {
            NewChatForm(presentation: .sheet, runtimeMode: runtimeMode)
        }
    }
}

enum NewChatPresentation: Equatable {
    case sheet
    case detail
}

enum NewChatModelPickerOptions {
    static func visibleModels(from models: [AgentModel], excluding preferredModelID: String? = nil) -> [AgentModel] {
        models.filter { model in
            !model.isCursorDefaultModel && model.id != preferredModelID
        }
    }

    static func selection(from modelID: String?, runtimeMode: AgentRuntimeMode = .cloud) -> String? {
        runtimeMode.normalizedLaunchModelID(modelID)
    }

    static func modelID(from selection: String?, runtimeMode: AgentRuntimeMode = .cloud) -> String? {
        runtimeMode.normalizedLaunchModelID(selection)
    }
}

struct NewChatForm: View {
    private enum SourceMode: String, CaseIterable, Identifiable {
        case installed = "Repository"
        case manual = "URL"
        case pullRequest = "Pull Request"

        var id: String { rawValue }
    }

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    var presentation: NewChatPresentation
    var runtimeMode: AgentRuntimeMode?
    @State private var sourceMode: SourceMode = .installed
    @State private var manualRepositoryURL = ""
    @State private var pullRequestURL = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isLoadingPromptImages = false
    @State private var isPromptFileImporterPresented = false
    @State private var isLoadingPromptFiles = false
    @State private var promptFileImportMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case manualURL
        case pullRequestURL
        case startingRef
        case branchName
        case prompt
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if runtimeMode == nil {
                    runtimeCard
                }
                targetCard
                promptComposerCard
                outputCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 96)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(navigationTitle)
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
            launchBar
        }
        .task {
            applyLockedRuntimeMode()
            seedSourceFields()
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
    }

    private var runtimeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            NewChatSectionHeader(title: "Runtime", systemName: "bolt.horizontal")

            Picker("Runtime", selection: runtimeModeBinding) {
                ForEach(AgentRuntimeMode.allCases) { mode in
                    Text(mode.shortTitle).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if appState.launchDraft.runtimeMode == .sdkBridge {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Cursor Chat uses the Runline bridge with your Cursor key")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .newChatGlassSurface(cornerRadius: 22)
    }

    private var targetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            NewChatSectionHeader(title: targetSectionTitle, systemName: "folder")

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
                inlineTextField(
                    title: "Base ref",
                    placeholder: selectedRepository.flatMap { $0.defaultBranch.nilIfBlank } ?? "main",
                    systemName: "arrow.triangle.branch",
                    text: startingRefBinding,
                    focus: .startingRef
                )
            }
        }
        .padding(14)
        .newChatGlassSurface(cornerRadius: 22)
    }

    private var promptComposerCard: some View {
        VStack(spacing: 0) {
            if appState.launchDraft.runtimeMode == .cloud {
                cloudTaskHeader
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 2)
            }

            promptStarterChips
                .padding(.horizontal, 12)
                .padding(.top, appState.launchDraft.runtimeMode == .cloud ? 6 : 12)
                .padding(.bottom, 4)

            promptEditor

            if shouldShowPromptAttachments {
                attachmentPreviewStrip
                    .padding(.top, 2)
                    .padding(.bottom, 8)
            }

            Divider()
                .opacity(0.32)

            HStack(spacing: 10) {
                attachmentMenuButton

                promptCountLabel

                Spacer(minLength: 0)

                modelMenu
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .newChatGlassSurface(cornerRadius: 26)
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            NewChatSectionHeader(title: outputSectionTitle, systemName: "arrow.triangle.branch")

            VStack(spacing: 0) {
                NewChatOutputToggleRow(
                    title: "Open pull request",
                    isOn: autoCreatePRBinding
                )

                if appState.launchDraft.autoCreatePullRequest {
                    Divider().opacity(0.45)
                    NewChatOutputToggleRow(
                        title: "Request reviewers",
                        isOn: requestReviewersBinding
                    )
                }

                Divider().opacity(0.45)
                NewChatOutputToggleRow(
                    title: "Let Cursor name branch",
                    isOn: autoNameBranchBinding
                )

                if !appState.launchDraft.autoGenerateBranch {
                    Divider().opacity(0.45)
                    inlineTextField(
                        title: "Branch",
                        placeholder: "cursor/task-name",
                        systemName: "point.topleft.down.curvedto.point.bottomright.up",
                        text: branchNameBinding,
                        focus: .branchName
                    )
                    .padding(.top, 2)
                }
            }
        }
        .padding(14)
        .newChatGlassSurface(cornerRadius: 22)
    }

    private var launchBar: some View {
        VStack(spacing: 0) {
            Button {
                launch()
            } label: {
                HStack(spacing: 8) {
                    if appState.isLaunching {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.headline.weight(.bold))
                    }

                    Text(appState.isLaunching ? "Starting" : launchButtonTitle)
                        .font(.headline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(appState.canLaunchAgent ? Color(uiColor: .systemBlue) : Color(uiColor: .systemGray4))
                )
            }
            .buttonStyle(.plain)
            .disabled(!appState.canLaunchAgent || appState.isLaunching)
            .accessibilityIdentifier("newchat.launch")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private var promptEditor: some View {
        ZStack(alignment: .topLeading) {
            if appState.launchDraft.prompt.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(promptPlaceholder)
                    .foregroundStyle(.secondary)
                    .padding(.top, 14)
                    .padding(.leading, 16)
                    .allowsHitTesting(false)
            }

            TextEditor(text: promptTextBinding)
                .frame(minHeight: 170)
                .focused($focusedField, equals: .prompt)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .accessibilityIdentifier("newchat.prompt")
        }
    }

    private var promptStarterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PromptStarter.allCases) { starter in
                    Button {
                        applyPromptStarter(starter)
                    } label: {
                        Label(starter.title, systemImage: starter.symbolName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .newChatGlassSurface(cornerRadius: 15, interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var promptTextBinding: Binding<String> {
        Binding {
            appState.launchDraft.prompt.text
        } set: { value in
            appState.launchDraft.prompt.text = value
        }
    }

    private var cloudTaskHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            NewChatSectionHeader(title: "Task", systemName: "text.bubble")

            Spacer(minLength: 8)

            NewChatInlinePill(systemName: "cloud.fill", title: "Cloud Run")
        }
    }

    private var targetSectionTitle: String {
        appState.launchDraft.runtimeMode == .cloud ? "Workspace" : "Target"
    }

    private var outputSectionTitle: String {
        appState.launchDraft.runtimeMode == .cloud ? "Review" : "Output"
    }

    private var promptPlaceholder: String {
        switch appState.launchDraft.runtimeMode {
        case .cloud:
            "Describe the Cloud Agent task..."
        case .sdkBridge:
            "Ask Cursor to build, fix, review, or prepare a release..."
        }
    }

    @ViewBuilder
    private var sourceControls: some View {
        switch sourceMode {
        case .installed:
            if appState.repositories.isEmpty {
                ContentUnavailableView("No Repositories", systemImage: "folder.badge.questionmark")
                    .frame(maxWidth: .infinity)
            } else {
                Menu {
                    ForEach(appState.repositories) { repository in
                        Button {
                            selectRepository(repository)
                        } label: {
                            Label(repository.displayName, systemImage: selectedRepository?.url == repository.url ? "checkmark" : "folder")
                        }
                    }
                } label: {
                    NewChatSelectorLabel(
                        systemName: "folder",
                        title: selectedRepository?.displayName ?? "Select repository",
                        subtitle: selectedRepository
                            .flatMap { $0.defaultBranch.nilIfBlank.map { "Default branch \($0)" } }
                            ?? "Default branch from Cursor"
                    )
                }
                .menuIndicator(.hidden)
                .tint(.primary)
            }
        case .manual:
            inlineTextField(
                title: "Repository URL",
                placeholder: "https://github.com/owner/repository",
                systemName: "link",
                text: $manualRepositoryURL,
                focus: .manualURL,
                keyboardType: .URL
            )
            .onChange(of: manualRepositoryURL) { _, value in
                updateManualRepository(value)
            }
        case .pullRequest:
            inlineTextField(
                title: "Pull request",
                placeholder: "https://github.com/owner/repository/pull/123",
                systemName: "arrow.up.right.square",
                text: $pullRequestURL,
                focus: .pullRequestURL,
                keyboardType: .URL
            )
            .onChange(of: pullRequestURL) { _, value in
                updatePullRequest(value)
            }
        }
    }

    private var attachmentMenuButton: some View {
        Menu {
            if appState.capabilities.supportsImagesInPrompt {
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 5,
                    matching: .images
                ) {
                    Label("Photos", systemImage: "photo")
                }
                .onChange(of: selectedPhotoItems) { _, items in
                    Task {
                        await loadPromptImages(from: items)
                    }
                }
                .disabled(isLoadingPromptImages || appState.launchDraft.prompt.images.count >= 5)
            }

            Button {
                isPromptFileImporterPresented = true
            } label: {
                Label("Files", systemImage: "doc")
            }
            .disabled(isLoadingPromptFiles || appState.launchDraft.prompt.files.count >= PromptFileLoader.maxFiles)
        } label: {
            Label("Attach", systemImage: "paperclip")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(uiColor: .systemBlue))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .newChatGlassSurface(cornerRadius: 17, interactive: true)
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("Attach files or images")
    }

    private var shouldShowPromptAttachments: Bool {
        isLoadingPromptImages
            || isLoadingPromptFiles
            || !appState.launchDraft.prompt.images.isEmpty
            || !appState.launchDraft.prompt.files.isEmpty
            || promptFileImportMessage != nil
    }

    @ViewBuilder
    private var promptCountLabel: some View {
        let count = appState.launchDraft.prompt.text.count
        if count > 0 {
            Text("\(count) chars")
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .accessibilityLabel("\(count) characters")
        }
    }

    private var attachmentPreviewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if isLoadingPromptImages || isLoadingPromptFiles {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.horizontal, 10)
                }

                ForEach(appState.launchDraft.prompt.images) { image in
                    NewChatAttachmentPill(
                        systemName: "photo",
                        title: "\(image.width) x \(image.height)"
                    ) {
                        removePromptImage(image)
                    }
                }

                ForEach(appState.launchDraft.prompt.files) { file in
                    NewChatAttachmentPill(
                        systemName: "doc.text",
                        title: "\(file.filename) - \(file.sizeDescription)"
                    ) {
                        removePromptFile(file)
                    }
                }

                if let promptFileImportMessage {
                    NewChatInlinePill(systemName: "exclamationmark.triangle", title: promptFileImportMessage)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var modelMenu: some View {
        Menu {
            Button {
                modelSelectionBinding.wrappedValue = preferredModelID
            } label: {
                Label(
                    appState.launchDraft.runtimeMode.preferredLaunchModelTitle,
                    systemImage: modelSelectionBinding.wrappedValue == preferredModelID ? "checkmark" : "cpu"
                )
            }

            ForEach(NewChatModelPickerOptions.visibleModels(from: appState.models, excluding: preferredModelID)) { model in
                Button {
                    modelSelectionBinding.wrappedValue = model.id
                } label: {
                    Label(model.displayName, systemImage: modelSelectionBinding.wrappedValue == model.id ? "checkmark" : "cpu")
                }
            }
        } label: {
            NewChatInlinePill(systemName: "cpu", title: selectedModelTitle, trailingSystemName: "chevron.down")
        }
        .menuIndicator(.hidden)
        .tint(.secondary)
        .accessibilityLabel("Select model")
    }

    private var preferredModelID: String? {
        appState.launchDraft.runtimeMode.preferredLaunchModelID
    }

    private var selectedRepository: Repository? {
        if case .repository(let url, _) = appState.launchDraft.source,
           let repository = appState.repositories.first(where: { $0.url == url }) {
            return repository
        }
        return appState.selectedRepository ?? appState.repositories.first
    }

    private var selectedModelTitle: String {
        guard let selection = modelSelectionBinding.wrappedValue else { return appState.launchDraft.runtimeMode.preferredLaunchModelTitle }
        return appState.models.first(where: { $0.id == selection })?.displayName ?? selection
    }

    private var launchButtonTitle: String {
        switch appState.launchDraft.runtimeMode {
        case .cloud:
            "Start Cloud Run"
        case .sdkBridge:
            "Start Cursor Chat"
        }
    }

    private var navigationTitle: String {
        switch runtimeMode {
        case .cloud:
            "New Cloud Run"
        case .sdkBridge:
            "New Cursor Chat"
        case nil:
            "New Chat"
        }
    }

    private var runtimeModeBinding: Binding<AgentRuntimeMode> {
        Binding {
            appState.launchDraft.runtimeMode
        } set: { mode in
            applyRuntimeMode(mode)
        }
    }

    private func inlineTextField(
        title: String,
        placeholder: String,
        systemName: String,
        text: Binding<String>,
        focus: Field,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField(placeholder, text: text)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: focus)
            }
        }
        .padding(12)
        .newChatGlassSurface(cornerRadius: 16, interactive: true)
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

    private var modelSelectionBinding: Binding<String?> {
        Binding {
            NewChatModelPickerOptions.selection(
                from: appState.launchDraft.modelID,
                runtimeMode: appState.launchDraft.runtimeMode
            )
        } set: { modelID in
            let resolvedModelID = NewChatModelPickerOptions.modelID(
                from: modelID,
                runtimeMode: appState.launchDraft.runtimeMode
            )
            appState.launchDraft.modelID = resolvedModelID
            if appState.launchDraft.runtimeMode == .sdkBridge {
                CursorChatModelPreference.saveSelectedModelID(resolvedModelID)
            }
        }
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
        case .general:
            sourceMode = .installed
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

    private func applyLockedRuntimeMode() {
        guard let runtimeMode else { return }
        applyRuntimeMode(runtimeMode)
    }

    private func applyRuntimeMode(_ mode: AgentRuntimeMode) {
        appState.launchDraft.applyRuntimeMode(mode)
        if mode == .sdkBridge {
            appState.launchDraft.modelID = CursorChatModelPreference.selectedModelID()
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
        applyLockedRuntimeMode()
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

    private func applyPromptStarter(_ starter: PromptStarter) {
        let current = appState.launchDraft.prompt.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty {
            appState.launchDraft.prompt.text = starter.prompt
        } else {
            appState.launchDraft.prompt.text = current + "\n\n" + starter.prompt
        }
        focusedField = .prompt
    }
}

private struct NewChatSectionHeader: View {
    var title: String
    var systemName: String

    var body: some View {
        Label(title, systemImage: systemName)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct NewChatSelectorLabel: View {
    var systemName: String
    var title: String
    var subtitle: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(uiColor: .systemBlue))
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .newChatGlassSurface(cornerRadius: 16, interactive: true)
        .accessibilityElement(children: .combine)
    }
}

private struct NewChatOutputToggleRow: View {
    var title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
        .toggleStyle(.switch)
        .font(.body)
        .frame(minHeight: 40)
        .padding(.vertical, 3)
        .accessibilityLabel(title)
    }
}

private struct NewChatInlinePill: View {
    var systemName: String
    var title: String
    var trailingSystemName: String?

    init(systemName: String, title: String, trailingSystemName: String? = nil) {
        self.systemName = systemName
        self.title = title
        self.trailingSystemName = trailingSystemName
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.caption.weight(.semibold))

            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            if let trailingSystemName {
                Image(systemName: trailingSystemName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .newChatGlassSurface(cornerRadius: 17)
        .accessibilityElement(children: .combine)
    }
}

private struct NewChatAttachmentPill: View {
    var systemName: String
    var title: String
    var remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.caption)
                .lineLimit(1)

            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .newChatGlassSurface(cornerRadius: 17)
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    @ViewBuilder
    func newChatGlassSurface(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            if interactive {
                self
                    .glassEffect(.regular.interactive(), in: shape)
                    .overlay(shape.stroke(Color(uiColor: .separator).opacity(0.22), lineWidth: 0.5))
            } else {
                self
                    .glassEffect(.regular, in: shape)
                    .overlay(shape.stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 0.5))
            }
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color(uiColor: .separator).opacity(0.22), lineWidth: 0.5))
        }
    }
}

private enum PromptStarter: String, CaseIterable, Identifiable {
    case build
    case fix
    case review
    case release

    var id: String { rawValue }

    var title: String {
        switch self {
        case .build:
            "Build"
        case .fix:
            "Fix"
        case .review:
            "Review"
        case .release:
            "Release"
        }
    }

    var symbolName: String {
        switch self {
        case .build:
            "hammer"
        case .fix:
            "wrench.adjustable"
        case .review:
            "doc.text.magnifyingglass"
        case .release:
            "checklist.checked"
        }
    }

    var prompt: String {
        switch self {
        case .build:
            "Build this feature end to end. Keep the change focused, follow the existing architecture, and include tests or validation notes."
        case .fix:
            "Find and fix the bug. Explain the root cause, keep the patch minimal, and verify the behavior before finishing."
        case .review:
            "Review the current implementation for bugs, UX regressions, missing tests, and release risks. List findings first."
        case .release:
            "Run a release-readiness pass. Check tests, build health, documentation, public copy, and App Store readiness blockers."
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
