import SwiftUI

struct SkillListView: View {
    let handles: [SkillHandle]
    @Binding var selected: SkillHandle.ID?
    @Binding var searchText: String
    let totalCount: Int
    let isLoading: Bool
    let error: String?
    let onNewSkill: () -> Void
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
                malformedSection
                pluginSection
            }
            .listStyle(.sidebar)
            .overlay {
                if handles.isEmpty, !isLoading {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No skills" : "No matches",
                        systemImage: "wand.and.stars",
                        description: Text(searchText.isEmpty
                            ? "Drop a skill under ~/.claude/skills/ or click New Skill."
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

    // MARK: - section builders

    @ViewBuilder
    private var userSection: some View {
        let items = grouped[.user] ?? []
        if !items.isEmpty {
            Section {
                ForEach(items) { handle in
                    SkillRow(handle: handle)
                        .tag(handle.id as SkillHandle.ID?)
                }
            } header: {
                SectionHeader(
                    icon: "person.circle",
                    title: "User",
                    count: items.count
                )
            }
        }
    }

    @ViewBuilder
    private var malformedSection: some View {
        let items = grouped[.malformed] ?? []
        if !items.isEmpty {
            Section {
                ForEach(items) { handle in
                    SkillRow(handle: handle)
                        .tag(handle.id as SkillHandle.ID?)
                }
            } header: {
                SectionHeader(
                    icon: "exclamationmark.triangle",
                    title: "Invalid",
                    count: items.count
                )
            }
        }
    }

    @ViewBuilder
    private var pluginSection: some View {
        let items = grouped[.plugin] ?? []
        if !items.isEmpty {
            Section {
                ForEach(pluginGroups(for: items), id: \.pluginName) { group in
                    DisclosureGroup {
                        ForEach(group.skills) { handle in
                            SkillRow(handle: handle)
                                .tag(handle.id as SkillHandle.ID?)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "puzzlepiece.extension")
                                .foregroundStyle(.secondary)
                            Text(group.pluginName)
                                .font(.caption.bold())
                            Spacer()
                            Text("\(group.skills.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } header: {
                SectionHeader(
                    icon: "puzzlepiece.extension",
                    title: "Plugin-provided",
                    count: items.count
                )
            }
        }
    }

    // MARK: - layout helpers

    private var grouped: [SkillHandle.Section: [SkillHandle]] {
        Dictionary(grouping: handles, by: \.section)
    }

    private struct PluginGroup {
        let pluginName: String
        let skills: [SkillHandle]
    }

    private func pluginGroups(for items: [SkillHandle]) -> [PluginGroup] {
        let grouped = Dictionary(grouping: items) { handle -> String in
            if case .plugin(let name) = handle.scope { return name }
            return "unknown"
        }
        return grouped
            .map { PluginGroup(pluginName: $0.key, skills: $0.value) }
            .sorted { $0.pluginName.localizedCaseInsensitiveCompare($1.pluginName) == .orderedAscending }
    }

    // MARK: - chrome

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search skills", text: $searchText)
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
            Button(action: onNewSkill) {
                Label("New Skill", systemImage: "plus")
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

private struct SkillRow: View {
    let handle: SkillHandle

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(handle.name)
                    .font(.body)
                    .lineLimit(1)
                scopeBadge
            }
            if !handle.description.isEmpty {
                Text(handle.description)
                    .font(.caption)
                    .foregroundStyle(handle.isEditable ? .secondary : .tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var scopeBadge: some View {
        switch handle.scope {
        case .userSymlink:
            Image(systemName: "link")
                .foregroundStyle(.secondary)
                .font(.caption2)
                .help("Symlink to external bundle")
        case .plugin:
            Image(systemName: "lock.fill")
                .foregroundStyle(.tertiary)
                .font(.caption2)
                .help("Plugin-provided (read-only)")
        case .malformed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption2)
                .help("Invalid skill")
        case .user:
            EmptyView()
        }
    }
}
