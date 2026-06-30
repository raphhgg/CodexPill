import Foundation

struct ValidationFixtureBootstrapPayload: Codable {
    let remoteHostStates: [PersistedRemoteHostState]
}

enum ValidationFixtureBootstrap {
    @MainActor
    static func applyFixtureIfPresent(
        to settings: CodexPillSettingsStore,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard let fixtureURL = AppRuntimeEnvironment.validationSettingsFixtureURL(environment: environment) else {
            return
        }

        guard let data = try? Data(contentsOf: fixtureURL),
              let fixture = try? JSONDecoder().decode(ValidationFixtureBootstrapPayload.self, from: data) else {
            return
        }

        settings.remoteHostStates = fixture.remoteHostStates
    }
}
