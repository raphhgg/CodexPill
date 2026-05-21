import Foundation

enum CodexTokenUsagePeriod: Int, CaseIterable, Codable, Hashable {
    case last7Days = 7
    case last30Days = 30
    case last90Days = 90

    var dayCount: Int {
        rawValue
    }

    var menuTitle: String {
        switch self {
        case .last7Days:
            return "Last 7 Days"
        case .last30Days:
            return "Last 30 Days"
        case .last90Days:
            return "Last 90 Days"
        }
    }

    var summaryTitle: String {
        switch self {
        case .last7Days:
            return "Last 7 days"
        case .last30Days:
            return "Last 30 days"
        case .last90Days:
            return "Last 90 days"
        }
    }
}

enum TokenUsageLoadingAnimationStyle: String, CaseIterable, Equatable {
    case waves
    case random

    var menuTitle: String {
        switch self {
        case .waves:
            return "Waves"
        case .random:
            return "Random"
        }
    }
}

struct TokenUsageScanProgress: Equatable, Sendable {
    var scannedFiles: Int
    var totalFiles: Int

    var message: String {
        guard totalFiles > 0 else {
            return "Scanning local sessions"
        }
        return "Scanning \(min(scannedFiles, totalFiles)) of \(totalFiles) sessions"
    }
}

struct CodexDailyTokenUsage: Codable, Equatable {
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
