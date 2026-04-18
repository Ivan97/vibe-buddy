import SwiftUI

struct ModuleHost: View {
    let route: ModuleRoute?

    var body: some View {
        Group {
            switch route {
            case .sessions:
                SessionsRoot()
            case .subagents:
                SubagentsRoot()
            case .skills:
                SkillsRoot()
            case .prompts:
                PromptsRoot()
            case .statusline:
                StatuslineRoot()
            case .mcp:
                MCPRoot()
            case .hooks:
                HooksRoot()
            case .plugins:
                PluginsRoot()
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
