import Foundation
import os

@testable import rusage

extension ClaudeSignIn {
    /// A sign-in with fake tokens, such as access `a1` and refresh `r1`.
    static func fake(access: String, refresh: String, expiresAt: Date, email: String? = nil, planName: String? = nil) -> ClaudeSignIn {
        ClaudeSignIn(
            accessToken: ClaudeAccessToken(access)!,
            refreshToken: ClaudeRefreshToken(refresh)!,
            expiresAt: expiresAt,
            email: email,
            planName: planName
        )
    }
}

/// What the store, the token server and the usage server saw, in one ordered stream.
final class ClaudeEventLog: Sendable {
    private let stored = OSAllocatedUnfairLock<[String]>(initialState: [])

    var events: [String] { stored.withLock { $0 } }

    func append(_ event: String) {
        stored.withLock { $0.append(event) }
    }
}

/// A temp directory with rusage's own sign-in file and lock file. Nothing here touches the real Keychain.
struct ClaudeOwnSignInFiles {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeOwnSignIn-\(UUID().uuidString)", isDirectory: true)

    var store: FileClaudeSignInStore { FileClaudeSignInStore(fileURL: root.appendingPathComponent("claude-sign-in.json")) }
    var lock: ClaudeRefreshLock { ClaudeRefreshLock(fileURL: root.appendingPathComponent("claude-sign-in.lock")) }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// A file store that logs each save and can refuse saves. `saveAnswers` answers the next saves in order; once it is
/// empty, every save gets `acceptsSaves`.
final class RecordingClaudeSignInStore: ClaudeSignInStoring, @unchecked Sendable {
    private struct State {
        var saveAnswers: [Bool] = []
        var acceptsSaves = true
    }

    let file: FileClaudeSignInStore
    private let log: ClaudeEventLog?
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(file: FileClaudeSignInStore, log: ClaudeEventLog? = nil) {
        self.file = file
        self.log = log
    }

    func answerSaves(_ answers: [Bool], thenAccept acceptsSaves: Bool = true) {
        state.withLock { $0 = State(saveAnswers: answers, acceptsSaves: acceptsSaves) }
    }

    func read(allowingPrompt: Bool) -> ClaudeSignInRead {
        file.read(allowingPrompt: allowingPrompt)
    }

    func save(_ signIn: ClaudeSignIn, refreshPending: Bool, allowingPrompt: Bool) -> Bool {
        log?.append("save(\(signIn.accessToken.exposedValue), pending: \(refreshPending))")
        let accepted = state.withLock { state in
            state.saveAnswers.isEmpty ? state.acceptsSaves : state.saveAnswers.removeFirst()
        }
        return accepted && file.save(signIn, refreshPending: refreshPending, allowingPrompt: allowingPrompt)
    }

    func delete() -> Bool {
        log?.append("delete")
        return file.delete()
    }
}

/// Claude's token endpoint over fake tokens. Each refresh token works once and rotates: `r1` gives `a2` and `r2`.
/// A refresh token sent again gets `invalid_grant`, as Anthropic answers a spent one.
final class FakeClaudeTokenServer: ClaudeTokenEndpoint, @unchecked Sendable {
    private struct State {
        var valid: Set<String>
        var generation: Int
        var refreshes: [String] = []
        var revoked: [String] = []
        var delay: Duration = .zero
        var failure: ClaudeTokenError?
    }

    private let log: ClaudeEventLog?
    private let state: OSAllocatedUnfairLock<State>

    /// `generation` is the number of the valid refresh token, so 1 means `r1` is valid.
    init(generation: Int = 1, log: ClaudeEventLog? = nil) {
        self.log = log
        state = OSAllocatedUnfairLock(initialState: State(valid: ["r\(generation)"], generation: generation))
    }

    /// The refresh tokens that reached the server, in order.
    var refreshes: [String] { state.withLock { $0.refreshes } }
    var revoked: [String] { state.withLock { $0.revoked } }

    /// How long each refresh takes to answer.
    func answer(after delay: Duration) {
        state.withLock { $0.delay = delay }
    }

    /// Every refresh fails this way, without spending the token, until it is set back to nil.
    func fail(with failure: ClaudeTokenError?) {
        state.withLock { $0.failure = failure }
    }

    func exchange(code _: String, pkce _: ClaudePKCE, state _: String, redirectURI _: URL, now _: Date) async throws(ClaudeTokenError) -> ClaudeSignIn {
        throw .transport
    }

    func refresh(_ current: ClaudeSignIn, now: Date) async throws(ClaudeTokenError) -> ClaudeSignIn {
        let token = current.refreshToken.exposedValue
        log?.append("refresh(\(token))")
        let delay = state.withLock { state in
            state.refreshes.append(token)
            return state.delay
        }
        try? await Task.sleep(for: delay)
        let outcome: Result<Int, ClaudeTokenError> = state.withLock { state in
            if let failure = state.failure { return .failure(failure) }
            guard state.valid.remove(token) != nil else { return .failure(.invalidGrant) }
            state.generation += 1
            state.valid.insert("r\(state.generation)")
            return .success(state.generation)
        }
        let next = try outcome.get()
        return .fake(access: "a\(next)", refresh: "r\(next)", expiresAt: now.addingTimeInterval(3_600), email: current.email, planName: current.planName)
    }

    func revoke(_ refreshToken: ClaudeRefreshToken) async {
        state.withLock { $0.revoked.append(refreshToken.exposedValue) }
    }
}

/// A browser sign-in that opens nothing and answers with the next result the test set.
final class ScriptedClaudeSignInFlow: ClaudeSignInAuthorizing, @unchecked Sendable {
    private let next = OSAllocatedUnfairLock<Result<ClaudeSignIn, ClaudeSignInError>>(initialState: .failure(.denied))

    func answer(_ result: Result<ClaudeSignIn, ClaudeSignInError>) {
        next.withLock { $0 = result }
    }

    func signIn() async throws -> ClaudeSignIn {
        try next.withLock { $0 }.get()
    }
}
