import Foundation

struct CodexRateLimitSnapshot: Codable, Hashable {
    var limitID: String?
    var limitName: String?
    var planType: String?
    var primary: CodexRateLimitWindow?
    var secondary: CodexRateLimitWindow?
    var fetchedAt: Date
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
