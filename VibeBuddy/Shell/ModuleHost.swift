import SwiftUI

struct ModuleHost: View {
    let route: ModuleRoute?

    var body: some View {
        Group {
            switch route {
            case .sessions:
                SessionsRoot()
            case .prompts, .skills, .subagents,
                 .statusline, .mcp, .hooks,
                 .plugins:
                ComingSoonView(route: route!)
            case .none:
                EmptySelectionView()
            }
        }
        .navigationTitle(route?.title ?? "VibeBuddy")
    }
}

private struct EmptySelectionView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Select a module from the sidebar")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
