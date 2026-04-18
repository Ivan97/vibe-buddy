import SwiftUI

struct EventEditorView: View {
    @Binding var editing: HooksConfig
    let eventName: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if eventIndex == nil {
                    emptyState
                } else {
                    matcherList
                    addGroupButton
                }
            }
            .padding(20)
        }
    }

    // MARK: - sub-views

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eventName).font(.title2.bold())
            Text(eventDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.horizontal")
                    .foregroundStyle(.secondary)
                Text("No hooks configured for this event.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            Button("+ Add matcher group") { addGroup() }
                .buttonStyle(.bordered)
        }
    }

    private var matcherList: some View {
        ForEach(matcherIndices, id: \.self) { idx in
            MatcherGroupCard(
                group: $editing.events[eventIndex!].matchers[idx],
                canHaveMatcher: eventAcceptsMatcher,
                onDelete: { removeGroup(at: idx) }
            )
        }
    }

    private var addGroupButton: some View {
        Button("+ Add matcher group") { addGroup() }
            .buttonStyle(.bordered)
    }

    // MARK: - event helpers

    private var eventIndex: Int? {
        editing.events.firstIndex(where: { $0.name == eventName })
    }

    private var matcherIndices: [Int] {
        guard let idx = eventIndex else { return [] }
        return Array(editing.events[idx].matchers.indices)
    }

    private var eventDescription: String {
        switch HookEventKind(rawValue: eventName) {
        case .preToolUse:         return "Fires right before a tool is invoked. Matcher filters by tool name."
        case .postToolUse:        return "Fires after a tool call completes."
        case .userPromptSubmit:   return "Fires when the user submits a new prompt."
        case .notification:       return "Fires when Claude Code posts a user-visible notification."
        case .stop:               return "Fires when the main assistant turn ends."
        case .subagentStart:      return "Fires when a subagent begins."
        case .subagentStop:       return "Fires when a subagent completes."
        case .preCompact:         return "Fires before the conversation is compacted."
        case .sessionStart:       return "Fires when a session starts (new / resumed)."
        case .sessionEnd:         return "Fires when the session is about to end."
        case .permissionRequest:  return "Fires when Claude Code asks the user for permission."
        case .none:               return "Custom event from your settings.json."
        }
    }

    /// Claude Code only honors the `matcher` field for tool-related events.
    /// For the others, the field is effectively ignored; hide it to reduce
    /// clutter.
    private var eventAcceptsMatcher: Bool {
        switch HookEventKind(rawValue: eventName) {
        case .preToolUse, .postToolUse: return true
        default: return false
        }
    }

    // MARK: - mutations

    private func addGroup() {
        let newGroup = HookMatcherGroup(
            matcher: eventAcceptsMatcher ? "*" : nil,
            commands: [HookCommand(command: "")]
        )
        if let idx = eventIndex {
            editing.events[idx].matchers.append(newGroup)
        } else {
            editing.events.append(HookEvent(name: eventName, matchers: [newGroup]))
        }
    }

    private func removeGroup(at index: Int) {
        guard let idx = eventIndex else { return }
        editing.events[idx].matchers.remove(at: index)
        if editing.events[idx].matchers.isEmpty {
            editing.events.remove(at: idx)
        }
    }
}

// MARK: - matcher group card

private struct MatcherGroupCard: View {
    @Binding var group: HookMatcherGroup
    let canHaveMatcher: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if canHaveMatcher {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Matcher")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        TextField("Tool name pattern (e.g. Edit|Write|Bash)",
                                  text: Binding(
                                    get: { group.matcher ?? "" },
                                    set: { group.matcher = $0.isEmpty ? nil : $0 }
                                  ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    }
                } else {
                    Label("Match-all", systemImage: "asterisk.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove this matcher group")
            }

            Divider()

            ForEach(Array(group.commands.indices), id: \.self) { idx in
                HookCommandRow(
                    command: $group.commands[idx],
                    onDelete: {
                        group.commands.remove(at: idx)
                    }
                )
            }

            Button("+ Add hook") {
                group.commands.append(HookCommand(command: ""))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator)
        )
    }
}

private struct HookCommandRow: View {
    @Binding var command: HookCommand
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Type").font(.caption.bold()).foregroundStyle(.secondary)
                    TextField("command", text: $command.type)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Timeout (s)").font(.caption.bold()).foregroundStyle(.secondary)
                    TextField("", text: Binding(
                        get: { command.timeout.map(String.init) ?? "" },
                        set: { command.timeout = Int($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                }
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove this hook")
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Command").font(.caption.bold()).foregroundStyle(.secondary)
                TextField("e.g. /path/to/script --arg",
                          text: $command.command,
                          axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1...4)
            }
        }
        .padding(.vertical, 4)
    }
}
