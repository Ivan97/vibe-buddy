import Foundation

@MainActor
final class SessionMessageLoader: ObservableObject {
    @Published private(set) var entries: [SessionEntry] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadError: String?

    private var currentTask: Task<Void, Never>?

    func load(_ summary: SessionSummary) {
        currentTask?.cancel()
        entries = []
        isLoading = true
        loadError = nil

        let url = summary.path
        currentTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Self.decode(url: url)
            }.value

            guard let self, !Task.isCancelled else { return }
            isLoading = false
            switch result {
            case .success(let list):
                entries = list
            case .failure(let error):
                loadError = (error as NSError).localizedDescription
            }
        }
    }

    nonisolated private static func decode(url: URL) -> Result<[SessionEntry], Error> {
        let decoder = SessionEntryDecoder()
        var out: [SessionEntry] = []
        do {
            try JSONLReader(url: url).forEachLine { line in
                if let entry = decoder.decode(line) {
                    out.append(entry)
                }
            }
            return .success(out)
        } catch {
            return .failure(error)
        }
    }
}
