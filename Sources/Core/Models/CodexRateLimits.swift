import Foundation

extension UsageSnapshot {
    typealias CodexReportedWindow = (usedPercent: Int, resetsAt: Date?, durationMinutes: Int?)

    private static let weeklyDurationMinutes = 10_080
    private static let weeklyDurationToleranceMinutes = 60

    /// Codex reports a primary and a secondary window. Windows with a known duration are classified by
    /// that duration. Older payloads without durations are read by position: primary is the session
    /// window and secondary the weekly window, but only when neither window reports a duration.
    static func codex(
        planName: String?,
        primary: CodexReportedWindow?,
        secondary: CodexReportedWindow?,
        fetchedAt: Date
    ) -> UsageSnapshot {
        let reported = [primary, secondary].compactMap { $0 }
        let classified: [(kind: UsageWindowKind, window: CodexReportedWindow)]
        if reported.contains(where: { $0.durationMinutes != nil }) {
            classified = reported.compactMap { window in
                window.durationMinutes.map { (kind: kind(forDurationMinutes: $0), window: window) }
            }
        } else {
            classified = [
                primary.map { (kind: UsageWindowKind.session, window: $0) },
                secondary.map { (kind: UsageWindowKind.weekly, window: $0) },
            ].compactMap { $0 }
        }

        let windows = [UsageWindowKind.session, .weekly].compactMap { kind in
            classified.first { $0.kind == kind }.map {
                UsageWindow(
                    kind: kind,
                    usedPercent: $0.window.usedPercent,
                    resetsAt: $0.window.resetsAt,
                    durationMinutes: $0.window.durationMinutes
                )
            }
        }
        return UsageSnapshot(provider: .codex, planName: planName, windows: windows, fetchedAt: fetchedAt)
    }

    private static func kind(forDurationMinutes durationMinutes: Int) -> UsageWindowKind {
        durationMinutes < weeklyDurationMinutes - weeklyDurationToleranceMinutes ? .session : .weekly
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
