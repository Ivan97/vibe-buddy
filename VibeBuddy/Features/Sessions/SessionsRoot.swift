import SwiftUI

struct SessionsRoot: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("Sessions")
                .font(.largeTitle.bold())
            Text("List and detail views land in P0-5 and P0-6.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SessionsRoot()
        .frame(width: 640, height: 480)
}
