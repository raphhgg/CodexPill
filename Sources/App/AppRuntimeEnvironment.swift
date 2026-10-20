import Foundation

enum AppRuntimeEnvironment {
    static let isolatedAppSupportDirectoryEnvironmentKey = "RUSAGE_ISOLATED_APP_SUPPORT_DIR"
    static let isolatedDefaultsSuiteEnvironmentKey = "RUSAGE_ISOLATED_DEFAULTS_SUITE"
    static let xctestConfigurationFilePathEnvironmentKey = "XCTestConfigurationFilePath"

    static func isolatedDefaultsSuiteName(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        trimmedValue(for: isolatedDefaultsSuiteEnvironmentKey, environment: environment)
    }

    static func isRunningAutomatedTests(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        classLookup: (String) -> AnyClass? = NSClassFromString
    ) -> Bool {
        if let rawValue = environment[xctestConfigurationFilePathEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !rawValue.isEmpty {
            return true
        }

        // Launched app-host processes do not always inherit XCTestConfigurationFilePath,
        // but they still load XCTest runtime classes while the test bundle is injected.
        return classLookup("XCTestCase") != nil || classLookup("XCTest") != nil
    }

    static func isolatedAppSupportDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let launchDirectory = trimmedValue(for: isolatedAppSupportDirectoryEnvironmentKey, environment: environment) {
            return URL(fileURLWithPath: launchDirectory)
        }
        guard isRunningAutomatedTests(environment: environment) else { return nil }

        return FileManager.default.temporaryDirectory
            .appendingPathComponent("rusageTests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    }

    static func shouldStartAppRuntime(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        classLookup: (String) -> AnyClass? = NSClassFromString
    ) -> Bool {
        !isRunningAutomatedTests(environment: environment, classLookup: classLookup)
    }

    private static func trimmedValue(
        for key: String,
        environment: [String: String]
    ) -> String? {
        guard let rawValue = environment[key]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }

        return rawValue
    }
}
