import Foundation
import Observation

@MainActor
@Observable
final class NotificationStateStore {
    var accountNotificationStates: [PersistedAccountNotificationState] {
        didSet {
            persistCodable(accountNotificationStates, key: Self.accountNotificationStatesKey)
        }
    }

    private let userDefaults: UserDefaults

    private static let accountNotificationStatesKey = "accountNotificationStates"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        accountNotificationStates = Self.loadCodable(from: userDefaults, key: Self.accountNotificationStatesKey) ?? []
    }

    func accountNotificationState(for accountID: UUID) -> PersistedAccountNotificationState? {
        accountNotificationStates.first(where: { $0.accountID == accountID })
    }

    func updateAccountNotificationState(
        for accountID: UUID,
        mutate: (inout PersistedAccountNotificationState) -> Void
    ) {
        if let index = accountNotificationStates.firstIndex(where: { $0.accountID == accountID }) {
            var updated = accountNotificationStates[index]
            mutate(&updated)
            accountNotificationStates[index] = updated
            return
        }

        var state = PersistedAccountNotificationState(accountID: accountID)
        mutate(&state)
        accountNotificationStates.append(state)
        accountNotificationStates.sort { $0.accountID.uuidString < $1.accountID.uuidString }
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
}
