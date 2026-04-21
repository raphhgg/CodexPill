import Foundation
import Testing

@testable import CodexPill

struct AppPathsTests {
    @Test
    func validationAppSupportDirectoryOverrideBypassesDefaultApplicationSupportLocation() throws {
        let overrideDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = try AppPaths(
            fileManager: .default,
            environment: [AppRuntimeEnvironment.validationAppSupportDirectoryEnvironmentKey: overrideDirectory.path]
        )

        #expect(normalizedDirectoryPath(paths.appSupportDirectory) == normalizedDirectoryPath(overrideDirectory))
        #expect(
            paths.accountsFile.standardizedFileURL.path
                == overrideDirectory.appendingPathComponent("accounts.json").standardizedFileURL.path
        )
        #expect(
            normalizedDirectoryPath(paths.snapshotsDirectory)
                == normalizedDirectoryPath(overrideDirectory.appendingPathComponent("snapshots", isDirectory: true))
        )
    }

    private func normalizedDirectoryPath(_ url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
