import SwiftUI

struct CommandListView: View {
    let handles: [CommandHandle]
    @Binding var selected: CommandHandle.ID?
    @Binding var searchText: String
    let totalCount: Int
    let isLoading: Bool
    let error: String?
    let onNewCommand: () -> Void
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
                        searchText.isEmpty ? "No commands" : "No matches",
                        systemImage: "text.quote",
                        description: Text(searchText.isEmpty
                            ? "Click New Command to create your first slash command under ~/.claude/commands/."
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
        let items = handles.filter { $0.section == .user }
        if !items.isEmpty {
            Section {
                ForEach(items) { handle in
                    CommandRow(handle: handle)
                        .tag(handle.id as CommandHandle.ID?)
                }
            } header: {
                SectionHeader(icon: "person.circle", title: "User", count: items.count)
            }
        }
    }

    @ViewBuilder
    private var pluginSection: some View {
        let items = handles.filter { $0.section == .plugin }
        if !items.isEmpty {
            Section {
                ForEach(pluginGroups(for: items), id: \.plugin) { group in
                    DisclosureGroup {
                        ForEach(group.commands) { handle in
                            CommandRow(handle: handle)
                                .tag(handle.id as CommandHandle.ID?)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "puzzlepiece.extension")
                                .foregroundStyle(.secondary)
                            Text(group.plugin)
                                .font(.caption.bold())
                            Spacer()
                            Text("\(group.commands.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } header: {
                SectionHeader(icon: "puzzlepiece.extension", title: "Plugin-provided", count: items.count)
            }
        }
    }

    private struct PluginGroup {
        let plugin: String
        let commands: [CommandHandle]
    }

    private func pluginGroups(for items: [CommandHandle]) -> [PluginGroup] {
        let grouped = Dictionary(grouping: items) { handle -> String in
            if case .plugin(_, let plugin) = handle.scope { return plugin }
            return "unknown"
        }
        return grouped
            .map { PluginGroup(plugin: $0.key, commands: $0.value) }
            .sorted { $0.plugin.localizedCaseInsensitiveCompare($1.plugin) == .orderedAscending }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search commands", text: $searchText)
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
            Button(action: onNewCommand) {
                Label("New Command", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            Spacer()
            Text("\(handles.count)\(searchText.isEmpty ? "" : " / \(totalCount)") total")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct SectionHeader: View {
    let icon: String
    let title: String
    let count: Int
    var body: some View {
        HStack {
            Image(systemName: icon)
            Text(title).font(.caption.bold())
            Spacer()
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct CommandRow: View {
    let handle: CommandHandle
    @EnvironmentObject private var navigator: Navigator

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("/" + handle.invocationSlug)
                    .font(.body.monospaced())
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
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            if let pluginID = handle.pluginID {
                Button("Show plugin") {
                    navigator.openPlugin(id: pluginID)
                }
            }
        }
    }
}
