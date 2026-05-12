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

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fixtureURL),
              let fixture = try? decoder.decode(ValidationAppBootstrapFixture.self, from: data) else {
            return
        }

        settings.remoteHostStates = fixture.remoteHostStates
    }
}
