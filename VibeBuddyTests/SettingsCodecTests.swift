import Foundation
import Testing
@testable import VibeBuddy

@Suite("SettingsCodec")
struct SettingsCodecTests {

    @Test("parses canonical settings.json keys")
    func parsesCanonical() {
        let raw: [String: Any] = [
            "model": "sonnet",
            "theme": "dark",
            "env": ["ANTHROPIC_BASE_URL": "https://api.example"],
            "includeCoAuthoredBy": false,
            "cleanupPeriodDays": 45,
            "verbose": true,
            "apiKeyHelper": "/usr/local/bin/key",
            "permissions": [
                "allow": ["Bash(npm test:*)", "Read(~/src/**)"],
                "deny": ["Bash(rm -rf *)"],
                "ask": []
            ]
        ]
        let settings = SettingsCodec.parse(raw)
        #expect(settings.model == "sonnet")
        #expect(settings.theme == "dark")
        #expect(settings.env == ["ANTHROPIC_BASE_URL": "https://api.example"])
        #expect(settings.includeCoAuthoredBy == false)
        #expect(settings.cleanupPeriodDays == 45)
        #expect(settings.verbose == true)
        #expect(settings.apiKeyHelper == "/usr/local/bin/key")
        #expect(settings.permissions.allow.count == 2)
        #expect(settings.permissions.deny == ["Bash(rm -rf *)"])
        #expect(settings.permissions.ask.isEmpty)
    }

    @Test("unknown top-level keys land in extras and survive round-trip")
    func extrasRoundTrip() throws {
        let raw: [String: Any] = [
            "model": "opus",
            "hooks": ["PostToolUse": []],
            "mcpServers": ["sentry": ["type": "http", "url": "https://x"]],
            "enabledPlugins": ["foo@bar": true],
            "statusLine": ["type": "command", "command": "/bin/date"],
            "somethingNew": 42
        ]
        let settings = SettingsCodec.parse(raw)
        #expect(settings.model == "opus")
        #expect(Set(settings.extras.keys) == ["hooks", "mcpServers", "enabledPlugins", "statusLine", "somethingNew"])

        let emitted = SettingsCodec.serialize(settings)
        #expect(emitted["model"] as? String == "opus")
        #expect(emitted["hooks"] != nil)
        #expect(emitted["mcpServers"] != nil)
        #expect(emitted["enabledPlugins"] != nil)
        #expect(emitted["statusLine"] != nil)
        #expect(emitted["somethingNew"] as? Int == 42)
    }

    @Test("unknown permission keys preserved on round-trip")
    func permissionExtrasPreserved() {
        let raw: [String: Any] = [
            "permissions": [
                "allow": ["Bash(ls)"],
                "defaultMode": "acceptEdits",
                "additionalDirectories": ["/tmp"]
            ]
        ]
        let settings = SettingsCodec.parse(raw)
        #expect(settings.permissions.allow == ["Bash(ls)"])
        #expect(settings.permissions.extras["defaultMode"] as? String == "acceptEdits")
        #expect(settings.permissions.extras["additionalDirectories"] as? [String] == ["/tmp"])

        let emitted = SettingsCodec.serialize(settings)
        let perms = try! #require(emitted["permissions"] as? [String: Any])
        #expect(perms["allow"] as? [String] == ["Bash(ls)"])
        #expect(perms["defaultMode"] as? String == "acceptEdits")
        #expect(perms["additionalDirectories"] as? [String] == ["/tmp"])
    }

    @Test("empty / nil typed fields are dropped from the emitted dict")
    func omitsEmpty() {
        let settings = ClaudeSettings.empty
        let emitted = SettingsCodec.serialize(settings)
        #expect(emitted.isEmpty)
    }

    @Test("typed keys win over extras on serialize")
    func typedKeysWin() {
        var settings = ClaudeSettings.empty
        settings.model = "haiku"
        settings.extras = ["model": "opus", "other": "keep"]
        let emitted = SettingsCodec.serialize(settings)
        #expect(emitted["model"] as? String == "haiku")
        #expect(emitted["other"] as? String == "keep")
    }

    @Test("dropping the model clears the key instead of writing empty string")
    func clearingModelDropsKey() {
        var settings = ClaudeSettings.empty
        settings.model = ""  // user cleared it via the picker's "Inherit"
        let emitted = SettingsCodec.serialize(settings)
        #expect(emitted["model"] == nil)
    }

    @Test("permissions with only extras still serializes them")
    func permissionExtrasAloneSerialize() {
        var settings = ClaudeSettings.empty
        settings.permissions.extras = ["defaultMode": "plan"]
        let emitted = SettingsCodec.serialize(settings)
        let perms = emitted["permissions"] as? [String: Any]
        #expect(perms?["defaultMode"] as? String == "plan")
    }
}
