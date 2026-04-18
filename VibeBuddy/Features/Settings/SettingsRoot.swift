import SwiftUI

struct SettingsRoot: View {
    @EnvironmentObject private var store: SettingsStore

    var body: some View {
        SettingsShell(store: store)
            .task {
                await store.reload()
                store.startWatching()
            }
    }
}

private struct SettingsShell: View {
    @ObservedObject var store: SettingsStore
    @State private var selected: SettingsTarget = .global

    var body: some View {
        HSplitView {
            SettingsFileListView(
                files: SettingsTarget.allCases.map { store.files[$0] ?? .placeholder(for: $0) },
                selected: $selected
            )
            .frame(minWidth: 260, idealWidth: 400)

            // No .id(selected) — that would reset the HSplitView divider
            // on every target switch. Editor reloads via onChange.
            SettingsEditorView(store: store, target: selected)
                .frame(minWidth: 400, maxHeight: .infinity)
        }
    }
}

private extension SettingsFileState {
    static func placeholder(for target: SettingsTarget) -> SettingsFileState {
        SettingsFileState(target: target, exists: false, byteSize: 0, modifiedAt: nil, loadError: nil)
    }
}
