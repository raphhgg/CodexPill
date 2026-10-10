import Foundation

enum CursorUsageSummaryParser {
    enum ParseError: Error, Equatable {
        case unexpectedShape
    }

    static func parse(_ data: Data, fetchedAt: Date) throws -> CursorUsageSnapshot {
        let summary: UsageSummaryDTO
        do {
            summary = try JSONDecoder().decode(UsageSummaryDTO.self, from: data)
        } catch {
            throw ParseError.unexpectedShape
        }

        return CursorUsageSnapshot(
            planName: summary.membershipType.flatMap { $0.isEmpty ? nil : $0 },
            includedUsagePercent: includedUsagePercent(from: summary),
            onDemand: onDemandSpend(from: summary.individualUsage?.onDemand),
            billingCycle: billingCycle(start: summary.billingCycleStart, end: summary.billingCycleEnd),
            fetchedAt: fetchedAt
        )
    }

    // `totalPercentUsed` is Cursor's headline figure; bonus credit makes it diverge from used / limit.
    private static func includedUsagePercent(from summary: UsageSummaryDTO) -> Double? {
        let plan = summary.individualUsage?.plan
        if summary.isUnlimited == true || plan?.enabled == false {
            return nil
        }
        if let totalPercentUsed = plan?.totalPercentUsed {
            return totalPercentUsed
        }
        if let used = plan?.used, let limit = plan?.limit, limit > 0 {
            return used / limit * 100
        }
        return nil
    }

    private static func onDemandSpend(from onDemand: OnDemandDTO?) -> CursorOnDemandSpend? {
        guard let onDemand, onDemand.enabled == true else { return nil }

        return CursorOnDemandSpend(
            usedUSD: (onDemand.used ?? 0) / 100,
            limitUSD: onDemand.limit.map { $0 / 100 }
        )
    }

    private static func billingCycle(start: String?, end: String?) -> DateInterval? {
        guard
            let start = start.flatMap(date(from:)),
            let end = end.flatMap(date(from:)),
            end > start
        else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    private static func date(from value: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(value)
    }
}

private struct UsageSummaryDTO: Decodable {
    let billingCycleStart: String?
    let billingCycleEnd: String?
    let membershipType: String?
    let isUnlimited: Bool?
    let individualUsage: IndividualUsageDTO?
}

private struct IndividualUsageDTO: Decodable {
    let plan: PlanUsageDTO?
    let onDemand: OnDemandDTO?
}

private struct PlanUsageDTO: Decodable {
    let enabled: Bool?
    let used: Double?
    let limit: Double?
    let totalPercentUsed: Double?
}

private struct OnDemandDTO: Decodable {
    let enabled: Bool?
    let used: Decimal?
    let limit: Decimal?
}
