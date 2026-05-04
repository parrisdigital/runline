import SwiftUI

struct RepositoriesView: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""
    @State private var isNewChatPresented = false

    var body: some View {
        NavigationStack {
            List {
                if filteredRepositories.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty ? "No Repositories" : "No Matches",
                        systemImage: query.isEmpty ? "folder.badge.questionmark" : "magnifyingglass",
                        description: Text(query.isEmpty ? "Refresh after Cursor finishes loading connected repositories." : "Try a different owner or repository name.")
                    )
                } else {
                    Section {
                        ForEach(filteredRepositories) { repository in
                            Button {
                                select(repository)
                            } label: {
                                RepositoryListRow(
                                    repository: repository,
                                    isSelected: appState.selectedRepository?.id == repository.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Repositories")
            .searchable(text: $query, prompt: "Search repositories")
            .refreshable {
                await appState.reloadWorkspace()
            }
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
                NewChatSheet()
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

    private func select(_ repository: Repository) {
        appState.launchDraft.source = .repository(
            url: repository.url,
            startingRef: repository.defaultBranch.nilIfBlank
        )
        isNewChatPresented = true
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
