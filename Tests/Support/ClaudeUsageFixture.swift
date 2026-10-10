import Foundation

@testable import CodexPill

/// A `ClaudeCodeUsage` over an isolated defaults suite, a temp Claude config folder, a settable Claude Code Keychain
/// item, an in-memory CodexPill sign-in item, a scripted token endpoint and browser sign-in, and a settable usage
/// response. All tokens are fake.
final class ClaudeUsageFixture: ClaudeKeychainReading, ClaudeUsageWebClient, ClaudeSignInStoring, ClaudeTokenEndpoint,
    ClaudeSignInAuthorizing, @unchecked Sendable
{
    static let fakeAccessToken = "fake-claude-access-token"
    static let fakeOwnAccessToken = "fake-codexpill-access-token"
    static let fakeOwnRefreshToken = "fake-codexpill-refresh-token"
    static let fakeRotatedAccessToken = "fake-rotated-access-token"
    static let fakeRotatedRefreshToken = "fake-rotated-refresh-token"

    /// Synthetic `/api/oauth/usage` response with an Opus window that CodexPill ignores.
    static let usageResponse = #"""
    {"five_hour":{"utilization":64.4,"resets_at":"2026-10-10T15:00:00.000000+00:00"},
     "seven_day":{"utilization":21,"resets_at":"2026-10-14T09:00:00+00:00"},
     "seven_day_opus":{"utilization":80,"resets_at":"2026-10-14T09:00:00+00:00"}}
    """#

    let settings: ClaudeUsageSettingsStore
    let defaults: UserDefaults
    let configDirectory: URL
    private(set) var usage: ClaudeCodeUsage!
    private let suiteName = "ClaudeUsageFixture-\(UUID().uuidString)"
    private let lock = NSLock()
    private var currentKeychainItem: Data?
    private var keychainNeedsPermissionWithoutPrompt = false
    private var currentResponse: Result<Data, ClaudeUsageWebError> = .failure(.transport)
    private var keychainReads: [Bool] = []
    private var sentTokens: [String] = []
    private var rejectedTokens: Set<String> = []
    private var keepsOwnItemOnDelete = false
    private var refusesSaves = false
    private var ownItem: Data?
    private var currentRefreshResult: Result<ClaudeSignIn, ClaudeTokenError> = .failure(.transport)
    private var refreshedTokens: [String] = []
    private var revokedTokens: [String] = []
    private var refreshGate: CheckedContinuation<Void, Never>?
    private var holdsRefresh = false
    private var signInWaiter: CheckedContinuation<ClaudeSignIn, any Error>?
    private var signInStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var signInsStarted = 0

    init(refreshInterval: TimeInterval = ProviderUsageRuntime.refreshInterval) {
        defaults = UserDefaults(suiteName: suiteName)!
        settings = ClaudeUsageSettingsStore(userDefaults: defaults)
        configDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeUsageFixture-\(UUID().uuidString)", isDirectory: true)
        usage = ClaudeCodeUsage(
            settings: settings,
            client: ClaudeUsageClient(
                claudeCode: ClaudeCredentialsSource(configDirectory: configDirectory, keychain: self),
                signInStore: self,
                tokenEndpoint: self,
                webClient: self
            ),
            signInFlow: self,
            refreshInterval: refreshInterval
        )
    }

    static func credentialsJSON(expiresAt: Date, subscriptionType: String = "max") -> String {
        let milliseconds = Int(expiresAt.timeIntervalSince1970 * 1_000)
        return #"{"claudeAiOauth":{"accessToken":"\#(fakeAccessToken)","refreshToken":"fake-claude-refresh-token","expiresAt":\#(milliseconds),"scopes":["user:inference","user:profile"],"subscriptionType":"\#(subscriptionType)"}}"#
    }

    static func ownSignIn(expiresAt: Date, rotated: Bool = false) -> ClaudeSignIn {
        ClaudeSignIn(
            accessToken: ClaudeAccessToken(rotated ? fakeRotatedAccessToken : fakeOwnAccessToken)!,
            refreshToken: ClaudeRefreshToken(rotated ? fakeRotatedRefreshToken : fakeOwnRefreshToken)!,
            expiresAt: expiresAt
        )
    }

    /// Puts a fake Claude Code sign-in in the Keychain. `needsPermission` makes reads without a prompt fail like a fresh ACL.
    func signInToKeychain(expiresAt: Date, needsPermission: Bool = false) {
        lock.withLock {
            currentKeychainItem = Data(Self.credentialsJSON(expiresAt: expiresAt).utf8)
            keychainNeedsPermissionWithoutPrompt = needsPermission
        }
    }

    func writeCredentialsFile(_ json: String) throws {
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: configDirectory.appendingPathComponent(".credentials.json"))
    }

    var keychainItem: Data? {
        get { lock.withLock { currentKeychainItem } }
        set { lock.withLock { currentKeychainItem = newValue } }
    }

    /// CodexPill's own sign-in item, decoded.
    var ownSignIn: ClaudeSignIn? {
        get { lock.withLock { ownItem.flatMap(ClaudeSignIn.init(keychainData:)) } }
        set { lock.withLock { ownItem = newValue?.keychainData } }
    }

    var response: Result<Data, ClaudeUsageWebError> {
        get { lock.withLock { currentResponse } }
        set { lock.withLock { currentResponse = newValue } }
    }

    /// Makes deleting CodexPill's own sign-in item fail, like a Keychain that refuses the change.
    func failDeletes() {
        lock.withLock { keepsOwnItemOnDelete = true }
    }

    /// Makes saving CodexPill's own sign-in item fail, like a Keychain that refuses the change.
    func failSaves() {
        lock.withLock { refusesSaves = true }
    }

    /// Access tokens the usage endpoint answers with 401.
    var rejectedAccessTokens: Set<String> {
        get { lock.withLock { rejectedTokens } }
        set { lock.withLock { rejectedTokens = newValue } }
    }

    var refreshResult: Result<ClaudeSignIn, ClaudeTokenError> {
        get { lock.withLock { currentRefreshResult } }
        set { lock.withLock { currentRefreshResult = newValue } }
    }

    var requestCount: Int {
        lock.withLock { sentTokens.count }
    }

    /// The access token sent with each usage request, in order.
    var usageRequestTokens: [String] {
        lock.withLock { sentTokens }
    }

    /// The refresh token sent with each refresh request, in order.
    var refreshRequestTokens: [String] {
        lock.withLock { refreshedTokens }
    }

    var revokedRefreshTokens: [String] {
        lock.withLock { revokedTokens }
    }

    /// `allowingPrompt` for each Claude Code Keychain read, in order.
    var keychainReadPrompts: [Bool] {
        lock.withLock { keychainReads }
    }

    func credentialsData(allowingPrompt: Bool) -> ClaudeKeychainRead {
        lock.withLock {
            keychainReads.append(allowingPrompt)
            guard let currentKeychainItem else { return .notFound }
            if keychainNeedsPermissionWithoutPrompt && !allowingPrompt {
                return .needsPermission
            }
            keychainNeedsPermissionWithoutPrompt = false
            return .found(currentKeychainItem)
        }
    }

    func usage(using token: ClaudeAccessToken) async throws(ClaudeUsageWebError) -> Data {
        let (response, rejected) = lock.withLock {
            sentTokens.append(token.exposedValue)
            return (currentResponse, rejectedTokens.contains(token.exposedValue))
        }
        if rejected { throw .unauthorized }
        return try response.get()
    }

    func read(allowingPrompt _: Bool) -> ClaudeKeychainRead {
        lock.withLock { ownItem.map(ClaudeKeychainRead.found) ?? .notFound }
    }

    func save(_ signIn: ClaudeSignIn, allowingPrompt _: Bool) -> Bool {
        lock.withLock {
            guard !refusesSaves else { return false }
            ownItem = signIn.keychainData
            return true
        }
    }

    func delete() -> Bool {
        lock.withLock {
            guard !keepsOwnItemOnDelete else { return false }
            ownItem = nil
            return true
        }
    }

    func exchange(code _: String, pkce _: ClaudePKCE, state _: String, redirectURI _: URL, now _: Date) async throws(ClaudeTokenError) -> ClaudeSignIn {
        throw .transport
    }

    /// Makes refreshes wait until `releaseRefresh()`, so a test can start two reads at once.
    func holdRefreshes() {
        lock.withLock { holdsRefresh = true }
    }

    func releaseRefresh() {
        let gate = lock.withLock {
            holdsRefresh = false
            defer { refreshGate = nil }
            return refreshGate
        }
        gate?.resume()
    }

    var isRefreshWaiting: Bool {
        lock.withLock { refreshGate != nil }
    }

    func refresh(_ refreshToken: ClaudeRefreshToken, now _: Date) async throws(ClaudeTokenError) -> ClaudeSignIn {
        lock.withLock { refreshedTokens.append(refreshToken.exposedValue) }
        await withCheckedContinuation { continuation in
            let holds = lock.withLock {
                if holdsRefresh { refreshGate = continuation }
                return holdsRefresh
            }
            if !holds { continuation.resume() }
        }
        return try refreshResult.get()
    }

    func revoke(_ refreshToken: ClaudeRefreshToken) async {
        lock.withLock { revokedTokens.append(refreshToken.exposedValue) }
    }

    /// The scripted browser sign-in waits until the test finishes it with `finishSignIn(with:)` or cancels it.
    func signIn() async throws -> ClaudeSignIn {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let started = lock.withLock {
                    signInWaiter = continuation
                    signInsStarted += 1
                    defer { signInStartedWaiters = [] }
                    return signInStartedWaiters
                }
                started.forEach { $0.resume() }
            }
        } onCancel: {
            finishSignIn(with: .failure(CancellationError()))
        }
    }

    func waitUntilSignInStarted() async {
        await withCheckedContinuation { continuation in
            let started = lock.withLock {
                if signInWaiter == nil { signInStartedWaiters.append(continuation) }
                return signInWaiter != nil
            }
            if started { continuation.resume() }
        }
    }

    var browserSignInCount: Int {
        lock.withLock { signInsStarted }
    }

    func finishSignIn(with result: Result<ClaudeSignIn, any Error>) {
        let waiter = lock.withLock {
            defer { signInWaiter = nil }
            return signInWaiter
        }
        waiter?.resume(with: result)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: configDirectory)
    }
}
