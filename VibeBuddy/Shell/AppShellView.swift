import SwiftUI

struct AppShellView: View {
    @State private var selection: ModuleRoute? = .sessions

    var body: some View {
        NavigationSplitView {
            AppSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            ModuleHost(route: selection)
        }
    }
}

#Preview {
    AppShellView()
        .frame(width: 1040, height: 680)
}
