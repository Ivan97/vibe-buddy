import Foundation

extension HooksConfig {
    /// Drops events with no matcher groups and matcher groups with no
    /// commands. Called right before save so the UI can let users add
    /// empty scaffolding while editing without polluting settings.json.
    func pruned() -> HooksConfig {
        HooksConfig(events: events.compactMap { event in
            let kept = event.matchers.filter { !$0.commands.isEmpty }
            guard !kept.isEmpty else { return nil }
            return HookEvent(name: event.name, matchers: kept)
        })
    }
}
