import Foundation

enum UsageProvider: Hashable {
    case codex
    case claude
    case cursor
}

enum UsageWindowKind: Hashable {
    case session
    case weekly
    case billingCycle
    case other(minutes: Int)
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

    func window(_ kind: UsageWindowKind) -> UsageWindow? {
        windows.first { $0.kind == kind }
    }

    func freshness(at now: Date, staleAfter: TimeInterval) -> UsageFreshness {
        now.timeIntervalSince(fetchedAt) > staleAfter ? .stale : .fresh
    }
}

enum UsageFreshness: Hashable {
    case fresh
    case stale
}
