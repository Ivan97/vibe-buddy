import SwiftUI

struct ComingSoonView: View {
    let route: ModuleRoute

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: route.systemImage)
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)

            Text(route.title)
                .font(.largeTitle.bold())

            Text("Planned for Phase \(route.phase)")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(phaseDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var phaseDescription: String {
        switch route.phase {
        case 1:
            return "Ships with the shared markdown + frontmatter editor alongside the other Authoring modules."
        case 2:
            return "Ships with the safe JSON writer (schema + backup + diff) alongside the other Config modules."
        case 3:
            return "Plugin marketplace, install/uninstall, and cross-module effect visualization."
        default:
            return "Coming soon."
        }
    }
}

#Preview {
    ComingSoonView(route: .mcp)
        .frame(width: 600, height: 400)
}
