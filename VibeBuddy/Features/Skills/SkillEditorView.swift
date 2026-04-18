import SwiftUI

struct SkillEditorView: View {
    @ObservedObject var store: SkillStore
    let handle: SkillHandle

    @State private var original: FrontmatterDocument<SkillFrontmatter>?
    @State private var schema: SkillFrontmatter = .empty
    @State private var bodyText: String = ""
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var isSaving: Bool = false
    @State private var showDeleteConfirm: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            scopeBanner

            Group {
                if case .malformed(let reason) = handle.scope {
                    malformedView(reason: reason)
                } else if let err = loadError {
                    ContentUnavailableView(
                        "Couldn't load skill",
                        systemImage: "exclamationmark.triangle",
                        description: Text(err)
                    )
                } else {
                    editor
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: loadDocument)
        .alert("Delete \(handle.name)?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if case .userSymlink(let target) = handle.scope {
                Text("Removes the symlink at \(handle.displayURL.lastPathComponent). The source bundle at \(target.path) is NOT touched.")
            } else {
                Text("Removes the skill directory \(handle.displayURL.lastPathComponent) from disk.")
            }
        }
    }

    // MARK: - toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(handle.name).font(.headline)
                Text(handle.skillMdURL.path(percentEncoded: false))
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

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([handle.skillMdURL])
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help("Reveal SKILL.md in Finder")

            if handle.isEditable {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(handle.scope.isSymlink ? "Remove the symlink" : "Delete the skill")

                Button("Revert") { loadDocument() }
                    .disabled(!isDirty)

                Button("Save") { performSave() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!isDirty || isSaving)
            }
        }
        .padding(12)
    }

    // MARK: - scope banner

    @ViewBuilder
    private var scopeBanner: some View {
        switch handle.scope {
        case .userSymlink(let target):
            Banner(
                icon: "link",
                tone: .info,
                title: "This skill is a symlink",
                message: "Edits land at \(target.path(percentEncoded: false))"
            )
        case .plugin(let pluginName):
            Banner(
                icon: "lock.fill",
                tone: .warning,
                title: "Plugin-provided — read-only",
                message: "This skill ships with \(pluginName). Edits aren't saved from here."
            )
        case .malformed:
            EmptyView()    // handled as a content-level view below
        case .user:
            EmptyView()
        }
    }

    // MARK: - editor (editable + plugin read-only share this)

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let err = saveError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                LabeledRow("Name", hint: "Identifier the skill is listed under") {
                    TextField("kebab-case-name", text: $schema.name)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!handle.isEditable)
                }

                LabeledRow("Description", hint: "First sentence is the summary shown in skills listings") {
                    MultilineTextField(
                        text: $schema.description,
                        placeholder: "One sentence summary…",
                        minHeight: 72
                    )
                    .disabled(!handle.isEditable)
                }

                LabeledRow("License", hint: "Optional — drop if the skill doesn't ship a license") {
                    TextField("MIT / Proprietary / etc.", text: Binding(
                        get: { schema.license ?? "" },
                        set: { schema.license = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .disabled(!handle.isEditable)
                }

                Divider().padding(.vertical, 2)

                LabeledRow("SKILL.md body") {
                    MarkdownBodyEditor(
                        text: $bodyText,
                        placeholder: "Skill instructions…",
                        minHeight: 360
                    )
                    .disabled(!handle.isEditable)
                }

                if !schema.extras.isEmpty {
                    Divider()
                    LabeledRow(
                        "Unknown frontmatter keys",
                        hint: "Preserved verbatim on save"
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(schema.extras, id: \.key) { pair in
                                HStack(alignment: .top, spacing: 4) {
                                    Text("\(pair.key):")
                                        .font(.caption.monospaced().bold())
                                    Text(extraSummary(pair.value))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(4)
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - malformed

    @ViewBuilder
    private func malformedView(reason: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text("Invalid skill")
                .font(.title2.bold())
            Text(reason)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if reason.contains("SKILL.md") || reason.contains("missing") {
                Button("Create SKILL.md") {
                    performBootstrap()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
            }

            if let err = saveError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - state

    private var isDirty: Bool {
        guard let original else { return false }
        return original.schema != schema || original.body != bodyText
    }

    private func loadDocument() {
        // Plugin-provided is still readable; malformed has no SKILL.md.
        if case .malformed = handle.scope {
            return
        }
        do {
            let doc = try store.load(handle)
            original = doc
            schema = doc.schema
            bodyText = doc.body
            loadError = nil
        } catch {
            loadError = (error as NSError).localizedDescription
        }
    }

    private func performSave() {
        isSaving = true
        defer { isSaving = false }
        let doc = FrontmatterDocument(schema: schema, body: bodyText)
        do {
            _ = try store.save(doc, to: handle)
            original = doc
            saveError = nil
        } catch {
            saveError = (error as NSError).localizedDescription
        }
    }

    private func performDelete() {
        do {
            try store.delete(handle)
        } catch {
            saveError = (error as NSError).localizedDescription
        }
    }

    private func performBootstrap() {
        do {
            _ = try store.bootstrapSkillMd(at: handle)
            saveError = nil
        } catch {
            saveError = (error as NSError).localizedDescription
        }
    }

    private func extraSummary(_ value: FrontmatterValue) -> String {
        switch value {
        case .scalar(let s):
            return s
        case .list(let items):
            return "[\(items.joined(separator: ", "))]"
        }
    }
}

// MARK: - banner

private struct Banner: View {
    let icon: String
    let tone: Tone
    let title: String
    let message: String

    enum Tone {
        case info, warning
        var color: Color {
            switch self {
            case .info:    return .accentColor
            case .warning: return .orange
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tone.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.bold())
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(tone.color.opacity(0.08))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(tone.color.opacity(0.3)), alignment: .bottom)
    }
}

private extension SkillHandle.Scope {
    var isSymlink: Bool {
        if case .userSymlink = self { return true }
        return false
    }
}
