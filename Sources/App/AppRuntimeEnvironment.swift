import Foundation

enum AppRuntimeEnvironment {
    static let suppressEmptyStatePromptEnvironmentKey = "CODEXPILL_SUPPRESS_EMPTY_STATE_PROMPT"
    static let validationAutoRefreshIntervalSecondsEnvironmentKey = "CODEXPILL_VALIDATION_AUTO_REFRESH_INTERVAL_SECONDS"
    static let validationAppSupportDirectoryEnvironmentKey = "CODEXPILL_VALIDATION_APP_SUPPORT_DIR"
    static let validationUserDefaultsSuiteEnvironmentKey = "CODEXPILL_VALIDATION_USER_DEFAULTS_SUITE"
    static let validationSettingsFixtureEnvironmentKey = "CODEXPILL_VALIDATION_SETTINGS_FIXTURE"
    static let validationRemoteHostClientEnvironmentKey = "CODEXPILL_VALIDATION_REMOTE_HOST_CLIENT"
    static let xctestConfigurationFilePathEnvironmentKey = "XCTestConfigurationFilePath"

    static func shouldSuppressEmptyStatePrompt(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if let rawValue = environment[suppressEmptyStatePromptEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           ["1", "true", "yes"].contains(rawValue) {
            return true
        }

        return MenuBarValidationConfiguration.makeSink(environment: environment) != nil
    }

    static func validationAutoRefreshIntervalSeconds(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TimeInterval? {
        guard let rawValue = environment[validationAutoRefreshIntervalSecondsEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let seconds = TimeInterval(rawValue),
              seconds > 0 else {
            return nil
        }

        return seconds
    }

    static func validationAppSupportDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        trimmedURLValue(for: validationAppSupportDirectoryEnvironmentKey, environment: environment)
            .map(URL.init(fileURLWithPath:))
    }

    static func validationUserDefaultsSuiteName(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        trimmedURLValue(for: validationUserDefaultsSuiteEnvironmentKey, environment: environment)
    }

    static func validationSettingsFixtureURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        trimmedURLValue(for: validationSettingsFixtureEnvironmentKey, environment: environment)
            .map(URL.init(fileURLWithPath:))
    }

    static func shouldUseValidationRemoteHostClient(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if let rawValue = environment[validationRemoteHostClientEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           ["1", "true", "yes", "memory"].contains(rawValue) {
            return true
        }

        return false
    }

    static func isRunningAutomatedTests(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard let rawValue = environment[xctestConfigurationFilePathEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }

        return !rawValue.isEmpty
    }

    static func automatedTestAppSupportDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard isRunningAutomatedTests(environment: environment) else { return nil }

        return FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPillTests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    }

    static func shouldSuppressInteractiveAlerts(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        isRunningAutomatedTests(environment: environment) || MenuBarValidationConfiguration.makeSink(environment: environment) != nil
    }

    private static func trimmedURLValue(
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
