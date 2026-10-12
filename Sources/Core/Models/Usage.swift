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
    /// Claude's separate weekly limit for one model, named as Claude names it, such as "Fable". The menu bar icon
    /// ignores it.
    case modelWeekly(modelName: String)

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

    var isModelLimit: Bool {
        if case .modelWeekly = self { true } else { false }
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
    var credits: UsageCredits? = nil
    /// The email of the account the tool is signed in to, for Claude and Cursor. Codex keeps it on `CodexAccount`.
    var accountEmail: String? = nil

    func window(_ kind: UsageWindowKind) -> UsageWindow? {
        windows.first { $0.kind == kind }
    }

    func freshness(at now: Date, staleAfter: TimeInterval) -> UsageFreshness {
        now.timeIntervalSince(fetchedAt) > staleAfter ? .stale : .fresh
    }
}

/// Credits or paid usage beyond the plan, shown on the tool's card. It never changes limits or account ranking.
enum UsageCredits: Hashable {
    /// Credits left to spend, such as Codex credits.
    case balance(Decimal)
    /// The account spends credits without a balance.
    case unlimited
    /// Paid usage beyond the plan so far, against an optional cap, such as Claude extra usage or Cursor on-demand.
    case extraUsage(spent: Decimal, limit: Decimal?, currencyCode: String)
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
