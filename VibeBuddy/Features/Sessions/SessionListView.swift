import SwiftUI

/// Two-pane (list + placeholder detail) container that lives inside the
/// ModuleHost for the Sessions route. The real transcript view replaces the
/// placeholder in P0-6.
struct SessionListDetailView: View {
    @ObservedObject var store: SessionStore
    @EnvironmentObject private var navigator: Navigator
    @State private var selectedID: SessionSummary.ID?
    @State private var searchText: String = ""

    var body: some View {
        HSplitView {
            SessionListView(
                summaries: filteredSummaries,
                selected: $selectedID,
                searchText: $searchText,
                isLoading: store.isLoading,
                error: store.loadError,
                onRefresh: { Task { await store.reload() } }
            )
            .frame(minWidth: 280, idealWidth: 340)

            Group {
                if let summary = selectedSummary {
                    SessionDetailView(summary: summary)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                        Text("Select a session")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 400)
        }
        .onAppear(perform: consumePendingOpen)
        .onChange(of: navigator.pendingSessionID) { _, _ in consumePendingOpen() }
    }

    private func consumePendingOpen() {
        guard let id = navigator.pendingSessionID else { return }
        selectedID = id
        navigator.pendingSessionID = nil
    }

    private var filteredSummaries: [SessionSummary] {
        guard !searchText.isEmpty else { return store.summaries }
        let q = searchText.lowercased()
        return store.summaries.filter { s in
            (s.firstPrompt?.lowercased().contains(q) ?? false)
                || s.projectPath.lowercased().contains(q)
                || s.id.lowercased().contains(q)
        }
    }

    private var selectedSummary: SessionSummary? {
        guard let id = selectedID else { return nil }
        return store.summaries.first { $0.id == id }
    }
}

private struct SessionListView: View {
    let summaries: [SessionSummary]
    @Binding var selected: SessionSummary.ID?
    @Binding var searchText: String
    let isLoading: Bool
    let error: String?
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search sessions", text: $searchText)
                    .textFieldStyle(.plain)
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .symbolEffect(.pulse, options: .repeating, isActive: isLoading)
                }
                .buttonStyle(.borderless)
                .disabled(isLoading)
                .help("Refresh session list")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            List(selection: $selected) {
                ForEach(groupedByProject, id: \.key) { group in
                    Section(header: ProjectHeader(path: group.key)) {
                        ForEach(group.value) { summary in
                            SessionRow(summary: summary)
                                .tag(summary.id as SessionSummary.ID?)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if summaries.isEmpty, !isLoading {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No sessions" : "No matching sessions",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text(searchText.isEmpty
                            ? "Run Claude Code in any project to start recording sessions here."
                            : "Try a different query.")
                    )
                } else if isLoading, summaries.isEmpty {
                    ProgressView()
                }
            }
        }
    }

    /// Sessions grouped by projectPath, ordered by each group's most recent
    /// activity. Stable across refreshes because we sort by a concrete Date.
    private var groupedByProject: [(key: String, value: [SessionSummary])] {
        Dictionary(grouping: summaries, by: \.projectPath)
            .map { (key: $0.key, value: $0.value.sorted { $0.lastActivity > $1.lastActivity }) }
            .sorted {
                ($0.value.first?.lastActivity ?? .distantPast)
                    > ($1.value.first?.lastActivity ?? .distantPast)
            }
    }
}

private struct ProjectHeader: View {
    let path: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
            Text(displayName)
                .font(.caption.bold())
            Spacer()
        }
        .help(path)
    }

    private var displayName: String {
        let last = URL(fileURLWithPath: path).lastPathComponent
        return last.isEmpty ? path : last
    }
}

private struct SessionRow: View {
    let summary: SessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary.firstPrompt ?? "(no prompt)")
                .font(.body)
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(summary.lastActivity, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                Text("·")
                Text("\(summary.messageCount) msgs")
                if let branch = summary.gitBranch, !branch.isEmpty, branch != "HEAD" {
                    Text("·")
                    Label(branch, systemImage: "arrow.triangle.branch")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

