import Foundation

struct CodexRateLimitSnapshot: Codable, Hashable {
    var limitID: String?
    var limitName: String?
    var planType: String?
    var primary: CodexRateLimitWindow?
    var secondary: CodexRateLimitWindow?
    var fetchedAt: Date
}

func effectiveCodexPlanType(accountPlanType: String?, rateLimitPlanType: String?) -> String? {
    let accountPlan = knownCodexPlanType(accountPlanType)
    let rateLimitPlan = knownCodexPlanType(rateLimitPlanType)

    if accountPlan == "plus", rateLimitPlan == "pro" {
        return "pro"
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
        return "pro"
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
        return "Pro"
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
    var usedPercent: Int
    var resetsAt: Date?
    var windowDurationMinutes: Int?

    func displayedUsedPercent(at now: Date = .now) -> Int {
        guard let resetsAt else { return usedPercent }
        return resetsAt <= now ? 0 : usedPercent
    }
}
