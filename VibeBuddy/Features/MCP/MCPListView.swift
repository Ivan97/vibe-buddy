import SwiftUI

struct MCPListView: View {
    let servers: [MCPServer]
    @Binding var selectedName: String?
    let onNew: () -> Void
    let onDelete: () -> Void

    private var selectedIsEditable: Bool {
        guard let name = selectedName,
              let server = servers.first(where: { $0.name == name }) else { return false }
        return server.isEditable
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedName) {
                userSection
                pluginSection
            }
            .listStyle(.sidebar)

            Divider()
            HStack {
                Button(action: onNew) {
                    Label("New Server", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(!selectedIsEditable)
                .help(selectedIsEditable
                    ? "Remove selected server"
                    : "Plugin-provided servers are read-only")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var userSection: some View {
        let items = servers.filter { $0.isEditable }
        if !items.isEmpty {
            Section {
                ForEach(items) { server in
                    ServerRow(server: server).tag(server.name as String?)
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
        let items = servers.filter { !$0.isEditable }
        if !items.isEmpty {
            Section {
                ForEach(pluginGroups(for: items), id: \.plugin) { group in
                    DisclosureGroup {
                        ForEach(group.servers) { server in
                            ServerRow(server: server).tag(server.name as String?)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "puzzlepiece.extension")
                                .foregroundStyle(.secondary)
                            Text(group.plugin)
                                .font(.caption.bold())
                            Spacer()
                            Text("\(group.servers.count)")
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
        let servers: [MCPServer]
    }

    private func pluginGroups(for items: [MCPServer]) -> [PluginGroup] {
        let grouped = Dictionary(grouping: items) { server -> String in
            if case .plugin(_, let plugin) = server.scope { return plugin }
            return "unknown"
        }
        return grouped
            .map { PluginGroup(plugin: $0.key, servers: $0.value) }
            .sorted { $0.plugin.localizedCaseInsensitiveCompare($1.plugin) == .orderedAscending }
    }
}

private struct ServerRow: View {
    let server: MCPServer
    @EnvironmentObject private var navigator: Navigator

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: server.transport.icon)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(server.name)
                        .font(.body)
                        .lineLimit(1)
                    if !server.isEditable {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.tertiary)
                            .font(.caption2)
                    }
                }
                Text(server.transport.label)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .contextMenu {
            if let pluginID = server.pluginID {
                Button("Show plugin") {
                    navigator.openPlugin(id: pluginID)
                }
            }
        }
    }
}
