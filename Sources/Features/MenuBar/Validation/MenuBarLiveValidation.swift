import Foundation

protocol MenuBarValidationSink: Sendable {
    func record(_ snapshot: MenuBarValidationSnapshot) throws
}

struct FileMenuBarValidationSink: MenuBarValidationSink {
    let outputURL: URL

    func record(_ snapshot: MenuBarValidationSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: outputURL, options: .atomic)
    }
}

enum MenuBarValidationConfiguration {
    static let outputPathEnvironmentKey = "CODEXPILL_VALIDATION_OUTPUT"

    static func makeSink(environment: [String: String] = ProcessInfo.processInfo.environment) -> MenuBarValidationSink? {
        guard let outputPath = environment[outputPathEnvironmentKey], !outputPath.isEmpty else {
            return nil
        }

        return FileMenuBarValidationSink(outputURL: URL(fileURLWithPath: outputPath))
    }
}
