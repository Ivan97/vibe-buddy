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

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

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
        .onAppear(perform: loadDocument)
        .alert("Delete \(handle.name)?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes \(handle.url.lastPathComponent) from disk. A .bak sibling is kept.")
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
        .padding(12)
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
                    MarkdownEditor(
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

    private func extraSummary(_ value: FrontmatterValue) -> String {
        switch value {
        case .scalar(let s):
            return s
        case .list(let items):
            return "[\(items.joined(separator: ", "))]"
        }
    }
}
