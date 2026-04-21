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
    func validationRemoteHostClientModeAcceptsExplicitTruthValues() {
        #expect(
            AppRuntimeEnvironment.shouldUseValidationRemoteHostClient(
                environment: [AppRuntimeEnvironment.validationRemoteHostClientEnvironmentKey: "memory"]
            )
        )
        #expect(
            AppRuntimeEnvironment.shouldUseValidationRemoteHostClient(
                environment: [AppRuntimeEnvironment.validationRemoteHostClientEnvironmentKey: "true"]
            )
        )
        #expect(
            !AppRuntimeEnvironment.shouldUseValidationRemoteHostClient(
                environment: [AppRuntimeEnvironment.validationRemoteHostClientEnvironmentKey: "0"]
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
    func interactiveAlertsAreSuppressedDuringAutomatedTests() {
        let environment = [
            AppRuntimeEnvironment.xctestConfigurationFilePathEnvironmentKey: "/tmp/test.xctestconfiguration"
        ]

        #expect(AppRuntimeEnvironment.shouldSuppressInteractiveAlerts(environment: environment))
    }
}
