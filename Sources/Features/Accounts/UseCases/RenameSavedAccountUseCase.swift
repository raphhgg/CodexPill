import Foundation

struct RenameSavedAccountResult {
    let accounts: [CodexAccount]
    let renamedAccount: CodexAccount
}

struct RenameSavedAccountUseCase {
    private let repository: AccountCatalogPersisting

    init(repository: AccountCatalogPersisting) {
        self.repository = repository
    }

    func run(
        account: CodexAccount,
        newName: String,
        accounts: [CodexAccount]
    ) throws -> RenameSavedAccountResult {
        let resolvedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedName.isEmpty else {
            throw RenameSavedAccountUseCaseError.emptyAccountName
        }

        if account.name.caseInsensitiveCompare(resolvedName) == .orderedSame {
            try repository.saveAccounts(accounts)
            return RenameSavedAccountResult(
                accounts: accounts,
                renamedAccount: account
            )
        }

        guard !accounts.contains(where: {
            $0.id != account.id && $0.name.caseInsensitiveCompare(resolvedName) == .orderedSame
        }) else {
            throw RenameSavedAccountUseCaseError.duplicateAccountName
        }

        var renamedAccount = account
        renamedAccount.name = resolvedName

        let updatedAccounts = accounts
            .map { $0.id == account.id ? renamedAccount : $0 }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        try repository.saveAccounts(updatedAccounts)

        return RenameSavedAccountResult(
            accounts: updatedAccounts,
            renamedAccount: renamedAccount
        )
    }
}

enum RenameSavedAccountUseCaseError: LocalizedError {
    case emptyAccountName
    case duplicateAccountName

    var errorDescription: String? {
        switch self {
        case .emptyAccountName:
            "Account name cannot be empty."
        case .duplicateAccountName:
            "An account with that name already exists."
        }
    }
}
