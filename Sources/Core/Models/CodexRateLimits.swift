import Foundation

struct CodexRateLimitSnapshot: Codable, Hashable {
    var limitID: String?
    var limitName: String?
    var planType: String?
    var primary: CodexRateLimitWindow?
    var secondary: CodexRateLimitWindow?
    var fetchedAt: Date

    var sessionWindow: CodexRateLimitWindow? {
        window(classifiedAs: .session)
    }

    var weeklyWindow: CodexRateLimitWindow? {
        window(classifiedAs: .weekly)
    }

    var usageWindows: [UsageWindow] {
        [UsageWindowKind.session, .weekly].compactMap { kind in
            window(classifiedAs: kind).map {
                UsageWindow(
                    kind: kind,
                    usedPercent: $0.usedPercent,
                    resetsAt: $0.resetsAt,
                    durationMinutes: $0.windowDurationMinutes
                )
            }
        }
    }

    /// Codex reports a primary and a secondary window. Windows with a known duration are classified by
    /// that duration. Older payloads without durations are read by position: primary is the session
    /// window and secondary the weekly window, but only when neither window reports a duration.
    private func window(classifiedAs kind: UsageWindowKind) -> CodexRateLimitWindow? {
        let knownDurationWindows = [primary, secondary]
            .compactMap { $0 }
            .filter { $0.windowDurationMinutes != nil }
        if let window = knownDurationWindows.first(where: { $0.kind == kind }) {
            return window
        }

        guard primary?.windowDurationMinutes == nil, secondary?.windowDurationMinutes == nil else {
            return nil
        }
        switch kind {
        case .session:
            return primary
        case .weekly:
            return secondary
        case .billingCycle, .other:
            return nil
        }
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

    fileprivate var kind: UsageWindowKind? {
        guard let windowDurationMinutes else { return nil }
        return windowDurationMinutes < Self.weeklyDurationMinutes - Self.weeklyDurationToleranceMinutes
            ? .session
            : .weekly
    }
}
