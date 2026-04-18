import Foundation

/// Typed mirror of the `hooks` dictionary in `settings.json`. Round-trips
/// through `toJSON()` / `parse(_:)` so unknown keys on individual hooks
/// (things Claude Code might add in a future version) pass through
/// unchanged — see `HookCommand.extras`.
struct HooksConfig: Equatable, Sendable {
    /// One entry per event type. Order preserved from disk so serialize →
    /// parse → serialize is stable.
    var events: [HookEvent]

    static let empty = HooksConfig(events: [])
}

/// Canonical set of event types Claude Code currently emits. Anything the
/// settings file carries that isn't in here still round-trips via
/// `HookEvent.name` (a free-form string) so we don't break on new events.
enum HookEventKind: String, CaseIterable, Hashable, Sendable {
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case userPromptSubmit = "UserPromptSubmit"
    case notification = "Notification"
    case stop = "Stop"
    case subagentStart = "SubagentStart"
    case subagentStop = "SubagentStop"
    case preCompact = "PreCompact"
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    case permissionRequest = "PermissionRequest"

    /// Shorter human-facing label for chips / list rows.
    var displayName: String { rawValue }
}

struct HookEvent: Identifiable, Equatable, Sendable {
    /// Raw event string as it appears in settings.json. Typically one of
    /// `HookEventKind`'s raw values, but kept as String so unknown events
    /// don't get silently dropped.
    var name: String
    var matchers: [HookMatcherGroup]

    var id: String { name }

    var kind: HookEventKind? { HookEventKind(rawValue: name) }
    var hookCount: Int { matchers.reduce(0) { $0 + $1.commands.count } }
}

/// A single group within an event. The `matcher` string (Claude Code's
/// tool-name pattern, e.g. `Edit|Write|Bash`) is optional; absent means
/// "run for every invocation of the event".
struct HookMatcherGroup: Identifiable, Equatable, Sendable {
    let id: UUID
    var matcher: String?
    var commands: [HookCommand]

    init(id: UUID = UUID(), matcher: String?, commands: [HookCommand]) {
        self.id = id
        self.matcher = matcher
        self.commands = commands
    }

    /// Content equality — UUID `id` is deliberately excluded so a
    /// reserialize-then-reparse compares as equal even though each parse
    /// mints fresh identities for SwiftUI list diffing.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.matcher == rhs.matcher && lhs.commands == rhs.commands
    }
}

/// One executable hook line. `type` is almost always `"command"` today;
/// kept as a string so forward-compat is cheap.
struct HookCommand: Identifiable, Equatable, Sendable {
    let id: UUID
    var type: String
    var command: String
    var timeout: Int?
    /// Unknown keys we parsed out of the object — round-tripped verbatim
    /// via `toJSON()` so new Claude Code fields don't get erased on save.
    var extras: [String: String]

    init(
        id: UUID = UUID(),
        type: String = "command",
        command: String,
        timeout: Int? = nil,
        extras: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.command = command
        self.timeout = timeout
        self.extras = extras
    }

    /// Content equality — see `HookMatcherGroup.==` note.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.type == rhs.type
            && lhs.command == rhs.command
            && lhs.timeout == rhs.timeout
            && lhs.extras == rhs.extras
    }
}
