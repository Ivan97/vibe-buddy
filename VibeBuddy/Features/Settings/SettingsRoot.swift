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
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)

            SettingsEditorView(store: store, target: selected)
                .id(selected)
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private extension SettingsFileState {
    static func placeholder(for target: SettingsTarget) -> SettingsFileState {
        SettingsFileState(target: target, exists: false, byteSize: 0, modifiedAt: nil, loadError: nil)
    }
}
