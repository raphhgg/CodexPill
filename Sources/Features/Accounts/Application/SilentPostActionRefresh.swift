import Foundation
import OSLog

private let silentPostActionRefreshLogger = Logger(subsystem: "com.raphhgg.codexpill", category: "SilentPostActionRefresh")

struct SilentPostActionRefresh: Sendable {
    private let refreshActiveAccountUseCase: RefreshActiveAccountUseCase
    private let delay: Duration

    init(refreshActiveAccountUseCase: RefreshActiveAccountUseCase, delay: Duration = .seconds(2)) {
        self.refreshActiveAccountUseCase = refreshActiveAccountUseCase
        self.delay = delay
    }

    func run(
        activeAccountID: UUID?,
        accounts: [CodexAccount]
    ) async -> RefreshActiveAccountResult? {
        guard activeAccountID != nil else { return nil }

        if delay > .zero {
            try? await Task.sleep(for: delay)
        }

        do {
            return try await refreshActiveAccountUseCase.run(accounts: accounts)
        } catch {
            silentPostActionRefreshLogger.log("Silent post-action refresh skipped: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
