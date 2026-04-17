import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var summaries: [SessionSummary] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadError: String?

    let claudeHome: ClaudeHome
    private let summaryBuilder: SessionSummaryBuilder

    init(
        claudeHome: ClaudeHome = .discover(),
        summaryBuilder: SessionSummaryBuilder = SessionSummaryBuilder()
    ) {
        self.claudeHome = claudeHome
        self.summaryBuilder = summaryBuilder
    }

    func reload() async {
        isLoading = true
        loadError = nil

        let home = claudeHome
        let builder = summaryBuilder

        let result: Result<[SessionSummary], Error> = await Task.detached(priority: .userInitiated) {
            do {
                let summaries = try SessionStore.scan(home: home, builder: builder)
                return .success(summaries)
            } catch {
                return .failure(error)
            }
        }.value

        isLoading = false
        switch result {
        case .success(let list):
            summaries = list
        case .failure(let error):
            loadError = Self.humanReadable(error)
        }
    }

    nonisolated private static func scan(home: ClaudeHome, builder: SessionSummaryBuilder) throws -> [SessionSummary] {
        let fm = FileManager.default
        let projectsDir = home.projectsDir
        guard fm.fileExists(atPath: projectsDir.path) else { return [] }

        let projectDirs = try fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

        var summaries: [SessionSummary] = []
        for dir in projectDirs {
            let files = (try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for file in files where file.pathExtension == "jsonl" {
                if let summary = try? builder.build(from: file, slug: dir.lastPathComponent) {
                    summaries.append(summary)
                }
            }
        }

        return summaries.sorted { $0.lastActivity > $1.lastActivity }
    }

    nonisolated private static func humanReadable(_ error: Error) -> String {
        let nsError = error as NSError
        return nsError.localizedDescription
    }
}
