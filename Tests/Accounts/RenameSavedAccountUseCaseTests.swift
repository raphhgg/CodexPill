import Foundation
import Testing

@testable import CodexPill

struct RenameSavedAccountUseCaseTests {
    @Test
    func runPersistsRenamedAccountAndPreservesIdentity() throws {
        let account = makeAccount(name: "Business 1")
        let other = makeAccount(name: "Personal")
        let repository = RenamingCatalogProbe()
        let useCase = RenameSavedAccountUseCase(repository: repository)

        let result = try useCase.run(
            account: account,
            newName: "Business Main",
            accounts: [account, other]
        )

        #expect(result.renamedAccount.name == "Business Main")
        #expect(result.renamedAccount.id == account.id)
        #expect(result.accounts.map(\.name) == ["Business Main", "Personal"])
        #expect(repository.savedAccounts?.map(\.name) == ["Business Main", "Personal"])
    }

    @Test
    func runChangesOnlyDisplayLabelForLoadedAccount() throws {
        let account = makeLoadedAccount(name: "Business 1")
        let repository = RenamingCatalogProbe()
        let useCase = RenameSavedAccountUseCase(repository: repository)

        let result = try useCase.run(
            account: account,
            newName: "Business Main",
            accounts: [account]
        )

        #expect(result.renamedAccount.name == "Business Main")
        #expect(result.renamedAccount.id == account.id)
        #expect(result.renamedAccount.snapshotFileName == account.snapshotFileName)
        #expect(result.renamedAccount.createdAt == account.createdAt)
        #expect(result.renamedAccount.updatedAt == account.updatedAt)
        #expect(result.renamedAccount.email == account.email)
        #expect(result.renamedAccount.planType == account.planType)
        #expect(result.renamedAccount.rateLimits == account.rateLimits)
        #expect(result.renamedAccount.identity == account.identity)
        #expect(repository.savedAccounts?.first?.snapshotFileName == account.snapshotFileName)
        #expect(repository.savedAccounts?.first?.rateLimits == account.rateLimits)
        #expect(repository.savedAccounts?.first?.identity == account.identity)
    }

    @Test
    func runDoesNotChangeUpdatedAtForLabelOnlyRename() throws {
        let createdAt = Date(timeIntervalSince1970: 100)
        let updatedAt = Date(timeIntervalSince1970: 200)
        let fetchedAt = Date(timeIntervalSince1970: 300)
        let account = CodexAccount(
            id: UUID(),
            name: "Business 1",
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: createdAt,
            updatedAt: updatedAt,
            email: "business@example.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "team",
                primary: nil,
                secondary: nil,
                fetchedAt: fetchedAt
            ),
            identity: CodexAccountIdentity(
                snapshotFingerprint: UUID().uuidString,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "business@example.com")
            )
        )
        let repository = RenamingCatalogProbe()
        let useCase = RenameSavedAccountUseCase(repository: repository)

        let result = try useCase.run(
            account: account,
            newName: "Business Main",
            accounts: [account]
        )

        #expect(result.renamedAccount.updatedAt == updatedAt)
        #expect(result.renamedAccount.lastRemoteRefreshAt == fetchedAt)
        #expect(repository.savedAccounts?.first?.updatedAt == updatedAt)
    }

    @Test
    func runPersistsCatalogInDisplayNameOrderAfterSuccessfulRename() throws {
        let account = makeAccount(name: "Zebra")
        let first = makeAccount(name: "Alpha")
        let last = makeAccount(name: "Omega")
        let repository = RenamingCatalogProbe()
        let useCase = RenameSavedAccountUseCase(repository: repository)

        let result = try useCase.run(
            account: account,
            newName: "Beta",
            accounts: [account, last, first]
        )

        #expect(result.accounts.map(\.name) == ["Alpha", "Beta", "Omega"])
        #expect(repository.savedAccounts?.map(\.name) == ["Alpha", "Beta", "Omega"])
        #expect(result.renamedAccount.id == account.id)
        #expect(result.renamedAccount.snapshotFileName == account.snapshotFileName)
    }

    @Test
    func runRejectsDuplicateNameCaseInsensitively() {
        let account = makeAccount(name: "Business 1")
        let other = makeAccount(name: "Personal")
        let useCase = RenameSavedAccountUseCase(repository: RenamingCatalogProbe())

        #expect(throws: RenameSavedAccountUseCaseError.duplicateAccountName) {
            try useCase.run(
                account: account,
                newName: " personal ",
                accounts: [account, other]
            )
        }
    }

    @Test
    func runRejectsBlankName() {
        let account = makeAccount(name: "Business 1")
        let useCase = RenameSavedAccountUseCase(repository: RenamingCatalogProbe())

        #expect(throws: RenameSavedAccountUseCaseError.emptyAccountName) {
            try useCase.run(
                account: account,
                newName: "   ",
                accounts: [account]
            )
        }
    }

    @Test
    func runAllowsEquivalentNameForSameAccountWithoutChangingCatalog() throws {
        let account = makeAccount(name: "Business 1")
        let repository = RenamingCatalogProbe()
        let useCase = RenameSavedAccountUseCase(repository: repository)

        let result = try useCase.run(
            account: account,
            newName: "  business 1  ",
            accounts: [account]
        )

        #expect(result.renamedAccount.name == "Business 1")
        #expect(result.accounts == [account])
        #expect(repository.savedAccounts == [account])
    }

    private func makeAccount(name: String) -> CodexAccount {
        CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "\(name.lowercased())@example.com",
            planType: nil,
            rateLimits: nil,
            identity: CodexAccountIdentity(
                snapshotFingerprint: UUID().uuidString,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "\(name.lowercased())@example.com")
            )
        )
    }

    private func makeLoadedAccount(name: String) -> CodexAccount {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let updatedAt = Date(timeIntervalSince1970: 2_000)
        let fetchedAt = Date(timeIntervalSince1970: 3_000)
        return CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "business-1.json",
            createdAt: createdAt,
            updatedAt: updatedAt,
            email: "business@example.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: "synthetic-limit",
                limitName: "Synthetic Team",
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: 42,
                    resetsAt: fetchedAt.addingTimeInterval(3_600),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 68,
                    resetsAt: fetchedAt.addingTimeInterval(86_400),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: fetchedAt
            ),
            identity: CodexAccountIdentity(
                stableAccountID: "synthetic-stable-account",
                snapshotFingerprint: "synthetic-fingerprint",
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "business@example.com")
            )
        )
    }
}

private final class RenamingCatalogProbe: AccountCatalogStore, @unchecked Sendable {
    var savedAccounts: [CodexAccount]?

    func saveAccounts(_ accounts: [CodexAccount]) throws {
        savedAccounts = accounts
    }
}
