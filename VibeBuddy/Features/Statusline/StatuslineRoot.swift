import SwiftUI

struct StatuslineRoot: View {
    @EnvironmentObject private var store: StatuslineStore

    var body: some View {
        StatuslineShell(store: store)
            .task {
                await store.reload()
                store.startWatching()
            }
    }
}

private struct StatuslineShell: View {
    @ObservedObject var store: StatuslineStore

    @State private var editing: StatuslineConfig = .empty
    @State private var original: StatuslineConfig = .empty
    @State private var diffPair: DiffPair?
    @State private var saveError: String?

    // Preview state
    @State private var previewOutput: String = ""
    @State private var previewStderr: String = ""
    @State private var previewExitCode: Int32?
    @State private var previewDurationMs: Int?
    @State private var isRunningPreview: Bool = false
    @State private var previewError: String?

    private var isDirty: Bool { editing != original }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()
                editorCard
                Divider()
                previewCard
                Spacer(minLength: 12)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            editing = store.config
            original = store.config
        }
        .onChange(of: store.config) { _, new in
            if !isDirty {
                editing = new
                original = new
            }
        }
        .sheet(isPresented: Binding(
            get: { diffPair != nil },
            set: { if !$0 { diffPair = nil } }
        )) {
            if let pair = diffPair {
                DiffPreviewSheet(
                    title: "Save statusline to settings.json?",
                    message: store.claudeHome.settingsFile.path(percentEncoded: false),
                    beforeText: pair.before,
                    afterText: pair.after,
                    onConfirm: { commit(pair.updated) }
                )
            }
        }
    }

    // MARK: - header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Statusline").font(.title2.bold())
                Text(store.claudeHome.settingsFile.path(percentEncoded: false))
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if isDirty {
                Label("Unsaved", systemImage: "circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let err = saveError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button("Revert") { editing = original; saveError = nil }
                .disabled(!isDirty)
            Button("Save") { prepareSave() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!isDirty)
        }
    }

    // MARK: - editor

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Configuration").font(.headline)

            LabeledRow("Type", hint: "Claude Code supports \"command\" today") {
                Picker("", selection: $editing.type) {
                    Text("command").tag("command")
                    if editing.type != "command" {
                        Text(editing.type).tag(editing.type)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            LabeledRow("Command", hint: "Runs once per turn; stdin is the session-context JSON, stdout is the rendered line") {
                TextField(
                    "/path/to/your/statusline-script",
                    text: $editing.command,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .lineLimit(1...4)
            }

            if !editing.extras.isEmpty {
                LabeledRow("Unknown fields", hint: "Preserved verbatim on save") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(editing.extras.keys.sorted()), id: \.self) { k in
                            HStack(alignment: .top, spacing: 4) {
                                Text("\(k):")
                                    .font(.caption.monospaced().bold())
                                Text(editing.extras[k] ?? "")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - preview

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Preview").font(.headline)
                Spacer()
                Button {
                    Task { await runPreview() }
                } label: {
                    Label(isRunningPreview ? "Running…" : "Run preview", systemImage: "play.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isRunningPreview || editing.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let err = previewError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Group {
                if previewOutput.isEmpty, previewStderr.isEmpty, previewExitCode == nil {
                    Text("Click Run preview to execute the command with a mocked session context on stdin.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    previewOutputView
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        }
    }

    private var previewOutputView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let code = previewExitCode {
                    Label("exit \(code)", systemImage: code == 0 ? "checkmark.circle" : "xmark.octagon")
                        .foregroundStyle(code == 0 ? .green : .red)
                        .font(.caption)
                }
                if let ms = previewDurationMs {
                    Text("\(ms) ms")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !previewOutput.isEmpty {
                Text("stdout")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(previewOutput)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !previewStderr.isEmpty {
                Text("stderr")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
                Text(previewStderr)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.red.opacity(0.9))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func runPreview() async {
        isRunningPreview = true
        previewError = nil
        do {
            let result = try await StatuslinePreview.run(command: editing.command)
            previewOutput = result.stdout
            previewStderr = result.stderr
            previewExitCode = result.exitCode
            previewDurationMs = result.durationMs
        } catch {
            previewError = (error as NSError).localizedDescription
        }
        isRunningPreview = false
    }

    // MARK: - save

    private struct DiffPair {
        let before: String
        let after: String
        let updated: StatuslineConfig
    }

    private func prepareSave() {
        do {
            let pair = try store.previewSave(editing)
            diffPair = DiffPair(before: pair.before, after: pair.after, updated: editing)
        } catch {
            saveError = (error as NSError).localizedDescription
        }
    }

    private func commit(_ updated: StatuslineConfig) {
        do {
            try store.commit(updated)
            original = updated
            editing = updated
            saveError = nil
        } catch {
            saveError = (error as NSError).localizedDescription
        }
        diffPair = nil
    }
}
