import Foundation

struct CursorUsageSnapshot: Equatable, Sendable {
    let planName: String?
    let includedUsagePercent: Double?
    let onDemand: CursorOnDemandSpend?
    let billingCycle: DateInterval?
    let fetchedAt: Date
}

struct CursorOnDemandSpend: Equatable, Sendable {
    let usedUSD: Decimal
    let limitUSD: Decimal?
}
