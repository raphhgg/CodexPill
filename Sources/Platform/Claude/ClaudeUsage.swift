import CoreFoundation
import Foundation

enum ClaudeUsageWindowKind: String, CaseIterable, Sendable {
    case fiveHour = "five_hour"
    case sevenDay = "seven_day"

    var durationMinutes: Int {
        switch self {
        case .fiveHour: 300
        case .sevenDay: 10_080
        }
    }
}

/// A usage window evaluated at a point in time. `resetsAt == nil` means the
/// window has reset since the relay captured it, so `usedPercent` is 0.
struct ClaudeUsageWindow: Equatable, Sendable {
    let kind: ClaudeUsageWindowKind
    let usedPercent: Double
    let resetsAt: Date?
}

/// The relay's `claude-usage.json` exactly as captured, with no time evaluation.
struct ClaudeUsageRecord: Equatable, Sendable {
    struct Window: Equatable, Sendable {
        let usedPercent: Double
        let resetsAt: Date
    }

    let capturedAt: Date
    let windows: [ClaudeUsageWindowKind: Window]
}

struct ClaudeUsageSnapshot: Equatable, Sendable {
    let capturedAt: Date
    /// Ordered as `ClaudeUsageWindowKind.allCases`.
    let windows: [ClaudeUsageWindow]
}

enum ClaudeUsageStatus: Equatable, Sendable {
    /// No usage file: the relay has never run.
    case notConnected
    /// The relay ran but saw no rate limits (not a Pro/Max plan, or no API response yet).
    case awaitingUsage(capturedAt: Date)
    case current(ClaudeUsageSnapshot)
    /// Captured longer ago than the staleness threshold. Values may undercount
    /// usage from outside Claude Code sessions that ran the relay.
    case stale(ClaudeUsageSnapshot)

    static func evaluate(
        record: ClaudeUsageRecord?,
        now: Date,
        staleAfter: TimeInterval = 3600
    ) -> ClaudeUsageStatus {
        guard let record else { return .notConnected }

        let windows = ClaudeUsageWindowKind.allCases.compactMap { kind -> ClaudeUsageWindow? in
            guard let window = record.windows[kind] else { return nil }
            guard window.resetsAt > now else {
                return ClaudeUsageWindow(kind: kind, usedPercent: 0, resetsAt: nil)
            }
            return ClaudeUsageWindow(kind: kind, usedPercent: window.usedPercent, resetsAt: window.resetsAt)
        }
        guard !windows.isEmpty else { return .awaitingUsage(capturedAt: record.capturedAt) }

        let snapshot = ClaudeUsageSnapshot(capturedAt: record.capturedAt, windows: windows)
        return now.timeIntervalSince(record.capturedAt) > staleAfter ? .stale(snapshot) : .current(snapshot)
    }
}

enum ClaudeUsageParseError: Error, Equatable, Sendable {
    case notJSON
    case notAnObject
    case missingSchema
    case unsupportedSchema(Int)
    case invalidCapturedAt
    case invalidRateLimits
    case invalidWindow(ClaudeUsageWindowKind)
}

extension ClaudeUsageRecord {
    static let supportedSchema = 1

    static func parse(_ data: Data) throws(ClaudeUsageParseError) -> ClaudeUsageRecord {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw .notJSON
        }
        guard let root = object as? [String: Any] else { throw .notAnObject }

        guard let schemaValue = number(root["schema"]),
              let schema = Int(exactly: schemaValue) else {
            throw .missingSchema
        }
        guard schema == supportedSchema else { throw .unsupportedSchema(schema) }

        guard let capturedAt = number(root["captured_at"]) else { throw .invalidCapturedAt }
        guard let rateLimits = root["rate_limits"] as? [String: Any] else { throw .invalidRateLimits }

        var windows: [ClaudeUsageWindowKind: Window] = [:]
        for kind in ClaudeUsageWindowKind.allCases {
            guard let rawWindow = rateLimits[kind.rawValue] else { continue }
            guard let window = rawWindow as? [String: Any],
                  let usedPercent = number(window["used_percentage"]),
                  let resetsAt = number(window["resets_at"]) else {
                throw .invalidWindow(kind)
            }
            windows[kind] = Window(
                usedPercent: min(max(usedPercent, 0), 100),
                resetsAt: Date(timeIntervalSince1970: resetsAt)
            )
        }

        return ClaudeUsageRecord(capturedAt: Date(timeIntervalSince1970: capturedAt), windows: windows)
    }

    /// JSONSerialization bridges JSON booleans to NSNumber, so they are excluded explicitly.
    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }
}
