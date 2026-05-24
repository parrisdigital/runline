import SwiftUI

struct RepositoriesView: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""
    @State private var isNewChatPresented = false

    var body: some View {
        NavigationStack {
            RepositoryListContent(query: $query, presentation: .plain, select: select)
                .navigationTitle("Repositories")
                .searchable(text: $query, prompt: "Search repositories")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task {
                                await appState.reloadWorkspace()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh")
                    }
                }
                .sheet(isPresented: $isNewChatPresented) {
                    NewChatSheet(runtimeMode: .cloud)
                }
        }
    }

    private func select(_ repository: Repository) {
        appState.launchDraft.applyRuntimeMode(.cloud)
        appState.launchDraft.source = .repository(
            url: repository.url,
            startingRef: repository.defaultBranch.nilIfBlank
        )
        isNewChatPresented = true
    }
}

struct RepositoryListContent: View {
    enum Presentation {
        case plain
        case selection(Binding<URL?>)
    }

    @Environment(AppState.self) private var appState
    @Binding var query: String
    var presentation: Presentation
    var select: (Repository) -> Void

    var body: some View {
        switch presentation {
        case .plain:
            List {
                listContent
            }
            .refreshable {
                await appState.reloadWorkspace()
            }
        case .selection(let selectedRepositoryURL):
            List(selection: selectedRepositoryURL) {
                listContent
            }
            .refreshable {
                await appState.reloadWorkspace()
            }
        }
    }

    private var filteredRepositories: [Repository] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return appState.repositories }
        return appState.repositories.filter { repository in
            repository.displayName.localizedCaseInsensitiveContains(trimmed)
                || repository.defaultBranch.localizedCaseInsensitiveContains(trimmed)
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if filteredRepositories.isEmpty {
            ContentUnavailableView(
                query.isEmpty ? "No Repositories" : "No Matches",
                systemImage: query.isEmpty ? "folder.badge.questionmark" : "magnifyingglass",
                description: Text(query.isEmpty ? "Refresh after Cursor finishes loading connected repositories." : "Try a different owner or repository name.")
            )
        } else {
            Section {
                ForEach(filteredRepositories) { repository in
                    repositoryRow(repository)
                }
            }
        }
    }

    @ViewBuilder
    private func repositoryRow(_ repository: Repository) -> some View {
        switch presentation {
        case .plain:
            Button {
                select(repository)
            } label: {
                RepositoryListRow(
                    repository: repository,
                    isSelected: appState.selectedRepository?.id == repository.id
                )
            }
            .buttonStyle(.plain)
        case .selection(let selectedRepositoryURL):
            Button {
                selectedRepositoryURL.wrappedValue = repository.url
                select(repository)
            } label: {
                RepositoryListRow(
                    repository: repository,
                    isSelected: selectedRepositoryURL.wrappedValue == repository.url
                )
            }
            .buttonStyle(.plain)
            .tag(repository.url)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
