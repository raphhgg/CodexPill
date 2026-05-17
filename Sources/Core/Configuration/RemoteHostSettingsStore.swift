import Foundation
import Observation

@MainActor
@Observable
final class RemoteHostSettingsStore {
    var remoteHostStates: [PersistedRemoteHostState] {
        didSet {
            persistCodable(remoteHostStates, key: Self.remoteHostsKey)
        }
    }

    private let userDefaults: UserDefaults

    private static let remoteHostsKey = "remoteHosts"
    private static let remoteHostKey = "remoteHost"
    private static let remoteHostInstalledAccountIDsKey = "remoteHostInstalledAccountIDs"
    private static let remoteHostActiveAccountKey = "remoteHostActiveAccount"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if userDefaults.object(forKey: Self.remoteHostsKey) != nil {
            remoteHostStates = Self.loadCodable(from: userDefaults, key: Self.remoteHostsKey) ?? []
            Self.removeLegacyRemoteHostKeys(from: userDefaults)
        } else {
            remoteHostStates = Self.loadLegacyRemoteHostStates(from: userDefaults)
            persistCodable(remoteHostStates, key: Self.remoteHostsKey)
            Self.removeLegacyRemoteHostKeys(from: userDefaults)
        }
    }

    var configuredRemoteHost: RemoteHost? {
        get { remoteHostStates.first?.host }
        set {
            if let newValue {
                upsertRemoteHost(newValue)
            } else if let first = remoteHostStates.first {
                removeRemoteHost(destination: first.host.destination)
            }
        }
    }

    var remoteHostInstalledAccountIDs: [UUID] {
        get { remoteHostStates.first?.installedAccountIDs ?? [] }
        set {
            guard let host = remoteHostStates.first?.host else { return }
            updateRemoteHostState(for: host) { state in
                state.installedAccountIDs = newValue
            }
        }
    }

    var remoteHostActiveAccount: CodexAccount? {
        get { remoteHostStates.first?.verifiedAccount }
        set {
            guard let host = remoteHostStates.first?.host else { return }
            updateRemoteHostState(for: host) { state in
                state.verifiedAccount = newValue
                state.detectedAccountID = nil
                state.verificationStatus = newValue == nil ? .unverified : .verified
                state.lastVerificationError = nil
                if state.desiredAccountID == nil {
                    state.desiredAccountID = newValue?.id
                }
            }
        }
    }

    var remoteHostDesiredAccountID: UUID? {
        get { remoteHostStates.first?.desiredAccountID }
        set {
            guard let host = remoteHostStates.first?.host else { return }
            updateRemoteHostState(for: host) { state in
                state.desiredAccountID = newValue
            }
        }
    }

    func upsertRemoteHost(_ host: RemoteHost) {
        updateRemoteHostState(for: host) { _ in }
    }

    func removeRemoteHost(destination: String) {
        remoteHostStates.removeAll { $0.host.destination == destination }
        Self.removeLegacyRemoteHostKeys(from: userDefaults)
    }

    func remoteHostState(for destination: String) -> PersistedRemoteHostState? {
        remoteHostStates.first(where: { $0.host.destination == destination })
    }

    func updateRemoteHostState(for host: RemoteHost, mutate: (inout PersistedRemoteHostState) -> Void) {
        if let index = remoteHostStates.firstIndex(where: { $0.host.destination == host.destination }) {
            var updated = remoteHostStates[index]
            updated.host = host
            mutate(&updated)
            remoteHostStates[index] = updated
            return
        }

        var state = PersistedRemoteHostState(host: host)
        mutate(&state)
        remoteHostStates.append(state)
        remoteHostStates.sort { $0.host.displayName.localizedCaseInsensitiveCompare($1.host.displayName) == .orderedAscending }
    }

    private func persistCodable<T: Codable>(_ value: T?, key: String) {
        guard let value else {
            userDefaults.removeObject(forKey: key)
            return
        }

        if let data = try? JSONEncoder().encode(value) {
            userDefaults.set(data, forKey: key)
        }
    }

    private static func loadCodable<T: Codable>(from userDefaults: UserDefaults, key: String) -> T? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func loadLegacyRemoteHostStates(from userDefaults: UserDefaults) -> [PersistedRemoteHostState] {
        guard let host: RemoteHost = loadCodable(from: userDefaults, key: Self.remoteHostKey) else {
            return []
        }

        let installedAccountIDs: [UUID] = loadCodable(from: userDefaults, key: Self.remoteHostInstalledAccountIDsKey) ?? []
        let activeAccount: CodexAccount? = loadCodable(from: userDefaults, key: Self.remoteHostActiveAccountKey)
        return [
            PersistedRemoteHostState(
                host: host,
                installedAccountIDs: installedAccountIDs,
                desiredAccountID: activeAccount?.id,
                verifiedAccount: nil,
                verificationStatus: .unverified
            )
        ]
    }

    private static func removeLegacyRemoteHostKeys(from userDefaults: UserDefaults) {
        userDefaults.removeObject(forKey: Self.remoteHostKey)
        userDefaults.removeObject(forKey: Self.remoteHostInstalledAccountIDsKey)
        userDefaults.removeObject(forKey: Self.remoteHostActiveAccountKey)
    }
}
