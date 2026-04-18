import Foundation

/// A discovered skill on disk. `skillMdURL` is the resolved path that the
/// editor reads/writes (symlinks followed); `displayURL` is what to show in
/// the UI header so the user knows the apparent location in `~/.claude/`.
struct SkillHandle: Identifiable, Hashable, Sendable {
    let id: String            // canonical resolved path of the SKILL.md
    let name: String          // frontmatter name, falls back to directory name
    let description: String   // truncated preview, from frontmatter
    let displayURL: URL       // where the skill *appears* to live (may be a symlink)
    let skillMdURL: URL       // resolved SKILL.md path (real file to write)
    let scope: Scope

    enum Scope: Hashable, Sendable {
        /// Plain directory under `~/.claude/skills/<name>/`.
        case user
        /// `~/.claude/skills/<name>` is a symlink; edits land at `target`.
        case userSymlink(target: URL)
        /// Shipped by a plugin at `~/.claude/plugins/cache/<plugin>/.../`.
        case plugin(pluginName: String)
        /// Entry that's in `~/.claude/skills/` but not a usable skill:
        /// a loose file, empty directory, missing SKILL.md, etc.
        case malformed(reason: String)
    }

    /// Whether the skill should expose a Save button. Plugin-provided and
    /// malformed skills are read-only in the editor (with a clear banner).
    var isEditable: Bool {
        switch scope {
        case .user, .userSymlink:        return true
        case .plugin, .malformed:        return false
        }
    }

    /// Section the skill belongs to in the sidebar.
    var section: Section {
        switch scope {
        case .user, .userSymlink:        return .user
        case .plugin:                    return .plugin
        case .malformed:                 return .malformed
        }
    }

    enum Section: String, CaseIterable, Hashable, Sendable {
        case user, plugin, malformed

        var title: String {
            switch self {
            case .user:      return "User"
            case .plugin:    return "Plugin-provided"
            case .malformed: return "Invalid"
            }
        }
    }
}
