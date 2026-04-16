import Testing

@testable import CodexPill

struct AppRuntimeEnvironmentTests {
    @Test
    func validationOutputSuppressesEmptyStatePrompt() {
        #expect(
            AppRuntimeEnvironment.shouldSuppressEmptyStatePrompt(
                environment: [MenuBarValidationConfiguration.outputPathEnvironmentKey: "/tmp/live-menu.json"]
            )
        )
    }

    @Test
    func explicitSuppressFlagAcceptsTruthyValues() {
        #expect(
            AppRuntimeEnvironment.shouldSuppressEmptyStatePrompt(
                environment: [AppRuntimeEnvironment.suppressEmptyStatePromptEnvironmentKey: "true"]
            )
        )
    }

    @Test
    func emptyEnvironmentKeepsPromptEnabled() {
        #expect(AppRuntimeEnvironment.shouldSuppressEmptyStatePrompt(environment: [:]) == false)
    }
}
