import Foundation
import Testing

@testable import rusage

struct AppRuntimeEnvironmentTests {
    @Test
    func isolatedLaunchReadsTrimmedDirectoryAndDefaultsSuite() {
        let environment = [
            AppRuntimeEnvironment.isolatedAppSupportDirectoryEnvironmentKey: " /tmp/rusage-isolated ",
            AppRuntimeEnvironment.isolatedDefaultsSuiteEnvironmentKey: " isolated-suite "
        ]

        #expect(AppRuntimeEnvironment.isolatedAppSupportDirectory(environment: environment)?.path == "/tmp/rusage-isolated")
        #expect(AppRuntimeEnvironment.isolatedDefaultsSuiteName(environment: environment) == "isolated-suite")
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
    func isolatedAppSupportDirectoryPrefersIsolatedLaunchThenAutomatedTestDirectory() {
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rusageTests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)

        #expect(
            AppRuntimeEnvironment.isolatedAppSupportDirectory(
                environment: [AppRuntimeEnvironment.isolatedAppSupportDirectoryEnvironmentKey: "/tmp/rusage-isolated"]
            )?.path == "/tmp/rusage-isolated"
        )
        #expect(
            AppRuntimeEnvironment.isolatedAppSupportDirectory(
                environment: [AppRuntimeEnvironment.xctestConfigurationFilePathEnvironmentKey: "/tmp/test.xctestconfiguration"]
            )?.standardizedFileURL.path == testDirectory.standardizedFileURL.path
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
}
