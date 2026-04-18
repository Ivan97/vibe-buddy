import SwiftUI

struct PluginDetailView: View {
    let plugin: InstalledPlugin
    let onToggle: (Bool) -> Void

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
        VStack(alignment: .leading, spacing: 10) {
            Text("Contributions").font(.headline)
            HStack(spacing: 14) {
                ContributionChip(
                    icon: "wand.and.stars",
                    count: plugin.contributions.skillCount,
                    label: "skills"
                )
                ContributionChip(
                    icon: "text.quote",
                    count: plugin.contributions.commandCount,
                    label: "commands"
                )
                ContributionChip(
                    icon: "person.2",
                    count: plugin.contributions.agentCount,
                    label: "agents"
                )
            }
            if plugin.contributions.total == 0 {
                Text("This plugin doesn't ship any discoverable skills / commands / agents under its bundle directories.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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

private struct ContributionChip: View {
    let icon: String
    let count: Int
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(count > 0 ? .primary : .tertiary)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(count)")
                    .font(.title3.monospacedDigit().bold())
                    .foregroundStyle(count > 0 ? .primary : .tertiary)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(count > 0 ? Color.secondary.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator)
        )
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
