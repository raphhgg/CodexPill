import Foundation
import Testing

/// Core holds models and typed preferences, and Platform talks to the system. Neither may depend on a feature.
struct LayerBoundaryTests {
    @Test
    func coreAndPlatformNeverReferenceANameDeclaredInFeatures() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let featureFiles = try Self.swiftFiles(in: sources.appendingPathComponent("Features"))
        let lowerFiles = try Self.swiftFiles(in: sources.appendingPathComponent("Core"))
            + Self.swiftFiles(in: sources.appendingPathComponent("Platform"))
        #expect(featureFiles.count > 20)
        #expect(lowerFiles.count > 20)

        let lowerDeclarations = try Set(lowerFiles.flatMap { try Self.declaredNames(in: Self.code(of: $0)) })
        let featureNames = try Set(featureFiles.flatMap { try Self.declaredNames(in: Self.code(of: $0)) })
            .subtracting(lowerDeclarations)

        var violations: [String] = []
        for file in lowerFiles {
            let used = Self.identifiers(in: try Self.code(of: file)).intersection(featureNames)
            violations += used.sorted().map { "\(file.lastPathComponent) uses \($0)" }
        }
        #expect(violations == [])
    }

    private static func swiftFiles(in directory: URL) throws -> [URL] {
        let enumerator = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// The file without comments and string literals, so prose never counts as a reference.
    private static func code(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
            .replacing(#/"""[\s\S]*?"""/#, with: "\"\"")
            .replacing(#//\*[\s\S]*?\*//#, with: "")
            .replacing(#///[^\n]*/#, with: "")
            .replacing(#/"(?:\\.|[^"\\\n])*"/#, with: "\"\"")
    }

    /// Types and top-level functions another file could use. Private declarations can't be used elsewhere.
    private static func declaredNames(in code: String) -> [String] {
        let type = #/(?m)^[ \t]*(?:@\w+(?:\([^)\n]*\))?\s+)*(?:(?:public|internal|package|final|nonisolated|indirect)\s+)*(?:class|struct|enum|protocol|actor|typealias)\s+([A-Z]\w*)/#
        let function = #/(?m)^(?:@\w+\s+)*(?:(?:public|internal|package|nonisolated)\s+)*func\s+(\w+)/#
        return code.matches(of: type).map { String($0.output.1) } + code.matches(of: function).map { String($0.output.1) }
    }

    private static func identifiers(in code: String) -> Set<String> {
        Set(code.matches(of: #/[A-Za-z_]\w*/#).map { String($0.output) })
    }
}
