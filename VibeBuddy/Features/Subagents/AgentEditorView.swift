import SwiftUI

struct AgentEditorView: View {
    @ObservedObject var store: AgentStore
    let handle: AgentHandle

    @State private var original: FrontmatterDocument<AgentFrontmatter>?
    @State private var schema: AgentFrontmatter = .empty
    @State private var bodyText: String = ""
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var isSaving: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var pendingSave: FrontmatterDocument<AgentFrontmatter>?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            scopeBanner

            if let err = loadError {
                ContentUnavailableView(
                    "Couldn't load agent",
                    systemImage: "exclamationmark.triangle",
                    description: Text(err)
                )
            } else {
                editor
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: handle.id, initial: true) { _, _ in loadDocument() }
        .alert("Delete \(handle.name)?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes \(handle.url.lastPathComponent) from disk. A .bak sibling is kept.")
        }
        .sheet(isPresented: Binding(
            get: { pendingSave != nil },
            set: { if !$0 { pendingSave = nil } }
        )) {
            if let doc = pendingSave, let original {
                DiffPreviewSheet(
                    title: "Save changes to \(handle.name)?",
                    message: handle.url.path(percentEncoded: false),
                    beforeText: original.serialized(),
                    afterText: doc.serialized(),
                    onConfirm: { commitSave(doc) }
                )
            }
        }
    }

    // MARK: - toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(handle.name).font(.headline)
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
                .help("Delete agent")

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
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plugin-provided — read-only").font(.caption.bold())
                    Text("Shipped by \(pluginName) · \(marketplace). Edits aren't saved from here.")
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
    }

    // MARK: - editor

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let err = saveError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                LabeledRow("Name", hint: "Slug used by Claude Code to invoke the agent") {
                    TextField("kebab-case-name", text: $schema.name)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledRow("Description", hint: "Shown in /agents listing and drives routing") {
                    MultilineTextField(
                        text: $schema.description,
                        placeholder: "One sentence summary…",
                        minHeight: 72
                    )
                }

                LabeledRow("Model", hint: "Optional — inherit from Claude Code if unset") {
                    Picker("", selection: modelBinding) {
                        Text("Inherit").tag(Optional<String>.none)
                        Text("opus").tag(Optional("opus"))
                        Text("sonnet").tag(Optional("sonnet"))
                        Text("haiku").tag(Optional("haiku"))
                        if let custom = schema.model,
                           !["opus", "sonnet", "haiku"].contains(custom) {
                            Text(custom).tag(Optional(custom))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Divider().padding(.vertical, 2)

                LabeledRow("System prompt / body") {
                    MarkdownBodyEditor(
                        text: $bodyText,
                        placeholder: "You are…",
                        minHeight: 360
                    )
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

    private var modelBinding: Binding<String?> {
        Binding(
            get: { schema.model },
            set: { schema.model = $0 }
        )
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

    private func commitSave(_ doc: FrontmatterDocument<AgentFrontmatter>) {
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
        case .scalar(let s):
            return s
        case .list(let items):
            return "[\(items.joined(separator: ", "))]"
        }
    }
}
