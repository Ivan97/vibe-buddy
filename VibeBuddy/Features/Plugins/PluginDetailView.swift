import SwiftUI

struct PluginDetailView: View {
    let plugin: InstalledPlugin
    let onToggle: (Bool) -> Void
    @EnvironmentObject private var navigator: Navigator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()
                contributionsSection
                if !plugin.manifest.keywords.isEmpty {
                    keywordsSection
                }
                Divider()
                metadataSection
                if !plugin.manifest.extras.isEmpty {
                    Divider()
                    extrasSection
                }
                Spacer(minLength: 12)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(plugin.pluginName)
                        .font(.largeTitle.bold())
                    HStack(spacing: 6) {
                        Text(plugin.marketplaceName)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if let version = plugin.manifest.version {
                            Text("·").foregroundStyle(.tertiary)
                            Text("v\(version)")
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Toggle("Enabled", isOn: Binding(
                    get: { plugin.isEnabled },
                    set: { onToggle($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.large)
            }

            if let description = plugin.manifest.description, !description.isEmpty {
                Text(description)
                    .font(.body)
                    .foregroundStyle(.primary)
            }

            HStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([plugin.manifestURL])
                } label: {
                    Label("Reveal bundle in Finder", systemImage: "folder")
                }
                .buttonStyle(.borderless)

                if let repository = plugin.manifest.repository,
                   let url = URL(string: repository) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Repository", systemImage: "arrow.up.forward.square")
                    }
                    .buttonStyle(.borderless)
                }

                if let homepage = plugin.manifest.homepage,
                   let url = URL(string: homepage) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Homepage", systemImage: "globe")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .font(.caption)
        }
    }

    private var contributionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Contributions").font(.headline)

            if plugin.contributions.total == 0 {
                Text("This plugin doesn't ship any discoverable skills / commands / agents under its bundle directories.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                if !plugin.contributions.skills.isEmpty {
                    ContributionGroup(
                        title: "Skills",
                        icon: "wand.and.stars",
                        items: plugin.contributions.skills,
                        prefix: "",
                        jumpHint: "Skills module"
                    ) { resource in
                        navigator.openSkill(id: resource.id)
                    }
                }
                if !plugin.contributions.commands.isEmpty {
                    ContributionGroup(
                        title: "Commands",
                        icon: "text.quote",
                        items: plugin.contributions.commands,
                        prefix: "/",
                        jumpHint: "Prompts module"
                    ) { resource in
                        navigator.openCommand(id: resource.id)
                    }
                }
                if !plugin.contributions.agents.isEmpty {
                    ContributionGroup(
                        title: "Agents",
                        icon: "person.2",
                        items: plugin.contributions.agents,
                        prefix: "",
                        jumpHint: "Subagents module"
                    ) { resource in
                        navigator.openAgent(id: resource.id)
                    }
                }
                if !plugin.contributions.mcpServers.isEmpty {
                    ContributionGroup(
                        title: "MCP servers",
                        icon: "bolt.horizontal",
                        items: plugin.contributions.mcpServers,
                        prefix: "",
                        jumpHint: "MCP module"
                    ) { resource in
                        navigator.openMCPServer(name: resource.name)
                    }
                }
            }
        }
    }

    private var keywordsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Keywords").font(.headline)
            FlowLayout(spacing: 6) {
                ForEach(plugin.manifest.keywords, id: \.self) { keyword in
                    Text(keyword)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.secondary.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metadata").font(.headline)
            metadataRow("Identifier", plugin.id, monospaced: true)
            if let author = plugin.manifest.author {
                metadataRow("Author", author)
            }
            if let license = plugin.manifest.license {
                metadataRow("License", license)
            }
            metadataRow(
                "Bundle",
                plugin.bundleRoot.path(percentEncoded: false),
                monospaced: true
            )
        }
    }

    private var extrasSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Additional manifest fields").font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(plugin.manifest.extras.sorted(by: { $0.key < $1.key }), id: \.key) { pair in
                    HStack(alignment: .top, spacing: 4) {
                        Text(pair.key + ":")
                            .font(.caption.monospaced().bold())
                        Text(pair.value)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }
        }
    }

    private func metadataRow(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer()
        }
    }
}

/// Collapsible list of a plugin's contributed resources. Each item is
/// clickable and calls the supplied action (typically
/// `navigator.openSkill/openCommand`).
private struct ContributionGroup: View {
    let title: String
    let icon: String
    let items: [PluginContributions.Resource]
    let prefix: String
    let jumpHint: String
    let onOpen: (PluginContributions.Resource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Text("\(title) · \(items.count)")
                    .font(.subheadline.bold())
                Spacer()
                Text(jumpHint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(items) { item in
                    ContributionItemRow(
                        title: prefix + item.name,
                        onOpen: { onOpen(item) }
                    )
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.06))
            )
        }
    }
}

private struct ContributionItemRow: View {
    let title: String
    let onOpen: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.callout.monospaced())
                    .foregroundStyle(.primary)
                Spacer()
                if hovered {
                    Image(systemName: "arrow.up.forward.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hovered ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - flow layout helper

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
