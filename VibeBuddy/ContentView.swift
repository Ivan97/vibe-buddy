import SwiftUI
import ConfettiSwiftUI

struct ContentView: View {
    @EnvironmentObject private var updater: SparkleUpdaterController
    @State private var confettiTrigger: Int = 0

    var body: some View {
        VStack(spacing: 24) {
            Text("Vibe Buddy")
                .font(.system(size: 40, weight: .bold, design: .rounded))

            Text("Claude Code 的增强伙伴")
                .font(.title3)
                .foregroundStyle(.secondary)

            Button {
                confettiTrigger &+= 1
            } label: {
                Label("撒一把彩带", systemImage: "sparkles")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .confettiCannon(
                trigger: $confettiTrigger,
                num: 60,
                radius: 340,
                hapticFeedback: false
            )

            Divider()
                .padding(.horizontal, 80)

            Button("检查更新") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
        .environmentObject(SparkleUpdaterController())
}
