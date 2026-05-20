import Foundation

enum TokenUsageChartVariant: String, CaseIterable, Equatable {
    case minimalDailyBars
    case sparklineArea
    case heatStrip
    case nativeCompact

    var title: String {
        switch self {
        case .minimalDailyBars:
            return "Minimal Bars"
        case .sparklineArea:
            return "Sparkline"
        case .heatStrip:
            return "Heat Strip"
        case .nativeCompact:
            return "Native Compact"
        }
    }

    var tradeoffNote: String {
        switch self {
        case .minimalDailyBars:
            return "Highest daily clarity with low decoration, but it has the most chart-like visual weight."
        case .sparklineArea:
            return "Best at showing rhythm and trend, but individual day comparison is less exact."
        case .heatStrip:
            return "Most compact and calendar-like, but token magnitude is more approximate."
        case .nativeCompact:
            return "Best native menu fit and summary readability, but it hides more of the day-by-day shape."
        }
    }
}

struct TokenUsageDayBucket: Equatable, Identifiable {
    let id: Int
    let shortLabel: String
    let tokenCount: Int
}

struct TokenUsagePrototypeCard: Equatable, Identifiable {
    let variant: TokenUsageChartVariant
    let periodTitle: String
    let buckets: [TokenUsageDayBucket]

    var id: TokenUsageChartVariant { variant }

    var todayTokenCount: Int {
        buckets.last?.tokenCount ?? 0
    }

    var periodTotalTokenCount: Int {
        buckets.reduce(0) { $0 + $1.tokenCount }
    }

    var accessibilitySummary: String {
        [
            "Token Usage",
            "This Mac",
            "Today: \(formattedTokenCount(todayTokenCount)) tokens",
            "\(periodTitle): \(formattedTokenCount(periodTotalTokenCount)) tokens",
            variant.title
        ].joined(separator: " • ")
    }
}

enum TokenUsagePrototype {
    static let periodTitle = "Last 30 days"

    static var fixtureCards: [TokenUsagePrototypeCard] {
        TokenUsageChartVariant.allCases.map {
            TokenUsagePrototypeCard(
                variant: $0,
                periodTitle: periodTitle,
                buckets: fixtureBuckets
            )
        }
    }

    static let fixtureBuckets: [TokenUsageDayBucket] = [
        .init(id: 1, shortLabel: "Apr 21", tokenCount: 8_200),
        .init(id: 2, shortLabel: "Apr 22", tokenCount: 15_400),
        .init(id: 3, shortLabel: "Apr 23", tokenCount: 12_100),
        .init(id: 4, shortLabel: "Apr 24", tokenCount: 29_800),
        .init(id: 5, shortLabel: "Apr 25", tokenCount: 4_600),
        .init(id: 6, shortLabel: "Apr 26", tokenCount: 7_900),
        .init(id: 7, shortLabel: "Apr 27", tokenCount: 18_600),
        .init(id: 8, shortLabel: "Apr 28", tokenCount: 37_200),
        .init(id: 9, shortLabel: "Apr 29", tokenCount: 41_500),
        .init(id: 10, shortLabel: "Apr 30", tokenCount: 23_700),
        .init(id: 11, shortLabel: "May 1", tokenCount: 9_400),
        .init(id: 12, shortLabel: "May 2", tokenCount: 5_500),
        .init(id: 13, shortLabel: "May 3", tokenCount: 13_900),
        .init(id: 14, shortLabel: "May 4", tokenCount: 21_300),
        .init(id: 15, shortLabel: "May 5", tokenCount: 34_800),
        .init(id: 16, shortLabel: "May 6", tokenCount: 47_600),
        .init(id: 17, shortLabel: "May 7", tokenCount: 28_100),
        .init(id: 18, shortLabel: "May 8", tokenCount: 16_700),
        .init(id: 19, shortLabel: "May 9", tokenCount: 6_200),
        .init(id: 20, shortLabel: "May 10", tokenCount: 11_800),
        .init(id: 21, shortLabel: "May 11", tokenCount: 24_900),
        .init(id: 22, shortLabel: "May 12", tokenCount: 32_400),
        .init(id: 23, shortLabel: "May 13", tokenCount: 51_200),
        .init(id: 24, shortLabel: "May 14", tokenCount: 43_700),
        .init(id: 25, shortLabel: "May 15", tokenCount: 19_300),
        .init(id: 26, shortLabel: "May 16", tokenCount: 10_600),
        .init(id: 27, shortLabel: "May 17", tokenCount: 14_500),
        .init(id: 28, shortLabel: "May 18", tokenCount: 27_800),
        .init(id: 29, shortLabel: "May 19", tokenCount: 39_100),
        .init(id: 30, shortLabel: "May 20", tokenCount: 22_400)
    ]
}

func formattedTokenCount(_ tokenCount: Int) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = true
    return formatter.string(from: NSNumber(value: tokenCount)) ?? "\(tokenCount)"
}
