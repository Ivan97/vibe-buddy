import SwiftUI

struct AppShellView: View {
    @EnvironmentObject private var navigator: Navigator

    var body: some View {
        NavigationSplitView {
            AppSidebar(selection: $navigator.route)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            ModuleHost(route: navigator.route)
        }
    }
}

#Preview {
    AppShellView()
        .environmentObject(Navigator())
        .frame(width: 1040, height: 680)
}
