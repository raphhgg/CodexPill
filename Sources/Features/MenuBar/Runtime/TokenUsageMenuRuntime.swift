import Foundation

enum TokenUsageMenuLoadState: Equatable {
    case loading
    case loaded([CodexDailyTokenUsage])
    case unavailable
}

protocol TokenUsageMenuProviding {
    func load(period: CodexTokenUsagePeriod) async -> TokenUsageMenuLoadState
}

struct LocalCodexSessionTokenUsageMenuProvider: TokenUsageMenuProviding {
    private let scanner: CodexSessionTokenUsageScanner
    private let sessionsDirectory: URL
    private let now: () -> Date

    init(
        scanner: CodexSessionTokenUsageScanner = CodexSessionTokenUsageScanner(),
        sessionsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true),
        now: @escaping () -> Date = Date.init
    ) {
        self.scanner = scanner
        self.sessionsDirectory = sessionsDirectory
        self.now = now
    }

    func load(period: CodexTokenUsagePeriod) async -> TokenUsageMenuLoadState {
        do {
            let result = try scanner.scan(
                sessionsDirectory: sessionsDirectory,
                period: period,
                now: now()
            )
            return .loaded(result.buckets)
        } catch {
            return .unavailable
        }
    }
}
