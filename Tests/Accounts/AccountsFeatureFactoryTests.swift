import Foundation
import Testing

@testable import CodexPill

@MainActor
struct AccountsFeatureFactoryTests {
    @Test
    func makeControllerLoadsSavedAccounts() throws {
        let repository = try makeRepository()
        let account = CodexAccount(
            id: UUID(),
            name: "Business",
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "business@example.com",
            planType: nil,
            rateLimits: nil,
            identity: .empty
        )
        try repository.bootstrapStorage()
        try repository.saveAccounts([account])

        let factory = AccountsFeatureFactory(
            repository: repository,
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: CodexAppProcessProbe(),
            accountStatusClient: DisabledAccountStatusClient()
        )

        let controller = factory.makeController()
        controller.load()

        #expect(controller.accounts.count == 1)
        #expect(controller.accounts.first?.id == account.id)
        #expect(controller.accounts.first?.name == "Business")
        #expect(controller.statusMessage == "Loaded 1 account(s)")
    }

    private func makeRepository() throws -> AccountRepository {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AccountsFeatureFactoryTests-\(UUID().uuidString)", isDirectory: true)
        return try AccountRepository(
            isolatedRootDirectory: directory
        )
    }
}
