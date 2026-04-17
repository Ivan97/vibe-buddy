import SwiftUI

struct AppSidebar: View {
    @Binding var selection: ModuleRoute?

    var body: some View {
        List(selection: $selection) {
            ForEach(ModuleRoute.Section.allCases, id: \.self) { section in
                Section(section.title) {
                    ForEach(ModuleRoute.allCases.filter { $0.section == section }) { route in
                        SidebarRow(route: route).tag(route)
                    }
                }
            }
        }
        .navigationTitle("VibeBuddy")
    }
}

private struct SidebarRow: View {
    let route: ModuleRoute

    var body: some View {
        HStack {
            Label(route.title, systemImage: route.systemImage)
            Spacer()
            if route.phase > 0 {
                Text("P\(route.phase)")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.15), in: Capsule())
                    .help("Ships in Phase \(route.phase)")
            }
        }
    }
}

#Preview {
    AppSidebar(selection: .constant(.sessions))
        .frame(width: 220, height: 480)
}
