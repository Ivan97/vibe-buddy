import SwiftUI

struct MenuBarScene: Scene {
    @ObservedObject var updater: SparkleUpdaterController
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var navigator: Navigator

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(
                updater: updater,
                sessionStore: sessionStore,
                navigator: navigator
            )
        } label: {
            Image(systemName: "sparkles")
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarPopover: View {
    @ObservedObject var updater: SparkleUpdaterController
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var navigator: Navigator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if sessionStore.summaries.isEmpty {
                ContentUnavailableView(
                    sessionStore.isLoading ? "Loading sessions…" : "No sessions yet",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Run Claude Code in any project to start recording sessions.")
                )
                .frame(minHeight: 160)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(sessionStore.summaries.prefix(5))) { summary in
                            RecentSessionRow(summary: summary) {
                                openSession(summary.id)
                            }
                        }
                    }
                }
                .frame(maxHeight: 260)
            }

            Divider()
            footer
        }
        .frame(width: 360)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
            Text("Recent Sessions")
                .font(.headline)
            Spacer()
            if sessionStore.isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        VStack(spacing: 2) {
            menuRow(
                title: "Open VibeBuddy",
                systemImage: "macwindow",
                shortcut: "⌘O"
            ) {
                openMainWindow()
            }

            menuRow(
                title: "Check for Updates…",
                systemImage: "arrow.down.circle",
                shortcut: nil,
                disabled: !updater.canCheckForUpdates
            ) {
                updater.checkForUpdates()
            }

            menuRow(
                title: "Quit VibeBuddy",
                systemImage: "power",
                shortcut: "⌘Q"
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(6)
    }

    private func menuRow(
        title: String,
        systemImage: String,
        shortcut: String?,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
        .disabled(disabled)
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: MainWindowScene.windowID)
        dismiss()
    }

    private func openSession(_ id: SessionSummary.ID) {
        navigator.openSession(id: id)
        openMainWindow()
    }
}

private struct RecentSessionRow: View {
    let summary: SessionSummary
    let onOpen: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.firstPrompt ?? "(no prompt)")
                        .lineLimit(1)
                        .font(.callout)
                    HStack(spacing: 4) {
                        Text(projectName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("·")
                        Text(summary.lastActivity, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(hovered ? Color.accentColor.opacity(0.18) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    private var projectName: String {
        let last = URL(fileURLWithPath: summary.projectPath).lastPathComponent
        return last.isEmpty ? summary.projectPath : last
    }
}

private struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? Color.accentColor.opacity(0.25)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
    }
}
