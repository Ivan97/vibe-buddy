import SwiftUI

struct PluginDetailView: View {
    let plugin: InstalledPlugin
    let status: GitUpdateChecker.Status
    let isUpdating: Bool
    let lastUpdateResult: PluginsStore.UpdateResult?
    let onToggle: (Bool) -> Void
    let onCheckUpdate: () -> Void
    let onUpdateNow: () -> Void
    let onDismissUpdateResult: () -> Void
    @EnvironmentObject private var navigator: Navigator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                updateBanner
                if let result = lastUpdateResult {
                    updateResultBanner(result)
                }
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
                // Always-visible Update now CTA — mirrors Claude Code's
                // /plugin TUI where "Update now" is a top-level action on
                // every plugin, not gated behind a prior check.
                Button(action: onUpdateNow) {
                    if isUpdating {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.small)
                            Text("Updating…")
                        }
                    } else {
                        Label("Update now", systemImage: "arrow.down.circle")
                    }
                }
                .controlSize(.large)
                .disabled(isUpdating)
                .help("Run `claude plugin update \(plugin.id)` — Claude Code pulls the latest version. Restart running sessions to pick it up.")

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

    /// Upstream-status row. Always present when a plugin is tracked — it
    /// either says "Up to date", "Update available · <shas>", or offers a
    /// Check button. Upgrading itself is NOT our responsibility; that
    /// stays with Claude Code's `/plugin update` command.
    @ViewBuilder
    private var updateBanner: some View {
        switch status {
        case .unchecked:
            // No banner in this state — the always-visible "Update now"
            // button in the header is the entry point; a separate
            // "Upstream not checked yet · Check" row is just noise.
            EmptyView()
        case .checking:
            bannerRow(
                icon: "arrow.triangle.2.circlepath",
                tint: .secondary,
                title: "Checking upstream…",
                subtitle: nil,
                action: nil,
                actionLabel: nil,
                pulse: true
            )
        case .upToDate(let local, let at):
            bannerRow(
                icon: "checkmark.seal.fill",
                tint: .green,
                title: "Up to date",
                subtitle: "\(local.prefix(7)) · checked \(Self.relative(at))",
                action: onCheckUpdate,
                actionLabel: "Re-check",
                pulse: false
            )
        case .updateAvailable(let local, let remote, let at):
            updateAvailableBanner(local: local, remote: remote, at: at)
        case .notTracked:
            bannerRow(
                icon: "link.badge.plus",
                tint: .secondary,
                title: "Not tracked by git",
                subtitle: "Bundle at \(plugin.bundleRoot.lastPathComponent) isn't a git checkout — nothing to compare against.",
                action: nil,
                actionLabel: nil,
                pulse: false
            )
        case .error(let reason):
            bannerRow(
                icon: "exclamationmark.triangle.fill",
                tint: .red,
                title: "Update check failed",
                subtitle: reason,
                action: onCheckUpdate,
                actionLabel: "Retry",
                pulse: false
            )
        }
    }

    /// Dedicated variant so the "Update now" CTA can sit next to a
    /// "Re-check" button without cramming two actions into the generic
    /// banner helper. Spinner while the CLI call is in flight.
    private func updateAvailableBanner(local: String, remote: String, at: Date) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.orange)
                .font(.body)
            VStack(alignment: .leading, spacing: 2) {
                Text("Update available").font(.caption.bold())
                Text("\(local.prefix(7)) → \(remote.prefix(7)) · checked \(Self.relative(at)). Updating requires a Claude Code restart to apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onCheckUpdate) {
                Text("Re-check")
            }
            .controlSize(.small)
            .disabled(isUpdating)
            Button(action: onUpdateNow) {
                if isUpdating {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text("Updating…")
                    }
                } else {
                    Text("Update now")
                }
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .disabled(isUpdating)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    /// Post-run outcome banner — kept dismissible so the detail view
    /// doesn't grow a scroll-only set of stale messages.
    private func updateResultBanner(_ result: PluginsStore.UpdateResult) -> some View {
        let (icon, tint, title, subtitle): (String, Color, String, String) = {
            switch result {
            case .success(let output, let at):
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                let preview = trimmed.isEmpty ? "Completed. Restart Claude Code sessions to apply." : trimmed
                return ("checkmark.circle.fill", .green, "Updated \(Self.relative(at))", preview)
            case .failure(let msg, let at):
                return ("xmark.octagon.fill", .red, "Update failed \(Self.relative(at))", msg)
            }
        }()
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.body)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(6)
            }
            Spacer()
            Button("Dismiss", action: onDismissUpdateResult)
                .controlSize(.small)
        }
        .padding(10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(tint.opacity(0.25), lineWidth: 1))
    }

    private func bannerRow(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String?,
        action: (() -> Void)?,
        actionLabel: String?,
        pulse: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if pulse {
                    Image(systemName: icon)
                        .symbolEffect(.pulse, options: .repeating)
                } else {
                    Image(systemName: icon)
                }
            }
            .foregroundStyle(tint)
            .font(.body)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.bold())
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let action, let actionLabel {
                Button(actionLabel, action: action)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        )
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
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
