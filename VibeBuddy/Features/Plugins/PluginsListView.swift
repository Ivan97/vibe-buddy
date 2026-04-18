import SwiftUI

struct PluginsListView: View {
    let plugins: [InstalledPlugin]
    @Binding var selected: InstalledPlugin.ID?
    @Binding var searchText: String
    let totalCount: Int
    let enabledCount: Int
    let isLoading: Bool
    let isCheckingUpdates: Bool
    let updateStatus: (String) -> GitUpdateChecker.Status
    let autoUpdate: (String) -> Bool
    let onRefresh: () -> Void
    let onCheckUpdates: () -> Void
    let onToggleMarketplaceAutoUpdate: (_ marketplace: String, _ enabled: Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()

            List(selection: $selected) {
                ForEach(grouped, id: \.marketplace) { group in
                    Section(header: header(for: group)) {
                        ForEach(group.plugins) { plugin in
                            PluginRow(plugin: plugin, status: updateStatus(plugin.id))
                                .tag(plugin.id as InstalledPlugin.ID?)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if plugins.isEmpty, !isLoading {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No plugins" : "No matches",
                        systemImage: "puzzlepiece.extension",
                        description: Text(searchText.isEmpty
                            ? "Install a plugin via Claude Code to see it here."
                            : "Try a different query.")
                    )
                } else if isLoading, plugins.isEmpty {
                    ProgressView()
                }
            }

            Divider()
            footerBar
        }
    }

    // MARK: - helpers

    private struct MarketplaceGroup {
        let marketplace: String
        let plugins: [InstalledPlugin]
    }

    private var grouped: [MarketplaceGroup] {
        let buckets = Dictionary(grouping: plugins, by: \.marketplaceName)
        return buckets
            .map { MarketplaceGroup(marketplace: $0.key, plugins: $0.value) }
            .sorted {
                $0.marketplace.localizedCaseInsensitiveCompare($1.marketplace) == .orderedAscending
            }
    }

    private func header(for group: MarketplaceGroup) -> some View {
        MarketplaceHeader(
            name: group.marketplace,
            count: group.plugins.count,
            autoUpdate: autoUpdate(group.marketplace),
            onToggleAutoUpdate: { onToggleMarketplaceAutoUpdate(group.marketplace, $0) }
        )
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search plugins", text: $searchText)
                .textFieldStyle(.plain)
            Button(action: onCheckUpdates) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .symbolEffect(.pulse, options: .repeating, isActive: isCheckingUpdates)
            }
            .buttonStyle(.borderless)
            .disabled(isCheckingUpdates || plugins.isEmpty)
            .help("Check installed plugins for upstream updates")
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .symbolEffect(.pulse, options: .repeating, isActive: isLoading)
            }
            .buttonStyle(.borderless)
            .disabled(isLoading)
            .help("Re-scan plugins/")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footerBar: some View {
        HStack {
            Text("\(enabledCount) enabled / \(totalCount) installed")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct PluginRow: View {
    let plugin: InstalledPlugin
    let status: GitUpdateChecker.Status

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if plugin.isEnabled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption2)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.tertiary)
                        .font(.caption2)
                }
                Text(plugin.pluginName)
                    .font(.body)
                    .lineLimit(1)
                if let version = plugin.manifest.version {
                    Text("v\(version)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
                UpdateStatusBadge(status: status)
            }

            if let description = plugin.manifest.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    // Without this, List squeezes the 2nd line and pushes
                    // the contribution chips out of the row's visible
                    // area — see the plugin-list-clip regression.
                    .fixedSize(horizontal: false, vertical: true)
            }

            ContributionSummary(contributions: plugin.contributions)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ContributionSummary: View {
    let contributions: PluginContributions

    var body: some View {
        HStack(spacing: 8) {
            if contributions.skillCount > 0 {
                badge("\(contributions.skillCount)", "wand.and.stars")
            }
            if contributions.commandCount > 0 {
                badge("\(contributions.commandCount)", "text.quote")
            }
            if contributions.agentCount > 0 {
                badge("\(contributions.agentCount)", "person.2")
            }
            if contributions.total == 0 {
                Text("no contributions discovered")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
    }

    private func badge(_ text: String, _ icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption2.monospacedDigit())
        }
        .foregroundStyle(.secondary)
    }
}

/// Marketplace section header with an inline auto-update toggle. The
/// Toggle itself is intercepted via a custom Binding so a click triggers
/// the DiffPreviewSheet flow rather than writing straight through — every
/// config mutation in the app confirms before hitting disk.
private struct MarketplaceHeader: View {
    let name: String
    let count: Int
    let autoUpdate: Bool
    let onToggleAutoUpdate: (Bool) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "shippingbox")
            Text(name)
                .font(.caption.bold())
            Spacer()
            Toggle(isOn: Binding(
                get: { autoUpdate },
                set: { newValue in onToggleAutoUpdate(newValue) }
            )) {
                Text("auto-update")
                    .font(.caption2)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("When on, Claude Code pulls the latest version of every plugin from this marketplace on launch.")
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// Compact update-status pill rendered next to the plugin name (and, in
/// the Skills module, next to skill names). Uses SF Symbol animation for
/// the checking state so the list feels responsive during a bulk scan.
struct UpdateStatusBadge: View {
    let status: GitUpdateChecker.Status

    var body: some View {
        switch status {
        case .unchecked, .notTracked:
            EmptyView()
        case .checking:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, options: .repeating)
        case .upToDate:
            Image(systemName: "checkmark.seal.fill")
                .font(.caption2)
                .foregroundStyle(.green)
                .help("Up to date")
        case .updateAvailable:
            HStack(spacing: 2) {
                Image(systemName: "arrow.up.circle.fill")
                Text("update")
            }
            .font(.caption2.bold())
            .foregroundStyle(.orange)
        case .error(let reason):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
                .help(reason)
        }
    }
}
