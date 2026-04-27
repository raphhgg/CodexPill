import Foundation

struct RemoteHost: Codable, Equatable {
    let destination: String
    let displayName: String

    init(destination: String, displayName: String? = nil) {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.destination = trimmed
        self.displayName = (trimmedDisplayName?.isEmpty == false ? trimmedDisplayName : nil) ?? Self.defaultDisplayName(for: trimmed)
    }

    private static func defaultDisplayName(for destination: String) -> String {
        guard let hostComponent = destination.split(separator: "@").last else {
            return destination
        }
        return String(hostComponent)
    }
}

enum RemoteHostAccountInstallationState: String, Codable, Equatable {
    case installed
    case missing
}

protocol RemoteHostClient {
    func testConnection(to host: RemoteHost) async throws
    func installationState(for account: CodexAccount, on host: RemoteHost) async throws -> RemoteHostAccountInstallationState
    func installAccount(_ account: CodexAccount, on host: RemoteHost) async throws
    func switchToAccount(_ account: CodexAccount, on host: RemoteHost) async throws
    func refreshCodexAppServer(on host: RemoteHost) async throws
    func readCurrentAccountStatus(on host: RemoteHost) async throws -> CodexAccountStatus
}

enum RemoteHostClientError: LocalizedError, Equatable {
    case unavailable
    case commandFailed(String)
    case authReadFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Remote host switching is not configured yet."
        case .commandFailed(let message):
            return message
        case .authReadFailed(let message):
            return message
        }
    }
}

struct UnavailableRemoteHostClient: RemoteHostClient {
    func testConnection(to host: RemoteHost) async throws {
        throw RemoteHostClientError.unavailable
    }

    func installationState(for account: CodexAccount, on host: RemoteHost) async throws -> RemoteHostAccountInstallationState {
        throw RemoteHostClientError.unavailable
    }

    func installAccount(_ account: CodexAccount, on host: RemoteHost) async throws {
        throw RemoteHostClientError.unavailable
    }

    func switchToAccount(_ account: CodexAccount, on host: RemoteHost) async throws {
        throw RemoteHostClientError.unavailable
    }

    func refreshCodexAppServer(on host: RemoteHost) async throws {
        throw RemoteHostClientError.unavailable
    }

    func readCurrentAccountStatus(on host: RemoteHost) async throws -> CodexAccountStatus {
        throw RemoteHostClientError.unavailable
    }
}
