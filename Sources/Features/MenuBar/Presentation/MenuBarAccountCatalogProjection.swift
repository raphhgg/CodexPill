import Foundation

struct MenuBarAccountCatalogEntry: Equatable {
    let account: CodexAccount
    let isActive: Bool
}

/// Saved accounts for the menu: the active one first, then the rest ranked by room left.
struct MenuBarAccountCatalogProjection {
    private let inactiveAccountAvailabilityRanking = InactiveAccountAvailabilityRanking()

    let activeAccount: CodexAccount?
    let inactiveAccounts: [CodexAccount]

    var allSavedAccounts: [CodexAccount] {
        [activeAccount].compactMap { $0 } + inactiveAccounts
    }

    var accountCatalogEntries: [MenuBarAccountCatalogEntry] {
        let activeEntries = [activeAccount].compactMap { $0 }.map { MenuBarAccountCatalogEntry(account: $0, isActive: true) }
        let nonActiveEntries = inactiveAccounts
            .sorted(by: inactiveAccountAvailabilityRanking.compare)
            .map { MenuBarAccountCatalogEntry(account: $0, isActive: false) }
        return activeEntries + nonActiveEntries
    }
}
