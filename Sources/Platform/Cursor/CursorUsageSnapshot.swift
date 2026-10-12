import Foundation

struct CursorUsageSnapshot: Codable, Equatable, Sendable {
    let planName: String?
    let includedUsagePercent: Double?
    let onDemand: CursorOnDemandSpend?
    let billingCycle: DateInterval?
    let fetchedAt: Date
    /// The email Cursor cached for the signed-in account. The usage summary does not carry it.
    var accountEmail: String? = nil
}

struct CursorOnDemandSpend: Codable, Equatable, Sendable {
    let usedUSD: Decimal
    let limitUSD: Decimal?
}
