import SwiftUI

struct EventSidebar: View {
    @Binding var editing: HooksConfig
    @Binding var selected: String?

    var body: some View {
        List(selection: $selected) {
            Section("Known events") {
                ForEach(HookEventKind.allCases, id: \.rawValue) { kind in
                    row(name: kind.rawValue).tag(kind.rawValue as String?)
                }
            }

            if !customEventNames.isEmpty {
                Section("Custom") {
                    ForEach(customEventNames, id: \.self) { name in
                        row(name: name).tag(name as String?)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(name: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.horizontal")
                .foregroundStyle(.secondary)
            Text(name).font(.callout)
            Spacer()
            let count = hookCount(for: name)
            if count > 0 {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.secondary.opacity(0.15), in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    private var customEventNames: [String] {
        let known = Set(HookEventKind.allCases.map(\.rawValue))
        return editing.events
            .map(\.name)
            .filter { !known.contains($0) }
    }

    private func hookCount(for name: String) -> Int {
        editing.events.first(where: { $0.name == name })?.hookCount ?? 0
    }
}
