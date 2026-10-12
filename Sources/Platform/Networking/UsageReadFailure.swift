import Foundation
import OSLog

private let usageReadLogger = Logger(subsystem: "com.raphhgg.refill", category: "UsageRead")

/// Why a Claude or Cursor usage read failed, as a log line may say it: a category, plus the status of an HTTP error.
/// It never carries a token, an email, an account ID or a URL.
enum UsageReadFailure: Equatable, Sendable {
    case network
    case httpStatus(Int)
    case unauthorized
    case rateLimited
    /// The reply, or the tool's own sign-in on this Mac, could not be parsed.
    case parse
    case keychainAccess

    init(_ error: ClaudeUsageWebError) {
        self = switch error {
        case .unauthorized: .unauthorized
        case .forbidden: .httpStatus(403)
        case .rateLimited: .rateLimited
        case let .httpStatus(code): .httpStatus(code)
        case .transport: .network
        }
    }

    init(_ error: CursorUsageWebError) {
        self = switch error {
        case .unauthorized: .unauthorized
        case .forbidden: .httpStatus(403)
        case .rateLimited: .rateLimited
        case let .httpStatus(code): .httpStatus(code)
        case .transport: .network
        }
    }

    /// The only part of the log line that is public: "network", "http 503", "keychain access".
    var logDescription: String {
        switch self {
        case .network: "network"
        case let .httpStatus(code): "http \(code)"
        case .unauthorized: "unauthorized"
        case .rateLimited: "rate limited"
        case .parse: "parse"
        case .keychainAccess: "keychain access"
        }
    }

    func log(for provider: UsageProvider) {
        let description = logDescription
        switch provider {
        case .claude: usageReadLogger.error("Claude usage read failed: \(description, privacy: .public)")
        case .cursor: usageReadLogger.error("Cursor usage read failed: \(description, privacy: .public)")
        case .codex: usageReadLogger.error("Codex usage read failed: \(description, privacy: .public)")
        }
    }
}
