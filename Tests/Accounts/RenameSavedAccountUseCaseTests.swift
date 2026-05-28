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
}

private final class RenamingCatalogProbe: AccountCatalogStore, @unchecked Sendable {
    var savedAccounts: [CodexAccount]?

    func saveAccounts(_ accounts: [CodexAccount]) throws {
        savedAccounts = accounts
    }
}
