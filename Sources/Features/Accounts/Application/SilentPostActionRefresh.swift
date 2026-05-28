import Foundation
import OSLog

private let silentPostActionRefreshLogger = Logger(subsystem: "com.raphhgg.codexpill", category: "SilentPostActionRefresh")

struct SilentPostActionRefresh: Sendable {
    private let refreshActiveAccountUseCase: RefreshActiveAccountUseCase

    init(refreshActiveAccountUseCase: RefreshActiveAccountUseCase) {
        self.refreshActiveAccountUseCase = refreshActiveAccountUseCase
    }

    func run(
        after delay: Duration,
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
