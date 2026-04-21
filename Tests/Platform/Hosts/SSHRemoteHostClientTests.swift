import CryptoKit
import Foundation
import Testing

@testable import CodexPill

struct SSHRemoteHostClientTests {
    @Test
    func installAccountCreatesDirectoriesThenCopiesSnapshot() async throws {
        let account = makeAccount()
        let snapshotURL = URL(fileURLWithPath: "/tmp/\(account.snapshotFileName)")
        let runner = CommandRunnerSpy(results: [
            .success(.init(terminationStatus: 0, standardOutput: Data(), standardError: Data())),
            .success(.init(terminationStatus: 0, standardOutput: Data(), standardError: Data()))
        ])
        let client = SSHRemoteHostClient(
            snapshotLocator: SnapshotLocatorStub(snapshotURL: snapshotURL),
            commandRunner: runner,
            sshExecutableURL: URL(fileURLWithPath: "/usr/bin/ssh"),
            scpExecutableURL: URL(fileURLWithPath: "/usr/bin/scp")
        )

        try await client.installAccount(account, on: RemoteHost(destination: "user@buildbox"))

        #expect(runner.calls.count == 2)
        #expect(runner.calls[0].arguments == [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-o", "ConnectionAttempts=1",
            "user@buildbox",
            "mkdir -p .codexpill/snapshots .codex"
        ])
        #expect(runner.calls[1].arguments == [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-o", "ConnectionAttempts=1",
            snapshotURL.path,
            "user@buildbox:.codexpill/snapshots/\(account.snapshotFileName)"
        ])
    }

    @Test
    func switchToAccountCopiesInstalledSnapshotIntoRemoteAuthPath() async throws {
        let account = makeAccount()
        let runner = CommandRunnerSpy(results: [
            .success(.init(terminationStatus: 0, standardOutput: Data(), standardError: Data())),
            .success(.init(terminationStatus: 0, standardOutput: Data(), standardError: Data()))
        ])
        let client = SSHRemoteHostClient(
            snapshotLocator: SnapshotLocatorStub(snapshotURL: URL(fileURLWithPath: "/tmp/\(account.snapshotFileName)")),
            commandRunner: runner,
            sshExecutableURL: URL(fileURLWithPath: "/usr/bin/ssh"),
            scpExecutableURL: URL(fileURLWithPath: "/usr/bin/scp")
        )

        try await client.switchToAccount(account, on: RemoteHost(destination: "user@buildbox"))

        #expect(runner.calls.count == 2)
        #expect(runner.calls[1].arguments == [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-o", "ConnectionAttempts=1",
            "user@buildbox",
            "cp '.codexpill/snapshots/\(account.snapshotFileName)' '.codex/auth.json'"
        ])
    }

    @Test
    func installationStateTreatsExitCodeOneAsMissing() async throws {
        let account = makeAccount()
        let runner = CommandRunnerSpy(results: [
            .success(.init(terminationStatus: 1, standardOutput: Data(), standardError: Data()))
        ])
        let client = SSHRemoteHostClient(
            snapshotLocator: SnapshotLocatorStub(snapshotURL: URL(fileURLWithPath: "/tmp/\(account.snapshotFileName)")),
            commandRunner: runner,
            sshExecutableURL: URL(fileURLWithPath: "/usr/bin/ssh"),
            scpExecutableURL: URL(fileURLWithPath: "/usr/bin/scp")
        )

        let state = try await client.installationState(for: account, on: RemoteHost(destination: "user@buildbox"))

        #expect(state == .missing)
    }

    @Test
    func testConnectionRequiresCodexAndChecksRemoteDirectoryAccess() async throws {
        let runner = CommandRunnerSpy(results: [
            .success(.init(terminationStatus: 0, standardOutput: Data(), standardError: Data()))
        ])
        let client = SSHRemoteHostClient(
            snapshotLocator: SnapshotLocatorStub(snapshotURL: URL(fileURLWithPath: "/tmp/unused.json")),
            commandRunner: runner,
            sshExecutableURL: URL(fileURLWithPath: "/usr/bin/ssh"),
            scpExecutableURL: URL(fileURLWithPath: "/usr/bin/scp")
        )

        try await client.testConnection(to: RemoteHost(destination: "user@buildbox"))

        #expect(runner.calls.count == 1)
        #expect(runner.calls[0].arguments == [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-o", "ConnectionAttempts=1",
            "user@buildbox",
            "command -v codex >/dev/null 2>&1 && codex app-server --help >/dev/null 2>&1 && mkdir -p .codexpill/snapshots .codex"
        ])
    }

    @Test
    func testConnectionSurfacesRemoteCommandFailures() async {
        let runner = CommandRunnerSpy(results: [
            .success(.init(
                terminationStatus: 127,
                standardOutput: Data(),
                standardError: Data("codex: command not found".utf8)
            ))
        ])
        let client = SSHRemoteHostClient(
            snapshotLocator: SnapshotLocatorStub(snapshotURL: URL(fileURLWithPath: "/tmp/unused.json")),
            commandRunner: runner,
            sshExecutableURL: URL(fileURLWithPath: "/usr/bin/ssh"),
            scpExecutableURL: URL(fileURLWithPath: "/usr/bin/scp")
        )

        await #expect(throws: RemoteHostClientError.commandFailed("codex: command not found")) {
            try await client.testConnection(to: RemoteHost(destination: "user@buildbox"))
        }
    }

    @Test
    func installAccountSurfacesScpFailures() async {
        let account = makeAccount()
        let snapshotURL = URL(fileURLWithPath: "/tmp/\(account.snapshotFileName)")
        let runner = CommandRunnerSpy(results: [
            .success(.init(terminationStatus: 0, standardOutput: Data(), standardError: Data())),
            .success(.init(
                terminationStatus: 1,
                standardOutput: Data(),
                standardError: Data("scp: Permission denied".utf8)
            ))
        ])
        let client = SSHRemoteHostClient(
            snapshotLocator: SnapshotLocatorStub(snapshotURL: snapshotURL),
            commandRunner: runner,
            sshExecutableURL: URL(fileURLWithPath: "/usr/bin/ssh"),
            scpExecutableURL: URL(fileURLWithPath: "/usr/bin/scp")
        )

        await #expect(throws: RemoteHostClientError.commandFailed("scp: Permission denied")) {
            try await client.installAccount(account, on: RemoteHost(destination: "user@buildbox"))
        }
    }

    @Test
    func switchToAccountSurfacesRemoteCopyFailures() async {
        let account = makeAccount()
        let runner = CommandRunnerSpy(results: [
            .success(.init(terminationStatus: 0, standardOutput: Data(), standardError: Data())),
            .success(.init(
                terminationStatus: 1,
                standardOutput: Data(),
                standardError: Data("cp: .codex/auth.json: Permission denied".utf8)
            ))
        ])
        let client = SSHRemoteHostClient(
            snapshotLocator: SnapshotLocatorStub(snapshotURL: URL(fileURLWithPath: "/tmp/\(account.snapshotFileName)")),
            commandRunner: runner,
            sshExecutableURL: URL(fileURLWithPath: "/usr/bin/ssh"),
            scpExecutableURL: URL(fileURLWithPath: "/usr/bin/scp")
        )

        await #expect(throws: RemoteHostClientError.commandFailed("cp: .codex/auth.json: Permission denied")) {
            try await client.switchToAccount(account, on: RemoteHost(destination: "user@buildbox"))
        }
    }

    @Test
    func readCurrentAccountStatusParsesRemoteAppServerResponses() async throws {
        let executableURL = try makeRemoteAppServerFixtureExecutable()
        defer { try? FileManager.default.removeItem(at: executableURL) }
        let authData = makeAuthData(
            email: "remote@example.com",
            planType: "team",
            stableAccountID: "acct-remote",
            subject: "auth0|remote",
            chatGPTUserID: "user-remote",
            workspaceAccountID: "org-remote",
            workspaceLabel: "Remote Team"
        )
        let runner = CommandRunnerSpy(results: [
            .success(.init(terminationStatus: 0, standardOutput: authData, standardError: Data()))
        ])

        let client = SSHRemoteHostClient(
            snapshotLocator: SnapshotLocatorStub(snapshotURL: URL(fileURLWithPath: "/tmp/unused.json")),
            commandRunner: runner,
            sshExecutableURL: executableURL,
            scpExecutableURL: URL(fileURLWithPath: "/usr/bin/scp")
        )

        let status = try await client.readCurrentAccountStatus(on: RemoteHost(destination: "user@buildbox"))

        #expect(status.email == "remote@example.com")
        #expect(status.planType == "team")
        #expect(status.rateLimits?.primary?.usedPercent == 69)
        #expect(status.rateLimits?.primary?.resetsAt == Date(timeIntervalSince1970: 2_000_000_000))
        #expect(status.rateLimits?.secondary?.usedPercent == 38)
        #expect(status.stableAccountID == "acct-remote")
        #expect(status.authPrincipalIdentity == CodexAuthPrincipalIdentity(subject: "auth0|remote", chatGPTUserID: "user-remote"))
        #expect(status.workspaceIdentity == CodexWorkspaceIdentity(workspaceAccountID: "org-remote", workspaceLabel: "Remote Team"))
        #expect(status.snapshotFingerprint != nil)
        #expect(runner.calls == [
            .init(
                executableURL: executableURL,
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "-o", "ConnectionAttempts=1",
                    "user@buildbox",
                    "if [ ! -f '.codex/auth.json' ]; then exit 17; fi\ncat '.codex/auth.json'"
                ]
            )
        ])
    }

    @Test
    func readCurrentAccountStatusReturnsPartialAccountDataWhenRateLimitsAreMissing() async throws {
        let executableURL = try makeRemoteAppServerFixtureExecutable(
            lines: [
                #"{"id":2,"result":{"account":{"email":"remote@example.com","planType":"team"}}}"#,
                #"{"id":3,"result":{}}"#
            ]
        )
        defer { try? FileManager.default.removeItem(at: executableURL) }
        let runner = CommandRunnerSpy(results: [
            .success(.init(terminationStatus: 17, standardOutput: Data(), standardError: Data()))
        ])

        let client = SSHRemoteHostClient(
            snapshotLocator: SnapshotLocatorStub(snapshotURL: URL(fileURLWithPath: "/tmp/unused.json")),
            commandRunner: runner,
            sshExecutableURL: executableURL,
            scpExecutableURL: URL(fileURLWithPath: "/usr/bin/scp")
        )

        let status = try await client.readCurrentAccountStatus(on: RemoteHost(destination: "user@buildbox"))

        #expect(status.email == "remote@example.com")
        #expect(status.planType == "team")
        #expect(status.rateLimits == nil)
    }

    @Test
    func readCurrentAccountStatusRetriesWhenFirstRemoteResponseHasOnlyWeeklyRateLimits() async throws {
        let weeklyOnly = [
            #"{"id":2,"result":{"account":{"email":"remote@example.com","planType":"team"}}}"#,
            #"{"id":3,"result":{"rateLimits":{"planType":"team","secondary":{"usedPercent":16,"resetsAt":2000500000,"windowDurationMins":10080}}}}"#
        ]
        let full = [
            #"{"id":2,"result":{"account":{"email":"remote@example.com","planType":"team"}}}"#,
            #"{"id":3,"result":{"rateLimits":{"limitId":"team","limitName":"Team","planType":"team","primary":{"usedPercent":69,"resetsAt":2000000000,"windowDurationMins":300},"secondary":{"usedPercent":38,"resetsAt":2000500000,"windowDurationMins":10080}}}}"#
        ]
        let executableURL = try makeRemoteAppServerFixtureExecutable(firstLines: weeklyOnly, refreshedLines: full)
        defer { try? FileManager.default.removeItem(at: executableURL) }
        let runner = CommandRunnerSpy(results: [
            .success(.init(terminationStatus: 17, standardOutput: Data(), standardError: Data()))
        ])

        let client = SSHRemoteHostClient(
            snapshotLocator: SnapshotLocatorStub(snapshotURL: URL(fileURLWithPath: "/tmp/unused.json")),
            commandRunner: runner,
            sshExecutableURL: executableURL,
            scpExecutableURL: URL(fileURLWithPath: "/usr/bin/scp")
        )

        let status = try await client.readCurrentAccountStatus(on: RemoteHost(destination: "user@buildbox"))

        #expect(status.rateLimits?.primary?.usedPercent == 69)
        #expect(status.rateLimits?.secondary?.usedPercent == 38)
    }

    @Test
    func readCurrentAccountStatusPrefersRemoteAuthFingerprintWhenAppServerIdentityIsAmbiguous() async throws {
        let executableURL = try makeRemoteAppServerFixtureExecutable(
            lines: [
                #"{"id":2,"result":{"account":{"email":"shared@example.com","planType":"team"}}}"#,
                #"{"id":3,"result":{}}"#
            ]
        )
        defer { try? FileManager.default.removeItem(at: executableURL) }
        let authData = makeAuthData(
            email: "shared@example.com",
            planType: "team",
            stableAccountID: "acct-business-2",
            subject: "auth0|business-2",
            chatGPTUserID: "user-business-2",
            workspaceAccountID: "org-business-2",
            workspaceLabel: "Business 2"
        )
        let runner = CommandRunnerSpy(results: [
            .success(.init(terminationStatus: 0, standardOutput: authData, standardError: Data()))
        ])

        let client = SSHRemoteHostClient(
            snapshotLocator: SnapshotLocatorStub(snapshotURL: URL(fileURLWithPath: "/tmp/unused.json")),
            commandRunner: runner,
            sshExecutableURL: executableURL,
            scpExecutableURL: URL(fileURLWithPath: "/usr/bin/scp")
        )

        let status = try await client.readCurrentAccountStatus(on: RemoteHost(destination: "user@buildbox"))

        #expect(status.email == "shared@example.com")
        #expect(status.stableAccountID == "acct-business-2")
        #expect(status.authPrincipalIdentity == CodexAuthPrincipalIdentity(subject: "auth0|business-2", chatGPTUserID: "user-business-2"))
        #expect(status.workspaceIdentity == CodexWorkspaceIdentity(workspaceAccountID: "org-business-2", workspaceLabel: "Business 2"))
        #expect(status.snapshotFingerprint == makeFingerprint(for: authData))
    }

    @Test
    func readCurrentAccountStatusSurfacesRemoteAuthReadFailures() async throws {
        let executableURL = try makeRemoteAppServerFixtureExecutable(
            lines: [
                #"{"id":2,"result":{"account":{"email":"shared@example.com","planType":"team"}}}"#,
                #"{"id":3,"result":{}}"#
            ]
        )
        defer { try? FileManager.default.removeItem(at: executableURL) }
        let runner = CommandRunnerSpy(results: [
            .success(.init(
                terminationStatus: 1,
                standardOutput: Data(),
                standardError: Data("cat: .codex/auth.json: Permission denied".utf8)
            ))
        ])

        let client = SSHRemoteHostClient(
            snapshotLocator: SnapshotLocatorStub(snapshotURL: URL(fileURLWithPath: "/tmp/unused.json")),
            commandRunner: runner,
            sshExecutableURL: executableURL,
            scpExecutableURL: URL(fileURLWithPath: "/usr/bin/scp")
        )

        await #expect(throws: RemoteHostClientError.authReadFailed("cat: .codex/auth.json: Permission denied")) {
            _ = try await client.readCurrentAccountStatus(on: RemoteHost(destination: "user@buildbox"))
        }
    }

    private func makeAccount() -> CodexAccount {
        CodexAccount(
            id: UUID(),
            name: "Research",
            snapshotFileName: "research.json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "research@example.com",
            planType: "pro",
            rateLimits: nil,
            identity: CodexAccountIdentity(
                snapshotFingerprint: UUID().uuidString,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "research@example.com")
            )
        )
    }
}

private func makeAuthData(
    email: String,
    planType: String,
    stableAccountID: String,
    subject: String,
    chatGPTUserID: String,
    workspaceAccountID: String,
    workspaceLabel: String
) -> Data {
    let header = base64URL(#"{"alg":"none","typ":"JWT"}"#)
    let payload = base64URL("""
    {
      "sub":"\(subject)",
      "email":"\(email)",
      "https://api.openai.com/auth":{
        "chatgpt_user_id":"\(chatGPTUserID)",
        "chatgpt_plan_type":"\(planType)",
        "organizations":[
          {
            "id":"\(workspaceAccountID)",
            "title":"\(workspaceLabel)",
            "is_default":true
          }
        ]
      }
    }
    """)
    let token = "\(header).\(payload).signature"
    let object = """
    {
      "tokens": {
        "account_id": "\(stableAccountID)",
        "id_token": "\(token)"
      }
    }
    """
    return Data(object.utf8)
}

private func base64URL(_ string: String) -> String {
    Data(string.utf8)
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func makeFingerprint(for data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

private func makeRemoteAppServerFixtureExecutable(
    lines: [String]? = nil,
    firstLines: [String]? = nil,
    refreshedLines: [String]? = nil
) throws -> URL {
    let defaultLines = lines ?? [
        #"{"id":2,"result":{"account":{"email":"remote@example.com","planType":"team"}}}"#,
        #"{"id":3,"result":{"rateLimits":{"limitId":"team","limitName":"Team","planType":"team","primary":{"usedPercent":69,"resetsAt":2000000000,"windowDurationMins":300},"secondary":{"usedPercent":38,"resetsAt":2000500000,"windowDurationMins":10080}}}}"#
    ]
    let initialLines = firstLines ?? defaultLines
    let refreshLines = refreshedLines ?? defaultLines
    let initialPrintedLines = initialLines.map { "printf '%s\\n' '\($0)'" }.joined(separator: "\n")
    let refreshPrintedLines = refreshLines.map { "printf '%s\\n' '\($0)'" }.joined(separator: "\n")
    let stateFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    let script = """
    #!/bin/sh
    cat >/dev/null
    if [ ! -f "\(stateFile)" ]; then
      touch "\(stateFile)"
    \(initialPrintedLines)
    else
    \(refreshPrintedLines)
    fi
    """

    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data(script.utf8).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

private struct SnapshotLocatorStub: AccountSnapshotLocating {
    let snapshotURL: URL

    func snapshotURL(for account: CodexAccount) -> URL {
        snapshotURL
    }
}

private final class CommandRunnerSpy: CommandRunning {
    struct Call: Equatable {
        let executableURL: URL
        let arguments: [String]
    }

    let results: [Result<CommandResult, Error>]
    private(set) var calls: [Call] = []
    private var index = 0

    init(results: [Result<CommandResult, Error>]) {
        self.results = results
    }

    func run(executableURL: URL, arguments: [String]) async throws -> CommandResult {
        calls.append(.init(executableURL: executableURL, arguments: arguments))
        defer { index += 1 }
        return try results[index].get()
    }
}
