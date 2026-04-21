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
        #expect(
            paths.codexAuthFile.standardizedFileURL.path
                == overrideDirectory
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("auth.json")
                .standardizedFileURL.path
        )
    }

    @Test
    func automatedTestsDefaultToTemporaryApplicationSupportLocation() throws {
        let paths = try AppPaths(
            fileManager: .default,
            environment: [AppRuntimeEnvironment.xctestConfigurationFilePathEnvironmentKey: "/tmp/test.xctestconfiguration"]
        )

        let expectedDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPillTests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        #expect(normalizedDirectoryPath(paths.appSupportDirectory) == normalizedDirectoryPath(expectedDirectory))
        #expect(paths.accountsFile.standardizedFileURL.path == expectedDirectory.appendingPathComponent("accounts.json").standardizedFileURL.path)
        #expect(
            paths.codexAuthFile.standardizedFileURL.path
                == expectedDirectory
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("auth.json")
                .standardizedFileURL.path
        )
    }

    private func normalizedDirectoryPath(_ url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
