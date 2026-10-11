import Foundation

enum UsageProvider: String, CaseIterable, Hashable {
    case codex
    case claude
    case cursor
}

enum UsageWindowKind: Hashable {
    case session
    case weekly
    case monthly
    case billingCycle
    /// A limit whose length has no common name. The menu titles it by that length.
    case other(durationMinutes: Int)

    /// The one rule that names a reported window by its length. Each name allows an hour of slack either way,
    /// and monthly covers every calendar month (28 to 31 days).
    init(durationMinutes: Int) {
        switch durationMinutes {
        case (5 * 60 - 60)...(5 * 60 + 60): self = .session
        case (7 * 1_440 - 60)...(7 * 1_440 + 60): self = .weekly
        case (28 * 1_440 - 60)...(31 * 1_440 + 60): self = .monthly
        default: self = .other(durationMinutes: durationMinutes)
        }
    }
}

struct UsageWindow: Hashable {
    var kind: UsageWindowKind
    var usedPercent: Int
    var resetsAt: Date?
    var durationMinutes: Int?

    func displayedUsedPercent(at now: Date = .now) -> Int {
        guard let resetsAt else { return usedPercent }
        return resetsAt <= now ? 0 : usedPercent
    }
}

struct UsageSnapshot: Hashable {
    var provider: UsageProvider
    var planName: String?
    var windows: [UsageWindow]
    var fetchedAt: Date
    var resetCredits: UsageResetCredits? = nil
    var spend: UsageSpend? = nil

    func window(_ kind: UsageWindowKind) -> UsageWindow? {
        windows.first { $0.kind == kind }
    }

    func freshness(at now: Date, staleAfter: TimeInterval) -> UsageFreshness {
        now.timeIntervalSince(fetchedAt) > staleAfter ? .stale : .fresh
    }
}

/// On-demand spend in dollars, beyond the plan. It is money, not a percent of a limit.
struct UsageSpend: Hashable {
    var usedUSD: Decimal
    /// `nil` when on-demand spend has no cap.
    var limitUSD: Decimal?
}

/// Earned credits that reset the current Codex limits early.
struct UsageResetCredits: Hashable {
    var availableCount: Int
    /// The available credits Codex listed, or `nil` when it reported only the count.
    /// Codex may list fewer credits than `availableCount`.
    var credits: [UsageResetCredit]?

    var nextExpiry: Date? {
        credits?.compactMap(\.expiresAt).min()
    }
}

struct UsageResetCredit: Hashable {
    /// `nil` for a credit that never expires.
    var expiresAt: Date?
}

enum UsageFreshness: Hashable {
    case fresh
    case stale
}
