import Foundation
import Testing

@testable import CodexPill

struct AppRuntimeEnvironmentTests {
    @MainActor
    @Test
    func validationAppBootstrapLoadsRemoteHostFixturesWithVerifiedAccounts() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ValidationAppBootstrapTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fixtureURL = directory.appendingPathComponent("settings.json")
        let accountID = UUID()
        let payload = """
        {
          "remoteHostStates": [
            {
              "host": {
                "destination": "demo@buildbox.example",
                "displayName": "buildbox"
              },
              "installedAccountIDs": ["\(accountID.uuidString)"],
              "desiredAccountID": "\(accountID.uuidString)",
              "verifiedAccount": {
                "id": "\(accountID.uuidString)",
                "name": "Build Farm",
                "snapshotFileName": "build-farm.json",
                "createdAt": "2026-05-11T09:00:00Z",
                "updatedAt": "2026-05-11T09:01:00Z",
                "email": "buildfarm@example.com",
                "planType": "team",
                "rateLimits": null,
                "identity": {
                  "stableAccountID": "demo-build-farm",
                  "authPrincipalIdentity": null,
                  "workspaceIdentity": null,
                  "snapshotFingerprint": "demo-fingerprint",
                  "remoteIdentity": {
                    "normalizedEmailAddress": "buildfarm@example.com"
                  }
                }
              },
              "detectedAccountID": null,
              "verificationStatus": "verified",
              "lastVerificationError": null
            }
          ]
        }
        """
        try payload.write(to: fixtureURL, atomically: true, encoding: .utf8)

        let suiteName = "ValidationAppBootstrapTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = CodexPillSettingsStore(userDefaults: defaults)
        ValidationAppBootstrap.applyFixtureIfPresent(
            to: settings,
            environment: [AppRuntimeEnvironment.validationSettingsFixtureEnvironmentKey: fixtureURL.path]
        )

        #expect(settings.remoteHostStates.count == 1)
        #expect(settings.remoteHostStates.first?.host.displayName == "buildbox")
        #expect(settings.remoteHostStates.first?.verifiedAccount?.name == "Build Farm")
        #expect(settings.remoteHostStates.first?.verificationStatus == .verified)
    }

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
    func validationAccountStatusClientModeAcceptsExplicitTruthValues() {
        #expect(
            AppRuntimeEnvironment.shouldUseValidationAccountStatusClient(
                environment: [AppRuntimeEnvironment.validationAccountStatusClientEnvironmentKey: "memory"]
            )
        )
        #expect(
            AppRuntimeEnvironment.shouldUseValidationAccountStatusClient(
                environment: [AppRuntimeEnvironment.validationAccountStatusClientEnvironmentKey: "true"]
            )
        )
        #expect(
            !AppRuntimeEnvironment.shouldUseValidationAccountStatusClient(
                environment: [AppRuntimeEnvironment.validationAccountStatusClientEnvironmentKey: "0"]
            )
        )
    }

    @Test
    func validationCodexProcessClientModeAcceptsExplicitTruthValues() {
        #expect(
            AppRuntimeEnvironment.shouldUseValidationCodexProcessClient(
                environment: [AppRuntimeEnvironment.validationCodexProcessClientEnvironmentKey: "memory"]
            )
        )
        #expect(
            AppRuntimeEnvironment.shouldUseValidationCodexProcessClient(
                environment: [AppRuntimeEnvironment.validationCodexProcessClientEnvironmentKey: "true"]
            )
        )
        #expect(
            !AppRuntimeEnvironment.shouldUseValidationCodexProcessClient(
                environment: [AppRuntimeEnvironment.validationCodexProcessClientEnvironmentKey: "0"]
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
            MenuBarValidationConfiguration.outputPathEnvironmentKey: "/tmp/codexpill-live-menu.json"
        ]

        #expect(
            !AppRuntimeEnvironment.shouldSuppressInteractiveAlerts(
                environment: environment,
                classLookup: { _ in nil }
            )
        )
    }
}
