import Foundation

enum AppRuntimeEnvironment {
    static let suppressEmptyStatePromptEnvironmentKey = "CODEXPILL_SUPPRESS_EMPTY_STATE_PROMPT"

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
}
