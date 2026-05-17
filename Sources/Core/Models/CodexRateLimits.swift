import Foundation

struct CodexRateLimitSnapshot: Codable, Hashable {
    var limitID: String?
    var limitName: String?
    var planType: String?
    var primary: CodexRateLimitWindow?
    var secondary: CodexRateLimitWindow?
    var fetchedAt: Date

    var sessionWindow: CodexRateLimitWindow? {
        if let window = knownDurationWindows.first(where: { $0.isSessionDuration }) {
            return window
        }

        return legacyWindow(primary, fallbackWhenOtherWindowHasKnownDuration: secondary)
    }

    var weeklyWindow: CodexRateLimitWindow? {
        if let window = knownDurationWindows.first(where: { $0.isWeeklyDuration }) {
            return window
        }

        return legacyWindow(secondary, fallbackWhenOtherWindowHasKnownDuration: primary)
    }

    private var knownDurationWindows: [CodexRateLimitWindow] {
        [primary, secondary]
            .compactMap { $0 }
            .filter { $0.windowDurationMinutes != nil }
    }

    private func legacyWindow(
        _ positionalWindow: CodexRateLimitWindow?,
        fallbackWhenOtherWindowHasKnownDuration otherWindow: CodexRateLimitWindow?
    ) -> CodexRateLimitWindow? {
        guard positionalWindow?.windowDurationMinutes == nil,
              otherWindow?.windowDurationMinutes == nil else {
            return nil
        }
        return positionalWindow
    }
}

func effectiveCodexPlanType(accountPlanType: String?, rateLimitPlanType: String?) -> String? {
    let accountPlan = knownCodexPlanType(accountPlanType)
    let rateLimitPlan = knownCodexPlanType(rateLimitPlanType)

    if accountPlan == "plus", rateLimitPlan == "prolite" || rateLimitPlan == "pro" {
        return rateLimitPlan
    }

    return accountPlan ?? rateLimitPlan
}

func normalizedCodexPlanType(_ planType: String?) -> String? {
    guard let planType else { return nil }
    let normalized = planType
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    guard !normalized.isEmpty else { return nil }

    switch normalized {
    case "prolite":
        return "prolite"
    case "self_serve_business_usage_based":
        return "business"
    case "enterprise_cbp_usage_based":
        return "enterprise"
    default:
        return normalized
    }
}

func displayNameForCodexPlanType(_ planType: String?) -> String {
    switch normalizedCodexPlanType(planType) {
    case "free":
        return "Free"
    case "go":
        return "Go"
    case "plus":
        return "Plus"
    case "pro":
        return "Pro x20"
    case "prolite":
        return "Pro x5"
    case "team":
        return "Team"
    case "business":
        return "Business"
    case "enterprise":
        return "Enterprise"
    case "edu":
        return "Edu"
    case "unknown", nil:
        return "Unknown"
    case .some(let value):
        return value
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

private func knownCodexPlanType(_ planType: String?) -> String? {
    let normalized = normalizedCodexPlanType(planType)
    return normalized == "unknown" ? nil : normalized
}

struct CodexRateLimitWindow: Codable, Hashable {
    static let weeklyDurationMinutes = 10_080
    static let weeklyDurationToleranceMinutes = 60

    var usedPercent: Int
    var resetsAt: Date?
    var windowDurationMinutes: Int?

    func displayedUsedPercent(at now: Date = .now) -> Int {
        guard let resetsAt else { return usedPercent }
        return resetsAt <= now ? 0 : usedPercent
    }

    fileprivate var isSessionDuration: Bool {
        guard let windowDurationMinutes else { return false }
        return windowDurationMinutes < Self.weeklyDurationMinutes - Self.weeklyDurationToleranceMinutes
    }

    fileprivate var isWeeklyDuration: Bool {
        guard let windowDurationMinutes else { return false }
        return windowDurationMinutes >= Self.weeklyDurationMinutes - Self.weeklyDurationToleranceMinutes
    }
}
