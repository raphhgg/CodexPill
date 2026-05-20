import Foundation

enum CodexTokenUsagePeriod: Int, CaseIterable, Codable, Hashable {
    case last7Days = 7
    case last30Days = 30
    case last90Days = 90

    var dayCount: Int {
        rawValue
    }
}

struct CodexDailyTokenUsage: Equatable {
    var day: Date
    var usage: CodexTokenUsageTotals
}

struct CodexTokenUsageTotals: Equatable, Codable {
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
    var reasoningOutputTokens: Int
    var totalTokens: Int

    static let zero = CodexTokenUsageTotals(
        inputTokens: 0,
        cachedInputTokens: 0,
        outputTokens: 0,
        reasoningOutputTokens: 0,
        totalTokens: 0
    )

    static func + (lhs: CodexTokenUsageTotals, rhs: CodexTokenUsageTotals) -> CodexTokenUsageTotals {
        CodexTokenUsageTotals(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            cachedInputTokens: lhs.cachedInputTokens + rhs.cachedInputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            reasoningOutputTokens: lhs.reasoningOutputTokens + rhs.reasoningOutputTokens,
            totalTokens: lhs.totalTokens + rhs.totalTokens
        )
    }

    static func - (lhs: CodexTokenUsageTotals, rhs: CodexTokenUsageTotals) -> CodexTokenUsageTotals {
        CodexTokenUsageTotals(
            inputTokens: lhs.inputTokens - rhs.inputTokens,
            cachedInputTokens: lhs.cachedInputTokens - rhs.cachedInputTokens,
            outputTokens: lhs.outputTokens - rhs.outputTokens,
            reasoningOutputTokens: lhs.reasoningOutputTokens - rhs.reasoningOutputTokens,
            totalTokens: lhs.totalTokens - rhs.totalTokens
        )
    }

    var hasPositiveTotal: Bool {
        totalTokens > 0
    }

    var hasNegativeComponent: Bool {
        inputTokens < 0 ||
            cachedInputTokens < 0 ||
            outputTokens < 0 ||
            reasoningOutputTokens < 0
    }

    func preservingOnlyTotalTokens() -> CodexTokenUsageTotals {
        CodexTokenUsageTotals(
            inputTokens: 0,
            cachedInputTokens: 0,
            outputTokens: 0,
            reasoningOutputTokens: 0,
            totalTokens: totalTokens
        )
    }
}
