import Foundation

func appServerFailure(
    stderr: String?,
    terminationStatus: Int?,
    timedOut: Bool
) -> CodexAppServerError {
    if let stderr, !stderr.isEmpty {
        return .server(stderr)
    }

    if let terminationStatus {
        return .terminated(terminationStatus)
    }

    if timedOut {
        return .timeout
    }

    return .timeout
}

func friendlyAppServerDecodingMessage(for error: DecodingError) -> String {
    switch error {
    case .keyNotFound:
        return "Codex returned an incomplete app-server response."
    case .valueNotFound:
        return "Codex returned an incomplete app-server response."
    case .typeMismatch:
        return "Codex returned an invalid app-server response."
    case .dataCorrupted:
        return "Codex returned an unreadable app-server response."
    @unknown default:
        return "Codex returned an invalid app-server response."
    }
}

enum CodexAppServerError: LocalizedError, Equatable {
    case server(String)
    case terminated(Int)
    case timeout
    case remoteConnectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .server(let message):
            "Codex app-server error: \(message)"
        case .terminated(let code):
            "Codex app-server exited with code \(code)."
        case .timeout:
            "Timed out while reading Codex account data."
        case .remoteConnectionFailed(let message):
            message
        }
    }
}
