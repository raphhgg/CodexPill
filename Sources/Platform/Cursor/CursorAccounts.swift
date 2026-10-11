import Foundation
import OSLog

private let cursorAccountsLogger = Logger(subsystem: "com.raphhgg.codexpill", category: "CursorAccounts")

enum CursorAccountsError: Error, Equatable, Sendable {
    case cursorNotInstalled
    case signedOut
    case accountNotFound
    /// Refill's saved-account Keychain item could not be read or written.
    case savedAccountsUnreadable
    case stateUnreadable
    /// Cursor is still running, for example because it is asking about unsaved changes. Nothing was written.
    case cursorDidNotQuit
    /// A Cursor helper still holds the database after Cursor quit. Nothing was written.
    case cursorBusy
    /// The write failed and was rolled back, so Cursor keeps the sign-in it had.
    case writeFailed
    /// The switch was written, but Cursor could not be opened again.
    case reopenFailed
    /// This build has no account switching, as in isolated runs.
    case switchingUnavailable
}

/// Saved Cursor sign-ins and switching between them.
///
/// Switching writes only the `CursorSignIn.keys` rows of Cursor's `state.vscdb`, and only while Cursor is
/// not running. Quitting and opening Cursor go through `CursorAppProcessClient`.
struct CursorAccounts: Sendable {
    let database: CursorStateDatabase
    let store: any CursorAccountStore
    let app: any CursorAppProcessClient

    func savedAccounts() throws(CursorAccountsError) -> [CursorSavedAccount] {
        try loadAccounts()
    }

    /// The saved account Cursor is signed in as, or nil when Cursor is signed out or uses an unsaved account.
    func activeAccountID() throws(CursorAccountsError) -> UUID? {
        guard database.exists, let current = try currentSignIn() else { return nil }
        return try loadAccounts().first { $0.userID == current.userID }?.id
    }

    /// Saves Cursor's current sign-in under `name`, or under its email when `name` is nil. Saving an account that
    /// is already saved refreshes its tokens, and renames it when a name is given, instead of adding a second entry.
    @discardableResult
    func captureCurrent(named name: String? = nil) throws(CursorAccountsError) -> CursorSavedAccount {
        guard database.exists else { throw .cursorNotInstalled }
        guard let signIn = try currentSignIn() else { throw .signedOut }
        return try add(signIn, named: name)
    }

    /// Saves Cursor's current sign-in when its user is not saved yet. Nil when there is nothing new to save: Cursor is
    /// signed out or its user is saved already.
    func saveCurrentIfNew() throws(CursorAccountsError) -> CursorSavedAccount? {
        guard
            database.exists,
            let signIn = try currentSignIn(),
            try !loadAccounts().contains(where: { $0.userID == signIn.userID })
        else {
            return nil
        }
        return try add(signIn)
    }

    /// Saves a sign-in Cursor made in a throwaway profile, the same way as `captureCurrent`.
    @discardableResult
    func add(_ signIn: CursorSignIn, named name: String? = nil) throws(CursorAccountsError) -> CursorSavedAccount {
        var accounts = try loadAccounts()
        let account: CursorSavedAccount
        if let index = accounts.firstIndex(where: { $0.userID == signIn.userID }) {
            if let name { accounts[index].name = name }
            accounts[index].signIn = signIn
            account = accounts[index]
        } else {
            account = CursorSavedAccount(id: UUID(), name: name ?? signIn.email ?? "Cursor", signIn: signIn)
            accounts.append(account)
        }
        try saveAccounts(accounts)
        return account
    }

    func savedAccount(_ id: UUID) throws(CursorAccountsError) -> CursorSavedAccount {
        guard let account = try loadAccounts().first(where: { $0.id == id }) else { throw .accountNotFound }
        return account
    }

    /// Keeps limits read with a saved sign-in, but only while that saved sign-in is still `readWith`. Returns false
    /// and changes nothing otherwise, for example when a switch saved tokens Cursor rotated in the meantime.
    @discardableResult
    func recordUsage(_ usage: CursorUsageSnapshot, for id: UUID, ifSignInUnchangedFrom readWith: CursorSignIn) -> Bool {
        guard var accounts = try? loadAccounts(),
              let index = accounts.firstIndex(where: { $0.id == id }),
              accounts[index].signIn == readWith
        else {
            return false
        }
        accounts[index].usage = usage
        return (try? saveAccounts(accounts)) != nil
    }

    func rename(_ id: UUID, to name: String) throws(CursorAccountsError) {
        var accounts = try loadAccounts()
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { throw .accountNotFound }
        accounts[index].name = name
        try saveAccounts(accounts)
    }

    /// Forgets a saved account. Cursor itself is not touched, even when it is signed in as that account.
    func remove(_ id: UUID) throws(CursorAccountsError) {
        var accounts = try loadAccounts()
        accounts.removeAll { $0.id == id }
        try saveAccounts(accounts)
    }

    /// Signs Cursor in as a saved account: quits Cursor, saves the outgoing sign-in (Cursor may have rotated
    /// its tokens since it was captured), writes the saved rows in one transaction, and opens Cursor.
    ///
    /// If Cursor does not quit, nothing is written. If anything fails after Cursor quit, Cursor is opened
    /// again on the sign-in it had.
    func activate(_ id: UUID) async throws(CursorAccountsError) {
        var accounts = try loadAccounts()
        guard accounts.contains(where: { $0.id == id }) else { throw .accountNotFound }
        guard database.exists else { throw .cursorNotInstalled }

        do {
            try await app.quit()
        } catch {
            throw .cursorDidNotQuit
        }

        do {
            try switchSignIn(to: id, accounts: &accounts)
        } catch {
            cursorAccountsLogger.error("Cursor switch failed, reopening Cursor unchanged")
            try? await app.open()
            throw error
        }

        do {
            try await app.open()
        } catch {
            throw .reopenFailed
        }
    }

    private func switchSignIn(to id: UUID, accounts: inout [CursorSavedAccount]) throws(CursorAccountsError) {
        // Reading through a write connection first folds Cursor's WAL into the database and fails while any
        // Cursor process still holds it.
        let outgoing: CursorSignIn?
        do {
            outgoing = CursorSignIn(values: try database.valuesForWrite(forKeys: CursorSignIn.keys))
        } catch CursorStateDatabaseError.busy {
            throw .cursorBusy
        } catch {
            throw .stateUnreadable
        }

        if let outgoing {
            if let index = accounts.firstIndex(where: { $0.userID == outgoing.userID }) {
                accounts[index].signIn = outgoing
            } else {
                // Keep an unsaved sign-in so switching never strands it.
                accounts.append(CursorSavedAccount(id: UUID(), name: outgoing.email ?? "Cursor", signIn: outgoing))
            }
            try saveAccounts(accounts)
        }

        guard let target = accounts.first(where: { $0.id == id }) else { throw .accountNotFound }
        if target.userID == outgoing?.userID {
            cursorAccountsLogger.log("Cursor is already signed in as the chosen account")
            return
        }

        do {
            try database.write(target.signIn.values, removing: CursorSignIn.keys)
        } catch CursorStateDatabaseError.busy {
            throw .cursorBusy
        } catch {
            throw .writeFailed
        }
        cursorAccountsLogger.log("Wrote the saved Cursor sign-in")
    }

    private func currentSignIn() throws(CursorAccountsError) -> CursorSignIn? {
        do {
            return CursorSignIn(values: try database.values(forKeys: CursorSignIn.keys))
        } catch {
            throw .stateUnreadable
        }
    }

    private func loadAccounts() throws(CursorAccountsError) -> [CursorSavedAccount] {
        do {
            return try store.load()
        } catch {
            throw .savedAccountsUnreadable
        }
    }

    private func saveAccounts(_ accounts: [CursorSavedAccount]) throws(CursorAccountsError) {
        do {
            try store.save(accounts)
        } catch {
            throw .savedAccountsUnreadable
        }
    }
}
