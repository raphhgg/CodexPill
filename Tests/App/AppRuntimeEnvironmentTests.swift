import Foundation
import Testing

@testable import CodexPill

struct AppRuntimeEnvironmentTests {
    @Test
    func validationAutoRefreshIntervalSecondsParsesPositiveValues() {
        let environment = [
            AppRuntimeEnvironment.validationAutoRefreshIntervalSecondsEnvironmentKey: "2.5"
        ]

        #expect(AppRuntimeEnvironment.validationAutoRefreshIntervalSeconds(environment: environment) == 2.5)
    }

    @Test
    func validationAutoRefreshIntervalSecondsRejectsInvalidValues() {
        #expect(AppRuntimeEnvironment.validationAutoRefreshIntervalSeconds(environment: [:]) == nil)
        #expect(
            AppRuntimeEnvironment.validationAutoRefreshIntervalSeconds(
                environment: [AppRuntimeEnvironment.validationAutoRefreshIntervalSecondsEnvironmentKey: "0"]
            ) == nil
        )
        #expect(
            AppRuntimeEnvironment.validationAutoRefreshIntervalSeconds(
                environment: [AppRuntimeEnvironment.validationAutoRefreshIntervalSecondsEnvironmentKey: "abc"]
            ) == nil
        )
    }

    @Test
    func validationOverridesReadTrimmedPathsAndSuiteNames() {
        let environment = [
            AppRuntimeEnvironment.validationAppSupportDirectoryEnvironmentKey: " /tmp/codexpill-validation ",
            AppRuntimeEnvironment.validationUserDefaultsSuiteEnvironmentKey: " validation-suite ",
            AppRuntimeEnvironment.validationSettingsFixtureEnvironmentKey: " /tmp/settings.json "
        ]

        #expect(AppRuntimeEnvironment.validationAppSupportDirectory(environment: environment)?.path == "/tmp/codexpill-validation")
        #expect(AppRuntimeEnvironment.validationUserDefaultsSuiteName(environment: environment) == "validation-suite")
        #expect(AppRuntimeEnvironment.validationSettingsFixtureURL(environment: environment)?.path == "/tmp/settings.json")
    }

    @Test
    func inMemoryRemoteHostClientModeAcceptsExplicitTruthValues() {
        #expect(
            AppRuntimeEnvironment.shouldUseInMemoryRemoteHostClient(
                environment: [AppRuntimeEnvironment.validationInMemoryRemoteHostClientEnvironmentKey: "memory"]
            )
        )
        #expect(
            AppRuntimeEnvironment.shouldUseInMemoryRemoteHostClient(
                environment: [AppRuntimeEnvironment.validationInMemoryRemoteHostClientEnvironmentKey: "true"]
            )
        )
        #expect(
            !AppRuntimeEnvironment.shouldUseInMemoryRemoteHostClient(
                environment: [AppRuntimeEnvironment.validationInMemoryRemoteHostClientEnvironmentKey: "0"]
            )
        )
    }

    @Test
    func noopCodexProcessClientModeAcceptsExplicitTruthValues() {
        #expect(
            AppRuntimeEnvironment.shouldUseNoopCodexProcessClient(
                environment: [AppRuntimeEnvironment.validationNoopCodexProcessClientEnvironmentKey: "memory"]
            )
        )
        #expect(
            AppRuntimeEnvironment.shouldUseNoopCodexProcessClient(
                environment: [AppRuntimeEnvironment.validationNoopCodexProcessClientEnvironmentKey: "true"]
            )
        )
        #expect(
            !AppRuntimeEnvironment.shouldUseNoopCodexProcessClient(
                environment: [AppRuntimeEnvironment.validationNoopCodexProcessClientEnvironmentKey: "0"]
            )
        )
    }

    @Test
    func automatedTestEnvironmentIsDetectedFromXCTestConfigurationPath() {
        #expect(
            AppRuntimeEnvironment.isRunningAutomatedTests(
                environment: [AppRuntimeEnvironment.xctestConfigurationFilePathEnvironmentKey: "/tmp/test.xctestconfiguration"],
                classLookup: { _ in nil }
            )
        )
        #expect(
            !AppRuntimeEnvironment.isRunningAutomatedTests(
                environment: [:],
                classLookup: { _ in nil }
            )
        )
    }

    @Test
    func automatedTestEnvironmentIsDetectedFromLoadedXCTestRuntime() {
        #expect(
            AppRuntimeEnvironment.isRunningAutomatedTests(
                environment: [:],
                classLookup: { name in
                    name == "XCTestCase" ? NSObject.self : nil
                }
            )
        )
    }

    @Test
    func appRuntimeDoesNotStartInsideAutomatedTests() {
        #expect(
            !AppRuntimeEnvironment.shouldStartAppRuntime(
                environment: [AppRuntimeEnvironment.xctestConfigurationFilePathEnvironmentKey: "/tmp/test.xctestconfiguration"],
                classLookup: { _ in nil }
            )
        )
        #expect(
            AppRuntimeEnvironment.shouldStartAppRuntime(
                environment: [:],
                classLookup: { _ in nil }
            )
        )
    }

    @Test
    func interactiveAlertsAreSuppressedDuringAutomatedTests() {
        let environment = [
            AppRuntimeEnvironment.xctestConfigurationFilePathEnvironmentKey: "/tmp/test.xctestconfiguration"
        ]

        #expect(AppRuntimeEnvironment.shouldSuppressInteractiveAlerts(environment: environment))
    }

    @Test
    func validationInteractiveAlertOverrideDoesNotBypassAutomatedTests() {
        let environment = [
            AppRuntimeEnvironment.validationAllowInteractiveAlertsEnvironmentKey: "true",
            AppRuntimeEnvironment.xctestConfigurationFilePathEnvironmentKey: "/tmp/test.xctestconfiguration"
        ]

        #expect(
            AppRuntimeEnvironment.shouldSuppressInteractiveAlerts(
                environment: environment,
                classLookup: { _ in nil }
            )
        )
    }

    @Test
    func validationInteractiveAlertOverrideAllowsNonXCTestLiveSmokeLaunches() {
        let environment = [
            AppRuntimeEnvironment.validationAllowInteractiveAlertsEnvironmentKey: "true",
            MenuBarValidationConfiguration.outputPathEnvironmentKey: "/tmp/codexpill-runtime-menu.json"
        ]

        #expect(
            !AppRuntimeEnvironment.shouldSuppressInteractiveAlerts(
                environment: environment,
                classLookup: { _ in nil }
            )
        )
    }

    @Test
    func scenarioFixtureFactoryLivesInProductValidationAdapter() throws {
        let root = try repositoryRoot()
        let productFixture = root
            .appendingPathComponent("Sources/Features/MenuBar/Validation/MenuBarValidationScenarioFixtures.swift")
        let testFixture = root
            .appendingPathComponent("Tests/MenuBar/MenuBarValidationScenarioFixtures.swift")

        #expect(FileManager.default.fileExists(atPath: productFixture.path))
        #expect(!FileManager.default.fileExists(atPath: testFixture.path))
    }

    @Test
    func swiftUIPresentationDoesNotReadValidationScenarioEnvironment() throws {
        let root = try repositoryRoot()
        let searchedDirectories = [
            root.appendingPathComponent("Sources/Features/MenuBar/Alert"),
            root.appendingPathComponent("Sources/Features/MenuBar/Presentation")
        ]
        let forbiddenFragments = [
            "CODEXPILL_VALIDATION_SCENARIO",
            "MenuBarValidationConfiguration.scenario(",
            "remote-host-add-panel-validation",
            "menu-empty-catalog",
            "token-usage-ready-card",
            "token-usage-loading-progress"
        ]

        for fileURL in try swiftSourceFiles(in: searchedDirectories) {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            for fragment in forbiddenFragments {
                #expect(
                    !contents.contains(fragment),
                    "\(fileURL.path) should render from injected state instead of branching on validation scenario '\(fragment)'"
                )
            }
        }
    }

    private func repositoryRoot(filePath: String = #filePath) throws -> URL {
        var directory = URL(fileURLWithPath: filePath).deletingLastPathComponent()

        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Makefile").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }

        throw AppRuntimeEnvironmentTestError.repositoryRootNotFound
    }

    private func swiftSourceFiles(in directories: [URL]) throws -> [URL] {
        try directories.flatMap { directory in
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                return [URL]()
            }

            var files: [URL] = []
            for item in enumerator {
                guard let fileURL = item as? URL else { continue }
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard resourceValues.isRegularFile == true,
                      fileURL.pathExtension == "swift" else {
                    continue
                }
                files.append(fileURL)
            }
            return files
        }
    }
}

private enum AppRuntimeEnvironmentTestError: Error {
    case repositoryRootNotFound
}
