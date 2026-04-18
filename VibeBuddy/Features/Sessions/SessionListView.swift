import SwiftUI

/// Two-pane (list + placeholder detail) container that lives inside the
/// ModuleHost for the Sessions route. The real transcript view replaces the
/// placeholder in P0-6.
struct SessionListDetailView: View {
    @ObservedObject var store: SessionStore
    @EnvironmentObject private var navigator: Navigator
    @State private var selectedID: SessionSummary.ID?
    @State private var searchText: String = ""
    @State private var hideFinished: Bool = false
    @State private var now: Date = Date()

    /// Ticks once a minute so the live-dot decays even when no FS events
    /// fire (a session that goes idle for >5 min stops showing as live).
    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        HSplitView {
            SessionListView(
                summaries: filteredSummaries,
                selected: $selectedID,
                searchText: $searchText,
                hideFinished: $hideFinished,
                liveCount: store.summaries.filter { $0.isLive(now: now) }.count,
                now: now,
                isLoading: store.isLoading,
                error: store.loadError,
                onRefresh: { Task { await store.reload() } }
            )
            .frame(minWidth: 280, idealWidth: 340)

            Group {
                if let summary = selectedSummary {
                    SessionDetailView(summary: summary)
                        .id(summary.id)   // fresh state per session switch
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
        .onReceive(ticker) { now = $0 }
    }

    private func consumePendingOpen() {
        guard let id = navigator.pendingSessionID else { return }
        selectedID = id
        navigator.pendingSessionID = nil
    }

    private var filteredSummaries: [SessionSummary] {
        var result = store.summaries
        if hideFinished {
            result = result.filter { $0.isLive(now: now) }
        }
        guard !searchText.isEmpty else { return result }
        let q = searchText.lowercased()
        return result.filter { s in
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
    @Binding var hideFinished: Bool
    let liveCount: Int
    let now: Date
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

            filterBar

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
                    Section(header: ProjectHeader(path: group.key, liveCount: group.value.filter { $0.isLive(now: now) }.count)) {
                        ForEach(group.value) { summary in
                            SessionRow(summary: summary, now: now)
                                .tag(summary.id as SessionSummary.ID?)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if summaries.isEmpty, !isLoading {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text(emptyDescription)
                    )
                } else if isLoading, summaries.isEmpty {
                    ProgressView()
                }
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            if liveCount > 0 {
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("\(liveCount) live")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle(isOn: $hideFinished) {
                Label("Hide finished", systemImage: "eye.slash")
                    .font(.caption)
                    .labelStyle(.titleAndIcon)
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Hide sessions that haven't been updated in the last 5 minutes")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var emptyTitle: String {
        if !searchText.isEmpty { return "No matching sessions" }
        if hideFinished { return "No live sessions" }
        return "No sessions"
    }

    private var emptyDescription: String {
        if !searchText.isEmpty { return "Try a different query." }
        if hideFinished { return "Every visible session has been idle for 5+ minutes. Toggle Hide finished off to see them." }
        return "Run Claude Code in any project to start recording sessions here."
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
    let liveCount: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
            Text(displayName)
                .font(.caption.bold())
            if liveCount > 0 {
                Circle().fill(.green).frame(width: 5, height: 5)
            }
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
    let now: Date

    private var isLive: Bool { summary.isLive(now: now) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Liveness indicator reserves a column so text aligns whether or
            // not the dot is visible.
            Circle()
                .fill(isLive ? Color.green : Color.clear)
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.firstPrompt ?? "(no prompt)")
                    .font(.body)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if isLive {
                        Text("live")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                        Text("·")
                    }
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
        }
        .padding(.vertical, 2)
    }
}

