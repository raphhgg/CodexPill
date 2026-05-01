import Foundation

enum PersistedAccountNotificationReason: String, Codable, Equatable {
    case whenBlocked
    case whenOut

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "whenBlocked":
            self = .whenBlocked
        case "whenOut", "beforeYouRunOut":
            self = .whenOut
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown persisted notification reason: \(rawValue)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct PersistedAccountNotificationWindow: Codable, Equatable {
    var sessionResetAt: Date?
    var weeklyResetAt: Date?
}

struct PersistedAccountNotificationRecord: Codable, Equatable {
    var reason: PersistedAccountNotificationReason
    var window: PersistedAccountNotificationWindow
    var notifiedAt: Date
}

struct PersistedAccountNotificationState: Codable, Equatable, Identifiable {
    var accountID: UUID
    var isArmed: Bool
    var lastNotification: PersistedAccountNotificationRecord?

    var id: UUID { accountID }

    init(
        accountID: UUID,
        isArmed: Bool = true,
        lastNotification: PersistedAccountNotificationRecord? = nil
    ) {
        self.accountID = accountID
        self.isArmed = isArmed
        self.lastNotification = lastNotification
    }
}
