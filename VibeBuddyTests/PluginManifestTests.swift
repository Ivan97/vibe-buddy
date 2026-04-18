import Foundation
import Testing
@testable import VibeBuddy

@Suite("PluginManifestParser")
struct PluginManifestTests {

    @Test("parses basic manifest fields")
    func basic() throws {
        let data = #"""
        {
          "name": "example",
          "version": "1.2.3",
          "description": "Demo plugin",
          "license": "MIT"
        }
        """#.data(using: .utf8)!
        let manifest = try PluginManifestParser.parse(data: data)
        #expect(manifest.name == "example")
        #expect(manifest.version == "1.2.3")
        #expect(manifest.description == "Demo plugin")
        #expect(manifest.license == "MIT")
    }

    @Test("object-form author is flattened to 'name <email>'")
    func authorObject() throws {
        let data = #"""
        {
          "name": "x",
          "author": {"name": "Ada", "email": "ada@example.com"}
        }
        """#.data(using: .utf8)!
        let manifest = try PluginManifestParser.parse(data: data)
        #expect(manifest.author == "Ada <ada@example.com>")
    }

    @Test("string-form author passes through")
    func authorString() throws {
        let data = #"""
        {"name": "x", "author": "Ada"}
        """#.data(using: .utf8)!
        let manifest = try PluginManifestParser.parse(data: data)
        #expect(manifest.author == "Ada")
    }

    @Test("unknown keys land in extras")
    func extras() throws {
        let data = #"""
        {
          "name": "x",
          "strict": false,
          "custom-field": "hello"
        }
        """#.data(using: .utf8)!
        let manifest = try PluginManifestParser.parse(data: data)
        #expect(manifest.extras["strict"] == "false")
        #expect(manifest.extras["custom-field"] == "hello")
    }

    @Test("non-object root throws")
    func nonObjectRoot() {
        let data = "[1,2,3]".data(using: .utf8)!
        #expect(throws: Error.self) { try PluginManifestParser.parse(data: data) }
    }
}
