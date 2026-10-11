import Foundation

struct CursorUsageSnapshot: Codable, Equatable, Sendable {
    let planName: String?
    let includedUsagePercent: Double?
    let onDemand: CursorOnDemandSpend?
    let billingCycle: DateInterval?
    let fetchedAt: Date
}

struct CursorOnDemandSpend: Codable, Equatable, Sendable {
    let usedUSD: Decimal
    let limitUSD: Decimal?
}
