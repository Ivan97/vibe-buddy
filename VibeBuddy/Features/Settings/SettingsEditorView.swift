import SwiftUI

struct SettingsEditorView: View {
    @ObservedObject var store: SettingsStore
    let target: SettingsTarget
    @EnvironmentObject private var navigator: Navigator

    @State private var original: ClaudeSettings?
    @State private var editing: ClaudeSettings = .empty
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var isSaving: Bool = false
    @State private var pendingSave: (before: String, after: String)?

    private var isDirty: Bool {
        guard let original else { return false }
        return original != editing
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if !target.isPrimarilyUserEditable {
                mainConfigBanner
            }

            if let err = loadError {
                ContentUnavailableView(
                    "Couldn't parse \(target.title)",
                    systemImage: "exclamationmark.triangle",
                    description: Text(err)
                )
            } else {
                form
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: target, initial: true) { _, _ in load() }
        .sheet(isPresented: Binding(
            get: { pendingSave != nil },
            set: { if !$0 { pendingSave = nil } }
        )) {
            if let pair = pendingSave {
                DiffPreviewSheet(
                    title: "Save changes to \(target.title)?",
                    message: target.url(in: store.claudeHome).path(percentEncoded: false),
                    beforeText: pair.before,
                    afterText: pair.after,
                    onConfirm: commitSave
                )
            }
        }
    }

    // MARK: - toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(target.title).font(.headline)
                Text(target.url(in: store.claudeHome).path(percentEncoded: false))
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()

            if isDirty {
                Label("Unsaved", systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .labelStyle(.titleAndIcon)
            }
            if let err = saveError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([target.url(in: store.claudeHome)])
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")

            Button("Revert") { load() }
                .disabled(!isDirty)

            Button("Save") { prepareSave() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!isDirty || isSaving)
        }
        .padding(12)
    }

    private var mainConfigBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Most of this file is internal state").font(.caption.bold())
                Text("\(SettingsTarget.main.url(in: store.claudeHome).lastPathComponent) stores MCP servers, project index, tips history, and similar. Edit the handful of user-facing keys below carefully — the rest round-trips untouched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.orange.opacity(0.3)), alignment: .bottom)
    }

    // MARK: - form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                modelSection
                themeSection
                permissionsSection
                envSection
                miscSection
                Divider().padding(.vertical, 2)
                extrasSection
            }
            .padding(20)
        }
    }

    private var modelSection: some View {
        LabeledRow(
            "Default model",
            hint: "Which model Claude Code should default to. Leave blank to inherit."
        ) {
            Picker("", selection: Binding(
                get: { editing.model ?? "" },
                set: { editing.model = $0.isEmpty ? nil : $0 }
            )) {
                Text("Inherit").tag("")
                Text("opus").tag("opus")
                Text("sonnet").tag("sonnet")
                Text("haiku").tag("haiku")
                if let custom = editing.model,
                   !["opus", "sonnet", "haiku", ""].contains(custom) {
                    Text(custom).tag(custom)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var themeSection: some View {
        LabeledRow(
            "Theme",
            hint: "Terminal color theme Claude Code applies"
        ) {
            Picker("", selection: Binding(
                get: { editing.theme ?? "" },
                set: { editing.theme = $0.isEmpty ? nil : $0 }
            )) {
                Text("Inherit").tag("")
                Text("dark").tag("dark")
                Text("light").tag("light")
                Text("dark-daltonized").tag("dark-daltonized")
                Text("light-daltonized").tag("light-daltonized")
                Text("dark-ansi").tag("dark-ansi")
                Text("light-ansi").tag("light-ansi")
                if let custom = editing.theme,
                   !["dark", "light", "dark-daltonized", "light-daltonized", "dark-ansi", "light-ansi", ""].contains(custom) {
                    Text(custom).tag(custom)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var permissionsSection: some View {
        LabeledRow(
            "Permissions",
            hint: "Tool-pattern match rules. One pattern per line (e.g. Bash(npm test:*))"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                permissionList("Allow", color: .green, keyPath: \.allow)
                permissionList("Deny", color: .red, keyPath: \.deny)
                permissionList("Ask", color: .yellow, keyPath: \.ask)
            }
        }
    }

    private func permissionList(
        _ title: String,
        color: Color,
        keyPath: WritableKeyPath<ClaudeSettings.Permissions, [String]>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title).font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Text("\(editing.permissions[keyPath: keyPath].count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            StringListEditor(
                items: Binding(
                    get: { editing.permissions[keyPath: keyPath] },
                    set: { editing.permissions[keyPath: keyPath] = $0 }
                ),
                placeholder: title == "Allow"
                    ? "Bash(npm test:*)\nRead(~/.claude/**)"
                    : "One pattern per line",
                minHeight: 64
            )
        }
    }

    private var envSection: some View {
        LabeledRow(
            "Environment",
            hint: "KEY=VALUE, injected into every Claude Code session"
        ) {
            KeyValueEditor(
                dict: $editing.env,
                placeholder: "ANTHROPIC_BASE_URL=https://...\nCLAUDE_CODE_ENABLE_TELEMETRY=1",
                separator: "=",
                minHeight: 96
            )
        }
    }

    private var miscSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledRow("API key helper", hint: "Shell command whose stdout is the Anthropic API key") {
                TextField("/usr/local/bin/anthropic-key", text: Binding(
                    get: { editing.apiKeyHelper ?? "" },
                    set: { editing.apiKeyHelper = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
            }

            HStack(spacing: 24) {
                LabeledRow("Include co-authored-by", hint: "Add Claude as a Git co-author on commits") {
                    TriToggle(value: $editing.includeCoAuthoredBy)
                }
                LabeledRow("Verbose", hint: "Log extra diagnostics") {
                    TriToggle(value: $editing.verbose)
                }
            }

            HStack(spacing: 24) {
                LabeledRow("Cleanup period (days)", hint: "How long to keep session transcripts before pruning") {
                    HStack(spacing: 6) {
                        TextField("30", value: Binding(
                            get: { editing.cleanupPeriodDays ?? 0 },
                            set: { editing.cleanupPeriodDays = $0 == 0 ? nil : $0 }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("days").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                LabeledRow("Output style", hint: "Preset for response formatting") {
                    TextField("default", text: Binding(
                        get: { editing.outputStyle ?? "" },
                        set: { editing.outputStyle = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                }
            }

            LabeledRow("Force login method", hint: "Pin login flow (e.g. 'claudeai', 'console')") {
                TextField("unset", text: Binding(
                    get: { editing.forceLoginMethod ?? "" },
                    set: { editing.forceLoginMethod = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
            }
        }
    }

    // MARK: - extras section

    private var extrasSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Other keys").font(.subheadline.bold())
                Spacer()
                Text("\(editing.extras.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            if editing.extras.isEmpty {
                Text("None. Every top-level key is handled by the form above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Preserved verbatim on save. Keys managed by other modules are listed here — jump over to edit them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(editing.extras.keys.sorted(), id: \.self) { key in
                        extrasRow(key: key)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.06))
                )
            }
        }
    }

    @ViewBuilder
    private func extrasRow(key: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .font(.caption.monospaced().bold())
                .foregroundStyle(.primary)

            if let jump = Self.moduleJump(for: key) {
                Button {
                    navigator.route = jump.route
                } label: {
                    Label("Manage in \(jump.label)", systemImage: "arrow.up.forward.circle")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
            } else {
                Text(Self.extrasPreview(editing.extras[key]))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            Spacer()
        }
    }

    private struct ModuleJump {
        let label: String
        let route: ModuleRoute
    }

    private static func moduleJump(for key: String) -> ModuleJump? {
        switch key {
        case "mcpServers":     return ModuleJump(label: "MCP", route: .mcp)
        case "hooks":          return ModuleJump(label: "Hooks", route: .hooks)
        case "enabledPlugins": return ModuleJump(label: "Plugins", route: .plugins)
        case "statusLine":     return ModuleJump(label: "Statusline", route: .statusline)
        default:               return nil
        }
    }

    private static func extrasPreview(_ value: Any?) -> String {
        guard let value else { return "" }
        if let s = value as? String { return "\"\(s)\"" }
        if let n = value as? NSNumber { return n.stringValue }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "\(value)"
    }

    // MARK: - actions

    private func load() {
        do {
            let loaded = try store.loadSettings(target)
            original = loaded
            editing = loaded
            loadError = nil
            saveError = nil
        } catch {
            loadError = (error as NSError).localizedDescription
        }
    }

    private func prepareSave() {
        do {
            let pair = try store.previewSave(editing, for: target)
            pendingSave = pair
        } catch {
            saveError = (error as NSError).localizedDescription
        }
    }

    private func commitSave() {
        isSaving = true
        defer { isSaving = false }
        do {
            try store.commit(editing, for: target)
            original = editing
            saveError = nil
        } catch {
            saveError = (error as NSError).localizedDescription
        }
        pendingSave = nil
    }
}

// MARK: - helpers

/// Three-state toggle for optional bools: unset / true / false. Matches the
/// `nil` semantics the Claude Code settings file expects (absent key =
/// inherit).
private struct TriToggle: View {
    @Binding var value: Bool?

    var body: some View {
        Picker("", selection: Binding(
            get: { TriValue.from(value) },
            set: { value = $0.toOptional() }
        )) {
            Text("Inherit").tag(TriValue.unset)
            Text("On").tag(TriValue.on)
            Text("Off").tag(TriValue.off)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 220)
    }

    private enum TriValue: Hashable {
        case unset, on, off
        static func from(_ v: Bool?) -> TriValue {
            switch v {
            case nil:    return .unset
            case true?:  return .on
            case false?: return .off
            }
        }
        func toOptional() -> Bool? {
            switch self {
            case .unset: return nil
            case .on:    return true
            case .off:   return false
            }
        }
    }
}

/// One-item-per-line editor that round-trips through a `[String]`. Empty
/// lines are dropped — blank trailing lines in the TextEditor are common
/// while typing and would otherwise be persisted as empty strings.
private struct StringListEditor: View {
    @Binding var items: [String]
    let placeholder: String
    var minHeight: CGFloat = 72

    var body: some View {
        MultilineTextField(
            text: Binding(
                get: { items.joined(separator: "\n") },
                set: { newText in
                    items = newText
                        .split(separator: "\n", omittingEmptySubsequences: false)
                        .map { String($0).trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
            ),
            placeholder: placeholder,
            minHeight: minHeight
        )
    }
}

/// KEY<sep>VALUE editor for a `[String: String]` dict. `separator` is
/// typically `"="` (env) or `":"` (headers).
private struct KeyValueEditor: View {
    @Binding var dict: [String: String]
    let placeholder: String
    let separator: Character
    var minHeight: CGFloat = 96

    var body: some View {
        MultilineTextField(
            text: Binding(
                get: { Self.serialize(dict, separator: separator) },
                set: { dict = Self.parse($0, separator: separator) }
            ),
            placeholder: placeholder,
            minHeight: minHeight
        )
    }

    static func serialize(_ dict: [String: String], separator: Character) -> String {
        dict.sorted(by: { $0.key < $1.key })
            .map { "\($0.key)\(separator)\($0.value)" }
            .joined(separator: "\n")
    }

    static func parse(_ text: String, separator: Character) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let pair = line.split(separator: separator, maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { continue }
            let k = pair[0].trimmingCharacters(in: .whitespaces)
            let v = pair[1].trimmingCharacters(in: .whitespaces)
            if !k.isEmpty { out[k] = v }
        }
        return out
    }
}
