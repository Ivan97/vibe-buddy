import SwiftUI

struct CommandEditorView: View {
    @ObservedObject var store: CommandStore
    let handle: CommandHandle

    @State private var original: FrontmatterDocument<CommandFrontmatter>?
    @State private var schema: CommandFrontmatter = .empty
    @State private var bodyText: String = ""
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var isSaving: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var pendingSave: FrontmatterDocument<CommandFrontmatter>?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            scopeBanner

            Group {
                if let err = loadError {
                    ContentUnavailableView(
                        "Couldn't load command",
                        systemImage: "exclamationmark.triangle",
                        description: Text(err)
                    )
                } else {
                    editor
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: handle.id, initial: true) { _, _ in loadDocument() }
        .alert("Delete /\(handle.invocationSlug)?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes \(handle.url.lastPathComponent) from disk. A .bak sibling will remain.")
        }
        .sheet(isPresented: Binding(
            get: { pendingSave != nil },
            set: { if !$0 { pendingSave = nil } }
        )) {
            if let doc = pendingSave, let original {
                DiffPreviewSheet(
                    title: "Save /\(handle.invocationSlug)?",
                    message: handle.url.path(percentEncoded: false),
                    beforeText: original.serialized(),
                    afterText: doc.serialized(),
                    onConfirm: { commitSave(doc) }
                )
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("/" + handle.invocationSlug)
                    .font(.headline.monospaced())
                Text(handle.url.path(percentEncoded: false))
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
                NSWorkspace.shared.activateFileViewerSelecting([handle.url])
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")

            if handle.isEditable {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete command")

                Button("Revert") { loadDocument() }
                    .disabled(!isDirty)

                Button("Save") { performSave() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!isDirty || isSaving)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var scopeBanner: some View {
        if case .plugin(let marketplace, let pluginName) = handle.scope {
            Banner(
                icon: "lock.fill",
                tone: .warning,
                title: "Plugin-provided — read-only",
                message: "Shipped by \(pluginName) · \(marketplace). Edits aren't saved from here."
            )
        }
    }

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let err = saveError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                LabeledRow("Description", hint: "Shown in /help and autocomplete") {
                    MultilineTextField(
                        text: Binding(
                            get: { schema.description ?? "" },
                            set: { schema.description = $0.isEmpty ? nil : $0 }
                        ),
                        placeholder: "One sentence summary…",
                        minHeight: 60
                    )
                    .disabled(!handle.isEditable)
                }

                LabeledRow("Argument hint", hint: "Shown inline after the command name in autocomplete") {
                    TextField("[path] [--flag]", text: Binding(
                        get: { schema.argumentHint ?? "" },
                        set: { schema.argumentHint = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .disabled(!handle.isEditable)
                }

                LabeledRow("Allowed tools", hint: "Optional tool-name filter, e.g. 'Bash(gh pr diff:*)'") {
                    TextField("Leave blank for unrestricted", text: Binding(
                        get: { schema.allowedTools ?? "" },
                        set: { schema.allowedTools = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .lineLimit(1...6)
                    .disabled(!handle.isEditable)
                }

                Divider().padding(.vertical, 2)

                LabeledRow("Command body", hint: "Use $ARGUMENTS where user input goes") {
                    MarkdownBodyEditor(
                        text: $bodyText,
                        placeholder: "Write the prompt template here…",
                        minHeight: 360
                    )
                    .disabled(!handle.isEditable)
                }

                if !schema.extras.isEmpty {
                    Divider()
                    LabeledRow("Unknown frontmatter keys", hint: "Preserved verbatim on save") {
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

    // MARK: - state

    private var isDirty: Bool {
        guard let original else { return false }
        return original.schema != schema || original.body != bodyText
    }

    private func loadDocument() {
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
        let doc = FrontmatterDocument(schema: schema, body: bodyText)
        if original != nil {
            pendingSave = doc
        } else {
            commitSave(doc)
        }
    }

    private func commitSave(_ doc: FrontmatterDocument<CommandFrontmatter>) {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try store.save(doc, to: handle)
            original = doc
            saveError = nil
        } catch {
            saveError = (error as NSError).localizedDescription
        }
        pendingSave = nil
    }

    private func performDelete() {
        do {
            try store.delete(handle)
        } catch {
            saveError = (error as NSError).localizedDescription
        }
    }

    private func extraSummary(_ value: FrontmatterValue) -> String {
        switch value {
        case .scalar(let s):     return s
        case .list(let items):   return "[\(items.joined(separator: ", "))]"
        }
    }
}

// MARK: - banner (reused shape from Skills; kept local to avoid cross-module import)

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
            Image(systemName: icon).foregroundStyle(tone.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.bold())
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(tone.color.opacity(0.08))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(tone.color.opacity(0.3)), alignment: .bottom)
    }
}
