import SwiftUI

struct HooksRoot: View {
    @EnvironmentObject private var store: HooksStore

    var body: some View {
        HooksShell(store: store)
            .task {
                await store.reload()
                store.startWatching()
            }
    }
}

private struct HooksShell: View {
    @ObservedObject var store: HooksStore

    @State private var editing: HooksConfig = .empty
    @State private var original: HooksConfig = .empty
    @State private var selectedEventName: String?
    @State private var diffPair: DiffPair?
    @State private var saveError: String?

    private var isDirty: Bool { editing.pruned() != original.pruned() }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            editing = store.config
            original = store.config
            if selectedEventName == nil {
                selectedEventName = store.config.events.first?.name
                    ?? HookEventKind.allCases.first?.rawValue
            }
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
                    title: "Save hooks to settings.json?",
                    message: store.claudeHome.settingsFile.path(percentEncoded: false),
                    beforeText: pair.before,
                    afterText: pair.after,
                    onConfirm: { commit(pair.updated) }
                )
            }
        }
    }

    // MARK: - toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hooks").font(.headline)
                Text(store.claudeHome.settingsFile.path(percentEncoded: false))
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
            Button("Revert") {
                editing = original
                saveError = nil
            }
            .disabled(!isDirty)
            Button("Save") { prepareSave() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!isDirty)
        }
        .padding(12)
    }

    private var content: some View {
        HSplitView {
            EventSidebar(editing: $editing, selected: $selectedEventName)
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

            Group {
                if let name = selectedEventName {
                    EventEditorView(editing: $editing, eventName: name)
                } else {
                    ContentUnavailableView(
                        "Select an event",
                        systemImage: "point.forward.to.point.capsulepath"
                    )
                }
            }
            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - save

    private struct DiffPair {
        let before: String
        let after: String
        let updated: HooksConfig
    }

    private func prepareSave() {
        let updated = editing.pruned()
        do {
            let pair = try store.previewSave(updated)
            diffPair = DiffPair(before: pair.before, after: pair.after, updated: updated)
        } catch {
            saveError = (error as NSError).localizedDescription
        }
    }

    private func commit(_ updated: HooksConfig) {
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
