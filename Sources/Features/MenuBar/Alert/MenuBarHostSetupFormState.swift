import Foundation

enum MenuBarHostSetupStatusKind: Equatable {
    case idle
    case testing
    case success
    case failure
}

struct MenuBarHostSetupFormState: Equatable {
    private(set) var destination: String
    private(set) var validatedHost: RemoteHost?
    private(set) var statusMessage: String
    private(set) var statusKind: MenuBarHostSetupStatusKind
    private let idleStatusText: String
    var isTesting = false

    init(destination: String, idleStatusText: String) {
        self.destination = destination
        self.idleStatusText = idleStatusText
        self.statusMessage = idleStatusText
        self.statusKind = .idle
    }

    var trimmedDestination: String {
        destination.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSubmit: Bool {
        guard !isTesting, let validatedHost else { return false }
        return validatedHost.destination == trimmedDestination
    }

    mutating func updateDestination(_ value: String) {
        destination = value
        isTesting = false

        guard validatedHost?.destination == trimmedDestination else {
            validatedHost = nil
            statusMessage = idleStatusText
            statusKind = .idle
            return
        }
    }

    mutating func beginTesting() {
        validatedHost = nil
        isTesting = true
        statusMessage = "Testing connection..."
        statusKind = .testing
    }

    mutating func finishTesting(with result: Result<RemoteHost, Error>) {
        isTesting = false
        switch result {
        case .success(let host):
            validatedHost = host
            statusMessage = "Connection successful."
            statusKind = .success
        case .failure(let error):
            validatedHost = nil
            if let localizedError = error as? LocalizedError, let message = localizedError.errorDescription, !message.isEmpty {
                statusMessage = message
            } else {
                statusMessage = error.localizedDescription
            }
            statusKind = .failure
        }
    }
}
