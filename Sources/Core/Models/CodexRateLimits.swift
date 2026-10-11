import Foundation

extension UsageSnapshot {
    typealias CodexReportedWindow = (usedPercent: Int, resetsAt: Date?, durationMinutes: Int?)

    /// Codex reports up to two windows, a primary and a secondary, and either may be missing. A window is named
    /// by its length, never by its slot: a free plan's only window is 30 days long and arrives as secondary.
    /// Windows come back shortest first, each kind once (the first reported wins). Older payloads without lengths
    /// are read by slot, primary as session and secondary as weekly, but only when neither window reports a length.
    static func codex(
        planName: String?,
        primary: CodexReportedWindow?,
        secondary: CodexReportedWindow?,
        fetchedAt: Date
    ) -> UsageSnapshot {
        let reported = [primary, secondary].compactMap { $0 }
        let windows: [UsageWindow]
        if reported.contains(where: { $0.durationMinutes != nil }) {
            windows = reported
                .compactMap { window in
                    window.durationMinutes.map {
                        UsageWindow(
                            kind: UsageWindowKind(durationMinutes: $0),
                            usedPercent: window.usedPercent,
                            resetsAt: window.resetsAt,
                            durationMinutes: $0
                        )
                    }
                }
                .reduce(into: [UsageWindow]()) { kept, window in
                    if !kept.contains(where: { $0.kind == window.kind }) { kept.append(window) }
                }
                .sorted { ($0.durationMinutes ?? 0) < ($1.durationMinutes ?? 0) }
        } else {
            windows = [
                primary.map { UsageWindow(kind: .session, usedPercent: $0.usedPercent, resetsAt: $0.resetsAt) },
                secondary.map { UsageWindow(kind: .weekly, usedPercent: $0.usedPercent, resetsAt: $0.resetsAt) },
            ].compactMap { $0 }
        }
        return UsageSnapshot(provider: .codex, planName: planName, windows: windows, fetchedAt: fetchedAt)
    }

    /// The windows back in Codex's two slots, shortest first. Readers name them by length, so the slot is free.
    var codexSlots: (primary: UsageWindow?, secondary: UsageWindow?) {
        (windows.first, windows.dropFirst().first)
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
