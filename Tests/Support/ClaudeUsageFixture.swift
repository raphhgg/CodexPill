import Foundation

@testable import RUsage

/// A `ClaudeCodeUsage` over an isolated defaults suite, a temp Claude config folder, a settable Keychain item,
/// and a settable usage response. All tokens are fake.
final class ClaudeUsageFixture: ClaudeKeychainReading, ClaudeUsageWebClient, @unchecked Sendable {
    static let fakeAccessToken = "fake-claude-access-token"

    /// Synthetic `/api/oauth/usage` response with an Opus window that rusage ignores.
    static let usageResponse = #"""
    {"five_hour":{"utilization":64.4,"resets_at":"2026-10-10T15:00:00.000000+00:00"},
     "seven_day":{"utilization":21,"resets_at":"2026-10-14T09:00:00+00:00"},
     "seven_day_opus":{"utilization":80,"resets_at":"2026-10-14T09:00:00+00:00"}}
    """#

    let settings: SettingsCell<ClaudeSettings>
    let defaults: UserDefaults
    let configDirectory: URL
    private(set) var usage: ClaudeCodeUsage!
    private let suiteName = "ClaudeUsageFixture-\(UUID().uuidString)"
    private let lock = NSLock()
    private var currentKeychainItem: Data?
    private var keychainNeedsPermissionWithoutPrompt = false
    private var currentResponse: Result<Data, ClaudeUsageWebError> = .failure(.transport)
    private var keychainReads: [Bool] = []
    private var requests = 0

    init(refreshInterval: TimeInterval = ProviderUsageRuntime.refreshInterval) {
        defaults = UserDefaults(suiteName: suiteName)!
        settings = SettingsCell(preferences: Preferences(userDefaults: defaults))
        configDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeUsageFixture-\(UUID().uuidString)", isDirectory: true)
        let ownSignInFiles = configDirectory.appendingPathComponent("rusage", isDirectory: true)
        usage = ClaudeCodeUsage(
            settings: settings,
            client: ClaudeUsageClient(
                credentials: ClaudeCredentialsSource(configDirectory: configDirectory, keychain: self),
                ownSignIn: ClaudeOwnSignIn(
                    store: FileClaudeSignInStore(fileURL: ownSignInFiles.appendingPathComponent("claude-sign-in.json")),
                    tokenEndpoint: FakeClaudeTokenServer(),
                    lock: ClaudeRefreshLock(fileURL: ownSignInFiles.appendingPathComponent("claude-sign-in.lock"))
                ),
                webClient: self
            ),
            signInFlow: ScriptedClaudeSignInFlow(),
            refreshInterval: refreshInterval
        )
    }

    static func credentialsJSON(expiresAt: Date, subscriptionType: String = "max") -> String {
        let milliseconds = Int(expiresAt.timeIntervalSince1970 * 1_000)
        return #"{"claudeAiOauth":{"accessToken":"\#(fakeAccessToken)","refreshToken":"fake-claude-refresh-token","expiresAt":\#(milliseconds),"scopes":["user:inference","user:profile"],"subscriptionType":"\#(subscriptionType)"}}"#
    }

    /// Puts a fake sign-in in the Keychain. `needsPermission` makes reads without a prompt fail like a fresh ACL.
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

    var response: Result<Data, ClaudeUsageWebError> {
        get { lock.withLock { currentResponse } }
        set { lock.withLock { currentResponse = newValue } }
    }

    var requestCount: Int {
        lock.withLock { requests }
    }

    /// `allowingPrompt` for each Keychain read, in order.
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
        let response = lock.withLock {
            requests += 1
            return currentResponse
        }
        guard token.authorizationHeaderValue == "Bearer \(Self.fakeAccessToken)" else {
            throw ClaudeUsageWebError.unauthorized
        }
        return try response.get()
    }

    func profile(using _: ClaudeAccessToken) async -> ClaudeProfile? {
        nil
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: configDirectory)
    }
}
