import Foundation
import Testing

@testable import CodexPill

struct ValidationBoundaryTests {
    @Test
    func validationFeatureDoesNotImportPresentationOrMenuBarTypes() throws {
        let featuresDirectory = try #require(featuresSourceDirectory(from: #filePath))
        let swiftFiles = validationSwiftFiles(in: featuresDirectory)

        #expect(!swiftFiles.isEmpty)

        for file in swiftFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.contains("import AppKit"), "Validation source must not import AppKit: \(file.lastPathComponent)")
            #expect(!source.contains("import SwiftUI"), "Validation source must not import SwiftUI: \(file.lastPathComponent)")
            #expect(!source.contains("MenuBarValidationSnapshot"), "Validation source must not depend on MenuBar snapshots: \(file.lastPathComponent)")
            #expect(!source.contains("MenuBarValidationSupport"), "Validation source must not depend on MenuBar snapshot support: \(file.lastPathComponent)")
            #expect(!source.contains("MenuBarValidationConfiguration"), "Validation source must not depend on MenuBar validation configuration: \(file.lastPathComponent)")
        }
    }

    private func featuresSourceDirectory(from testFilePath: String) -> URL? {
        var directory = URL(fileURLWithPath: testFilePath).deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appendingPathComponent("Sources/Features", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }

    private func validationSwiftFiles(in featuresSourceDirectory: URL) -> [URL] {
        [
            featuresSourceDirectory.appendingPathComponent("Validation", isDirectory: true),
            featuresSourceDirectory.appendingPathComponent("Accounts/Validation", isDirectory: true),
            featuresSourceDirectory.appendingPathComponent("Hosts/Validation", isDirectory: true),
        ].flatMap(swiftFiles(in:))
            .sorted { $0.path < $1.path }
    }

    private func swiftFiles(in directory: URL) -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        )
        return enumerator?.compactMap { item -> URL? in
            guard let url = item as? URL, url.pathExtension == "swift" else {
                return nil
            }
            return url
        } ?? []
    }
}
