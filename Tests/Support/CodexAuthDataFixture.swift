import Foundation

@testable import RUsage

/// A synthetic `auth.json` whose ID token names `email`, `accountID` and `userID`. It holds no real token.
func makeCodexAuthData(email: String, accountID: String = "acct-1", userID: String = "user-1", refreshToken: String = "r1") -> Data {
    func part(_ object: [String: Any]) -> String {
        (try! JSONSerialization.data(withJSONObject: object)).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    let idToken = part(["alg": "none"]) + "." + part([
        "email": email,
        "https://api.openai.com/auth": ["chatgpt_account_id": accountID, "chatgpt_user_id": userID],
    ]) + ".signature"
    return try! JSONSerialization.data(withJSONObject: [
        "tokens": ["account_id": accountID, "id_token": idToken, "refresh_token": refreshToken],
    ])
}

/// An `auth.json` in a fresh temporary folder.
func makeCodexAuthFile(_ authData: Data? = nil) -> CodexAuthFile {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("rusageTests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = CodexAuthFile(url: folder.appendingPathComponent("auth.json"))
    if let authData {
        try! file.write(authData)
    }
    return file
}

/// A browser sign-in that returns `authData` at once.
final class IsolatedCodexLoginProbe: IsolatedCodexLoginClient, @unchecked Sendable {
    var authData: Data
    /// Runs while the sign-in waits, as when the user signs in to Codex elsewhere meanwhile.
    var whileWaiting: () -> Void = {}

    init(authData: Data) {
        self.authData = authData
    }

    func startLogin() async throws -> IsolatedCodexLoginSession {
        Session(probe: self)
    }

    private final class Session: IsolatedCodexLoginSession, @unchecked Sendable {
        let probe: IsolatedCodexLoginProbe
        let prompt = IsolatedCodexLoginPrompt(url: URL(string: "https://example.com/device")!, userCode: "ABCD-1234")
        let codexHome = FileManager.default.temporaryDirectory

        init(probe: IsolatedCodexLoginProbe) {
            self.probe = probe
        }

        func waitForAuthData() async throws -> Data {
            probe.whileWaiting()
            return probe.authData
        }

        func verifyLoginStatus() async -> Bool { true }
        func cancel() {}
        func cleanup() {}
    }
}
