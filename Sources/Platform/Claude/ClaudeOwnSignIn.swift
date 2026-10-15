import Foundation
import OSLog

private let claudeSignInLogger = Logger(subsystem: "com.raphhgg.refill", category: "ClaudeSignIn")

/// Why Refill's own sign-in was not renewed this time. Its tokens stay, and a later read tries again.
enum ClaudeRefreshFailure: Equatable, Sendable {
    case network
    /// The token endpoint refused with something other than `invalid_grant`.
    case rejected
    case malformed
    /// The refresh marker could not be saved, so no refresh token was sent.
    case saveFailed
    /// Another Refill process held the refresh lock too long.
    case busy
}

enum ClaudeOwnToken: Equatable, Sendable {
    case token(ClaudeSignIn)
    /// There is no sign-in, or Anthropic rejected it. Only a new browser sign-in helps.
    case signInRequired
    case keychainAccessNeeded
    case unreadable
    case unavailable(ClaudeRefreshFailure)
}

/// Refill's own Claude sign-in and its renewal. Claude rotates the refresh token on every refresh and accepts each
/// one once, so a refresh token is never sent unless the store first records that it is about to be spent:
///
/// 1. Under the refresh lock, read the item again. One still marked `refreshPending` never saved its result, so its
///    refresh token is presumed spent: delete the item and ask for a new sign-in.
/// 2. Save the item with `refreshPending` set. If that fails, send nothing.
/// 3. Send the refresh token, then save the new pair with the marker cleared. A pair the store refuses stays in memory
///    and wins over the store until a save succeeds.
///
/// A crash between 2 and 3 costs only Refill's own sign-in. Claude Code's sign-in is never read or written here.
actor ClaudeOwnSignIn {
    private let signInStore: any ClaudeSignInStoring
    private let tokenEndpoint: any ClaudeTokenEndpoint
    private let lock: ClaudeRefreshLock
    /// A new sign-in the store refused. The stored refresh token may already be spent, so it is never sent while this
    /// is set.
    private var unsaved: ClaudeSignIn?
    private var refreshInFlight: Task<ClaudeOwnToken, Never>?

    init(store: any ClaudeSignInStoring, tokenEndpoint: any ClaudeTokenEndpoint, lock: ClaudeRefreshLock) {
        signInStore = store
        self.tokenEndpoint = tokenEndpoint
        self.lock = lock
    }

    /// A token for one usage read, renewed first when it expires within `ClaudeSignIn.refreshMargin`. A renewal that
    /// fails for any reason but `invalid_grant` keeps the current token while it is unexpired.
    func token(now: Date, allowingPrompt: Bool) async -> ClaudeOwnToken {
        var current = unsaved
        if current == nil {
            switch signInStore.read(allowingPrompt: allowingPrompt) {
            case .notFound: return .signInRequired
            case .needsPermission: return .keychainAccessNeeded
            case .failed: return .unreadable
            case let .found(signIn, refreshPending):
                guard refreshPending || signIn.needsRefresh(at: now) else { return .token(signIn) }
                current = signIn
            }
        }
        let result = await refresh(now: now, rejecting: nil, allowingPrompt: allowingPrompt)
        if case .unavailable = result, let current, !current.isExpired(at: now) {
            return .token(current)
        }
        return result
    }

    /// Anthropic answered 401 to `rejected`. Uses the stored token when another Refill process already renewed it,
    /// and renews otherwise.
    func refreshAfterRejection(of rejected: ClaudeAccessToken, now: Date) async -> ClaudeOwnToken {
        await refresh(now: now, rejecting: rejected, allowingPrompt: false)
    }

    /// Saves a new browser sign-in. Returns false when the store refused it: it then lasts until Refill quits.
    func store(_ signIn: ClaudeSignIn) async -> Bool {
        let saved = await lock.withLock {
            signInStore.save(signIn, refreshPending: false, allowingPrompt: true)
        } ?? false
        unsaved = saved ? nil : signIn
        log(saved ? "sign-in saved" : "sign-in not saved")
        return saved
    }

    /// Deletes the item, then asks Anthropic to revoke its refresh token, best effort. Returns whether the item is gone.
    func signOut() async -> Bool {
        let outcome = await lock.withLock { () -> (deleted: Bool, refreshToken: ClaudeRefreshToken?) in
            let stored: ClaudeSignIn? = if case let .found(signIn, _) = signInStore.read(allowingPrompt: false) { signIn } else { nil }
            let refreshToken = (unsaved ?? stored)?.refreshToken
            unsaved = nil
            return (signInStore.delete(), refreshToken)
        }
        guard let outcome else {
            log("busy")
            return false
        }
        if let refreshToken = outcome.refreshToken {
            await tokenEndpoint.revoke(refreshToken)
        }
        log(outcome.deleted ? "signed out" : "sign-out failed")
        return outcome.deleted
    }

    /// One renewal at a time in this process, and one at a time across processes through the lock.
    private func refresh(now: Date, rejecting rejected: ClaudeAccessToken?, allowingPrompt: Bool) async -> ClaudeOwnToken {
        if let refreshInFlight {
            return await refreshInFlight.value
        }
        let task = Task {
            await lock.withLock {
                await refreshHoldingLock(now: now, rejecting: rejected, allowingPrompt: allowingPrompt)
            } ?? .unavailable(.busy)
        }
        refreshInFlight = task
        let result = await task.value
        refreshInFlight = nil
        if result == .unavailable(.busy) {
            log("busy")
        }
        return result
    }

    private func refreshHoldingLock(now: Date, rejecting rejected: ClaudeAccessToken?, allowingPrompt: Bool) async -> ClaudeOwnToken {
        let current: ClaudeSignIn
        if let unsaved {
            if signInStore.save(unsaved, refreshPending: false, allowingPrompt: allowingPrompt) {
                self.unsaved = nil
            }
            current = unsaved
        } else {
            switch signInStore.read(allowingPrompt: allowingPrompt) {
            case .notFound:
                return .signInRequired
            case .needsPermission:
                return .keychainAccessNeeded
            case .failed:
                return .unreadable
            case .found(_, refreshPending: true):
                _ = signInStore.delete()
                log("unfinished")
                return .signInRequired
            case let .found(stored, refreshPending: false):
                current = stored
            }
        }
        if !current.needsRefresh(at: now), current.accessToken != rejected {
            return .token(current)
        }

        guard signInStore.save(current, refreshPending: true, allowingPrompt: allowingPrompt) else {
            log("save_failed")
            return .unavailable(.saveFailed)
        }
        log("attempt")
        do throws(ClaudeTokenError) {
            let refreshed = try await tokenEndpoint.refresh(current, now: now)
            let saved = signInStore.save(refreshed, refreshPending: false, allowingPrompt: allowingPrompt)
                || signInStore.save(refreshed, refreshPending: false, allowingPrompt: allowingPrompt)
            unsaved = saved ? nil : refreshed
            log(saved ? "ok" : "save_failed")
            return .token(refreshed)
        } catch {
            let failure: ClaudeRefreshFailure
            switch error {
            case .invalidGrant:
                _ = signInStore.delete()
                unsaved = nil
                log("invalid_grant")
                return .signInRequired
            case .transport: failure = .network
            case .rejected: failure = .rejected
            case .malformedResponse: failure = .malformed
            }
            // The token was not accepted, so clear the marker and keep it for the next try.
            unsaved = signInStore.save(current, refreshPending: false, allowingPrompt: allowingPrompt) ? nil : current
            log(failure.logCategory)
            return .unavailable(failure)
        }
    }

    /// `category` is one of a fixed set of words. It never carries a token, an email, a code, or a URL.
    private func log(_ category: StaticString) {
        let text = "\(category)"
        claudeSignInLogger.notice("Claude sign-in: \(text, privacy: .public)")
    }
}

private extension ClaudeRefreshFailure {
    var logCategory: StaticString {
        switch self {
        case .network: "network"
        case .rejected: "rejected"
        case .malformed: "malformed"
        case .saveFailed: "save_failed"
        case .busy: "busy"
        }
    }
}
