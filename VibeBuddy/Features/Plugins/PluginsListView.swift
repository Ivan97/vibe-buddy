import SwiftUI

struct PluginsListView: View {
    let plugins: [InstalledPlugin]
    @Binding var selected: InstalledPlugin.ID?
    @Binding var searchText: String
    let totalCount: Int
    let enabledCount: Int
    let isLoading: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()

            List(selection: $selected) {
                ForEach(grouped, id: \.marketplace) { group in
                    Section(header: header(for: group)) {
                        ForEach(group.plugins) { plugin in
                            PluginRow(plugin: plugin)
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
        HStack {
            Image(systemName: "shippingbox")
            Text(group.marketplace)
                .font(.caption.bold())
            Spacer()
            Text("\(group.plugins.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search plugins", text: $searchText)
                .textFieldStyle(.plain)
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
            }

            if let description = plugin.manifest.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            ContributionSummary(contributions: plugin.contributions)
        }
        .padding(.vertical, 2)
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
