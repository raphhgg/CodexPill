import CryptoKit
import Foundation
import LocalAuthentication
import os
import Security

/// rusage's own Cursor sign-in, from "Use Another Account…". It is kept in rusage's own Keychain item, never in
/// Cursor's database.
struct CursorSignIn: Sendable, Equatable, CustomStringConvertible {
    let accessToken: String
    let refreshToken: String
    var email: String? = nil

    var token: CursorAccessToken? {
        CursorAccessToken(jwt: accessToken)
    }

    var description: String {
        "CursorSignIn(redacted)"
    }
}

enum CursorSignInRead: Sendable, Equatable {
    case notFound
    /// The item exists but macOS needs the user to allow rusage to read it.
    case needsPermission
    case failed
    case found(CursorSignIn)
}

/// Where rusage keeps its own Cursor sign-in. Cursor's own database is never written.
protocol CursorSignInStoring: Sendable {
    /// `allowingPrompt` is true only right after a user action, so background reads never show a Keychain prompt.
    func read(allowingPrompt: Bool) -> CursorSignInRead
    func save(_ signIn: CursorSignIn) -> Bool
    /// True when no item is left.
    func delete() -> Bool
}

/// The stored item's JSON, shared by the Keychain item and the file store.
enum CursorSignInRecord {
    static func data(for signIn: CursorSignIn) -> Data? {
        try? JSONEncoder().encode(Stored(accessToken: signIn.accessToken, refreshToken: signIn.refreshToken, email: signIn.email))
    }

    static func read(_ data: Data) -> CursorSignInRead {
        guard let item = try? JSONDecoder().decode(Stored.self, from: data), CursorAccessToken(jwt: item.accessToken) != nil else {
            return .failed
        }
        return .found(CursorSignIn(accessToken: item.accessToken, refreshToken: item.refreshToken, email: item.email))
    }

    private struct Stored: Codable {
        let accessToken: String
        let refreshToken: String
        let email: String?
    }
}

/// The `rusage Cursor sign-in` generic password in the login Keychain. rusage creates it, so rusage is on its access
/// list and reads it without a prompt.
struct SystemCursorSignInKeychain: CursorSignInStoring {
    static let service = "rusage Cursor sign-in"
    static let account = "Cursor"

    func read(allowingPrompt: Bool) -> CursorSignInRead {
        var query = Self.itemQuery(allowingPrompt: allowingPrompt)
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true
        var result: AnyObject?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            return (result as? Data).map(CursorSignInRecord.read) ?? .failed
        case errSecItemNotFound:
            return .notFound
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            return .needsPermission
        default:
            return .failed
        }
    }

    func save(_ signIn: CursorSignIn) -> Bool {
        guard let data = CursorSignInRecord.data(for: signIn) else { return false }
        let status = SecItemUpdate(Self.itemQuery(allowingPrompt: true) as CFDictionary, [kSecValueData: data] as CFDictionary)
        guard status == errSecItemNotFound else { return status == errSecSuccess }

        var item = Self.itemQuery(allowingPrompt: true)
        item[kSecValueData] = data
        item[kSecAttrLabel] = Self.service
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func delete() -> Bool {
        let status = SecItemDelete(Self.itemQuery(allowingPrompt: true) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func itemQuery(allowingPrompt: Bool) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        if !allowingPrompt {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext] = context
        }
        return query
    }
}

/// rusage's own Cursor sign-in as a 0600 JSON file. Isolated runs and tests use it in place of the Keychain.
struct FileCursorSignInStore: CursorSignInStoring {
    let fileURL: URL

    func read(allowingPrompt _: Bool) -> CursorSignInRead {
        do {
            return CursorSignInRecord.read(try Data(contentsOf: fileURL))
        } catch CocoaError.fileReadNoSuchFile {
            return .notFound
        } catch {
            return .failed
        }
    }

    /// Writes a 0600 temp file, then renames it over the item, so a reader sees the old item or the new one.
    func save(_ signIn: CursorSignIn) -> Bool {
        guard let data = CursorSignInRecord.data(for: signIn) else { return false }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporaryURL = fileURL.deletingLastPathComponent().appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString)")
        guard fileManager.createFile(atPath: temporaryURL.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return false }
        guard rename(temporaryURL.path, fileURL.path) == 0 else {
            try? fileManager.removeItem(at: temporaryURL)
            return false
        }
        return true
    }

    func delete() -> Bool {
        do {
            try FileManager.default.removeItem(at: fileURL)
            return true
        } catch CocoaError.fileNoSuchFile {
            return true
        } catch {
            return false
        }
    }
}

/// Cursor's sign-in contract as its own CLI and app use it: a PKCE login page that the CLI polls for tokens, and the
/// app's token refresh.
enum CursorAuth {
    static let websiteURL = URL(string: "https://cursor.com")!
    static let apiURL = URL(string: "https://api2.cursor.sh")!
    /// The client the Cursor app refreshes its tokens with.
    static let clientID = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"

    static func loginURL(challenge: String, uuid: String) -> URL {
        var components = URLComponents(url: websiteURL.appendingPathComponent("loginDeepControl"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "challenge", value: challenge),
            URLQueryItem(name: "uuid", value: uuid),
            URLQueryItem(name: "mode", value: "login"),
            URLQueryItem(name: "redirectTarget", value: "cli"),
        ]
        return components.url!
    }

    static func pollURL(uuid: String, verifier: String) -> URL {
        var components = URLComponents(url: apiURL.appendingPathComponent("auth/poll"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "uuid", value: uuid), URLQueryItem(name: "verifier", value: verifier)]
        return components.url!
    }

    static let tokenURL = apiURL.appendingPathComponent("oauth/token")
    static let getMeURL = apiURL.appendingPathComponent("aiserver.v1.DashboardService/GetMe")

    /// A random verifier and its S256 challenge, both base64url without padding.
    static func makePKCE() -> (verifier: String, challenge: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = base64URL(Data(bytes))
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        return (verifier, challenge)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum CursorSignInError: Error, Equatable {
    /// The browser sign-in did not finish in time, or was cancelled.
    case timedOut
    case unreachable
    case notSaved
}

/// What the browser sign-in and the token refresh send and receive.
protocol CursorAuthWebClient: Sendable {
    /// 404 while the browser sign-in is not finished, then 200 with the tokens.
    func poll(_ url: URL) async throws -> (status: Int, data: Data)
    func refresh(refreshToken: String) async throws -> (status: Int, data: Data)
    func getMe(accessToken: String) async throws -> (status: Int, data: Data)
}

struct URLSessionCursorAuthWebClient: CursorAuthWebClient {
    private let session = URLSession(configuration: .ephemeral)

    func poll(_ url: URL) async throws -> (status: Int, data: Data) {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await send(request)
    }

    func refresh(refreshToken: String) async throws -> (status: Int, data: Data) {
        var request = URLRequest(url: CursorAuth.tokenURL, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "client_id": CursorAuth.clientID,
            "refresh_token": refreshToken,
        ])
        return try await send(request)
    }

    func getMe(accessToken: String) async throws -> (status: Int, data: Data) {
        var request = URLRequest(url: CursorAuth.getMeURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> (status: Int, data: Data) {
        let (data, response) = try await session.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}

private let cursorSignInLogger = Logger(subsystem: "com.raphhgg.rusage", category: "CursorSignIn")

/// rusage's own Cursor sign-in: the browser sign-in, its renewal, and sign-out. Reads go through
/// `CursorSignInTokenSource`, which picks this sign-in or Cursor's.
actor CursorOwnSignIn {
    /// Renew this long before the access token expires.
    static let refreshMargin: TimeInterval = 24 * 60 * 60

    private let store: any CursorSignInStoring
    private let web: any CursorAuthWebClient
    private let openURL: @Sendable (URL) -> Void
    private let sleep: @Sendable (Duration) async throws -> Void
    private let now: @Sendable () -> Date

    init(
        store: any CursorSignInStoring,
        web: any CursorAuthWebClient = URLSessionCursorAuthWebClient(),
        openURL: @escaping @Sendable (URL) -> Void,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.web = web
        self.openURL = openURL
        self.sleep = sleep
        self.now = now
    }

    /// Opens Cursor's login page and waits for the browser sign-in, as Cursor's CLI does: up to 150 polls, starting
    /// at a second apart and slowing to ten. The new sign-in replaces an earlier one.
    func signIn() async throws(CursorSignInError) {
        let pkce = CursorAuth.makePKCE()
        let uuid = UUID().uuidString.lowercased()
        openURL(CursorAuth.loginURL(challenge: pkce.challenge, uuid: uuid))

        var failures = 0
        for attempt in 0..<150 {
            if Task.isCancelled { throw .timedOut }
            do {
                let (status, data) = try await web.poll(CursorAuth.pollURL(uuid: uuid, verifier: pkce.verifier))
                if status == 200, let tokens = Self.tokens(fromPoll: data) {
                    var signIn = CursorSignIn(accessToken: tokens.access, refreshToken: tokens.refresh)
                    signIn.email = await email(for: signIn)
                    guard store.save(signIn) else { throw CursorSignInError.notSaved }
                    log("signed in")
                    return
                }
                failures = status == 404 ? 0 : failures + 1
            } catch let error as CursorSignInError {
                throw error
            } catch {
                failures += 1
            }
            if failures >= 3 { throw .unreachable }
            do {
                try await sleep(.milliseconds(Int(min(1_000 * pow(1.2, Double(attempt)), 10_000))))
            } catch {
                throw .timedOut
            }
        }
        throw .timedOut
    }

    /// Renews the access token a day before it expires. A refresh Cursor refuses with `shouldLogout` drops the
    /// sign-in, so the card asks to sign in again.
    func refreshIfNeeded() async {
        guard case let .found(signIn) = store.read(allowingPrompt: false),
              let token = signIn.token,
              token.expiresAt.timeIntervalSince(now()) < Self.refreshMargin
        else { return }
        guard let (status, data) = try? await web.refresh(refreshToken: signIn.refreshToken), status == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            log("refresh failed")
            return
        }
        if object["shouldLogout"] as? Bool == true {
            _ = store.delete()
            log("refresh refused")
            return
        }
        // Cursor's app keeps the new access token as the refresh token too.
        guard let access = object["access_token"] as? String, CursorAccessToken(jwt: access) != nil else { return }
        let refreshed = CursorSignIn(accessToken: access, refreshToken: access, email: signIn.email)
        log(store.save(refreshed) ? "refreshed" : "refresh not saved")
    }

    /// Deletes rusage's own item. Cursor's own sign-in is untouched.
    func signOut() -> Bool {
        store.delete()
    }

    /// The account email, from the same call Cursor's CLI makes after signing in. Nil when it can't be read.
    private func email(for signIn: CursorSignIn) async -> String? {
        guard let (status, data) = try? await web.getMe(accessToken: signIn.accessToken), status == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = object["email"] as? String, !email.isEmpty
        else { return nil }
        return email
    }

    static func tokens(fromPoll data: Data) -> (access: String, refresh: String)? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = object["accessToken"] as? String,
              let refresh = object["refreshToken"] as? String,
              CursorAccessToken(jwt: access) != nil
        else { return nil }
        return (access, refresh)
    }

    private func log(_ outcome: String) {
        cursorSignInLogger.log("Cursor sign-in: \(outcome, privacy: .public)")
    }
}

/// The sign-in reads use: rusage's own while it is on, else Cursor's. Background reads never show a Keychain
/// prompt; "Allow Keychain Access…" allows one.
final class CursorSignInTokenSource: CursorAccessTokenSource {
    private let usesOwnSignIn: @Sendable () -> Bool
    private let store: any CursorSignInStoring
    private let cursorApp: any CursorAccessTokenSource
    private let allowsPrompt = OSAllocatedUnfairLock(initialState: false)

    init(usesOwnSignIn: @escaping @Sendable () -> Bool, store: any CursorSignInStoring, cursorApp: any CursorAccessTokenSource) {
        self.usesOwnSignIn = usesOwnSignIn
        self.store = store
        self.cursorApp = cursorApp
    }

    func allowPromptOnce() {
        allowsPrompt.withLock { $0 = true }
    }

    func lookup() throws -> CursorAccessTokenLookup {
        guard usesOwnSignIn() else { return try cursorApp.lookup() }
        let allowingPrompt = allowsPrompt.withLock { allowed in
            defer { allowed = false }
            return allowed
        }
        switch store.read(allowingPrompt: allowingPrompt) {
        case let .found(signIn):
            guard let token = signIn.token else { return .signedOut }
            return .token(token, email: signIn.email)
        case .notFound:
            return .signedOut
        case .needsPermission:
            throw CursorOwnSignInReadError.keychainAccessNeeded
        case .failed:
            throw CursorOwnSignInReadError.unreadable
        }
    }
}

enum CursorOwnSignInReadError: Error {
    case keychainAccessNeeded
    case unreadable
}
