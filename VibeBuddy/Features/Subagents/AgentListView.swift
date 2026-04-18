import SwiftUI

struct AgentListView: View {
    let handles: [AgentHandle]
    @Binding var selected: AgentHandle.ID?
    @Binding var searchText: String
    let totalCount: Int
    let isLoading: Bool
    let error: String?
    let onNewAgent: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            List(selection: $selected) {
                userSection
                pluginSection
            }
            .listStyle(.sidebar)
            .overlay {
                if handles.isEmpty, !isLoading {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No agents" : "No matches",
                        systemImage: "person.2",
                        description: Text(searchText.isEmpty
                            ? "Click New Agent to create your first one."
                            : "Try a different query.")
                    )
                } else if isLoading, handles.isEmpty {
                    ProgressView()
                }
            }

            Divider()
            footerBar
        }
    }

    @ViewBuilder
    private var userSection: some View {
        let items = handles.filter {
            if case .user = $0.scope { return true }
            return false
        }
        if !items.isEmpty {
            Section {
                ForEach(items) { handle in
                    AgentRow(handle: handle)
                        .tag(handle.id as AgentHandle.ID?)
                }
            } header: {
                HStack {
                    Image(systemName: "person.circle")
                    Text("User").font(.caption.bold())
                    Spacer()
                    Text("\(items.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var pluginSection: some View {
        let items = handles.filter {
            if case .plugin = $0.scope { return true }
            return false
        }
        if !items.isEmpty {
            Section {
                ForEach(pluginGroups(for: items), id: \.plugin) { group in
                    DisclosureGroup {
                        ForEach(group.agents) { handle in
                            AgentRow(handle: handle)
                                .tag(handle.id as AgentHandle.ID?)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "puzzlepiece.extension")
                                .foregroundStyle(.secondary)
                            Text(group.plugin)
                                .font(.caption.bold())
                            Spacer()
                            Text("\(group.agents.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } header: {
                HStack {
                    Image(systemName: "puzzlepiece.extension")
                    Text("Plugin-provided").font(.caption.bold())
                    Spacer()
                    Text("\(items.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private struct PluginGroup {
        let plugin: String
        let agents: [AgentHandle]
    }

    private func pluginGroups(for items: [AgentHandle]) -> [PluginGroup] {
        let grouped = Dictionary(grouping: items) { handle -> String in
            if case .plugin(_, let plugin) = handle.scope { return plugin }
            return "unknown"
        }
        return grouped
            .map { PluginGroup(plugin: $0.key, agents: $0.value) }
            .sorted { $0.plugin.localizedCaseInsensitiveCompare($1.plugin) == .orderedAscending }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search agents", text: $searchText)
                .textFieldStyle(.plain)
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .symbolEffect(.pulse, options: .repeating, isActive: isLoading)
            }
            .buttonStyle(.borderless)
            .disabled(isLoading)
            .help("Refresh from disk")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footerBar: some View {
        HStack {
            Button(action: onNewAgent) {
                Label("New Agent", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct AgentRow: View {
    let handle: AgentHandle
    @EnvironmentObject private var navigator: Navigator

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(handle.name)
                    .font(.body)
                    .lineLimit(1)
                if case .plugin = handle.scope {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.tertiary)
                        .font(.caption2)
                }
            }
            if !handle.description.isEmpty {
                Text(handle.description)
                    .font(.caption)
                    .foregroundStyle(handle.isEditable ? .secondary : .tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if let pluginID = handle.pluginID {
                Button("Show plugin") {
                    navigator.openPlugin(id: pluginID)
                }
            }
        }
    }
}
