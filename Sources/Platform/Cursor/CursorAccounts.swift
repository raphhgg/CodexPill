import Foundation
import OSLog

private let cursorAccountsLogger = Logger(subsystem: "com.raphhgg.codexpill", category: "CursorAccounts")

enum CursorAccountsError: Error, Equatable {
    case cursorNotInstalled
    case signedOut
    case accountNotFound
}

/// Saved Cursor sign-ins and switching between them.
///
/// Switching writes only the `CursorSignIn.keys` rows of Cursor's `state.vscdb`, and only while Cursor is
/// not running. Quitting and opening Cursor go through `CursorAppProcessClient`.
struct CursorAccounts: Sendable {
    let database: CursorStateDatabase
    let store: any CursorAccountStore
    let app: any CursorAppProcessClient

    func savedAccounts() throws -> [CursorSavedAccount] {
        try store.load()
    }

    /// The saved account Cursor is signed in as, or nil when Cursor is signed out or uses an unsaved account.
    func activeAccountID() throws -> UUID? {
        guard database.exists, let current = try currentSignIn() else { return nil }
        return try store.load().first { $0.userID == current.userID }?.id
    }

    /// Saves Cursor's current sign-in under `name`. Saving an account that is already saved refreshes its
    /// tokens and renames it instead of adding a second entry.
    @discardableResult
    func captureCurrent(named name: String) throws -> CursorSavedAccount {
        guard database.exists else { throw CursorAccountsError.cursorNotInstalled }
        guard let signIn = try currentSignIn() else { throw CursorAccountsError.signedOut }

        var accounts = try store.load()
        let account: CursorSavedAccount
        if let index = accounts.firstIndex(where: { $0.userID == signIn.userID }) {
            accounts[index].name = name
            accounts[index].signIn = signIn
            account = accounts[index]
        } else {
            account = CursorSavedAccount(id: UUID(), name: name, signIn: signIn)
            accounts.append(account)
        }
        try store.save(accounts)
        return account
    }

    func rename(_ id: UUID, to name: String) throws {
        var accounts = try store.load()
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { throw CursorAccountsError.accountNotFound }
        accounts[index].name = name
        try store.save(accounts)
    }

    /// Forgets a saved account. Cursor itself is not touched, even when it is signed in as that account.
    func remove(_ id: UUID) throws {
        var accounts = try store.load()
        accounts.removeAll { $0.id == id }
        try store.save(accounts)
    }

    /// Signs Cursor in as a saved account: quits Cursor, saves the outgoing sign-in (Cursor may have rotated
    /// its tokens since it was captured), writes the saved rows in one transaction, and opens Cursor.
    ///
    /// If Cursor does not quit, nothing is written. If anything fails after Cursor quit, Cursor is opened
    /// again on the sign-in it had.
    func activate(_ id: UUID) async throws {
        var accounts = try store.load()
        guard accounts.contains(where: { $0.id == id }) else { throw CursorAccountsError.accountNotFound }
        guard database.exists else { throw CursorAccountsError.cursorNotInstalled }

        try await app.quit()

        do {
            try switchSignIn(to: id, accounts: &accounts)
        } catch {
            cursorAccountsLogger.error("Cursor switch failed, reopening Cursor unchanged")
            try? await app.open()
            throw error
        }

        try await app.open()
    }

    private func switchSignIn(to id: UUID, accounts: inout [CursorSavedAccount]) throws {
        // Reading through a write connection first folds Cursor's WAL into the database and fails while any
        // Cursor process still holds it.
        let outgoing = CursorSignIn(values: try database.valuesForWrite(forKeys: CursorSignIn.keys))

        if let outgoing {
            if let index = accounts.firstIndex(where: { $0.userID == outgoing.userID }) {
                accounts[index].signIn = outgoing
            } else {
                // Keep an unsaved sign-in so switching never strands it.
                accounts.append(CursorSavedAccount(id: UUID(), name: outgoing.email ?? "Cursor", signIn: outgoing))
            }
            try store.save(accounts)
        }

        guard let target = accounts.first(where: { $0.id == id }) else { throw CursorAccountsError.accountNotFound }
        if target.userID == outgoing?.userID {
            cursorAccountsLogger.log("Cursor is already signed in as the chosen account")
            return
        }

        try database.write(target.signIn.values, removing: CursorSignIn.keys)
        cursorAccountsLogger.log("Wrote the saved Cursor sign-in")
    }

    private func currentSignIn() throws -> CursorSignIn? {
        CursorSignIn(values: try database.values(forKeys: CursorSignIn.keys))
    }
}
