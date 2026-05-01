import Foundation

struct ValidationAppBootstrapFixture: Codable {
    let remoteHostStates: [PersistedRemoteHostState]
}

enum ValidationAppBootstrap {
    @MainActor
    static func applyFixtureIfPresent(
        to settings: CodexPillSettingsStore,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard let fixtureURL = AppRuntimeEnvironment.validationSettingsFixtureURL(environment: environment) else {
            return
        }

        guard let data = try? Data(contentsOf: fixtureURL),
              let fixture = try? JSONDecoder().decode(ValidationAppBootstrapFixture.self, from: data) else {
            return
        }

        settings.remoteHostStates = fixture.remoteHostStates
    }
}
