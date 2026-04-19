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
    func readCurrentAccountStatusParsesRemoteAppServerResponses() async throws {
        let executableURL = try makeRemoteAppServerFixtureExecutable()
        defer { try? FileManager.default.removeItem(at: executableURL) }

        let client = SSHRemoteHostClient(
            snapshotLocator: SnapshotLocatorStub(snapshotURL: URL(fileURLWithPath: "/tmp/unused.json")),
            commandRunner: CommandRunnerSpy(results: []),
            sshExecutableURL: executableURL,
            scpExecutableURL: URL(fileURLWithPath: "/usr/bin/scp")
        )

        let status = try await client.readCurrentAccountStatus(on: RemoteHost(destination: "user@buildbox"))

        #expect(status.email == "remote@example.com")
        #expect(status.planType == "team")
        #expect(status.rateLimits?.primary?.usedPercent == 69)
        #expect(status.rateLimits?.primary?.resetsAt == Date(timeIntervalSince1970: 2_000_000_000))
        #expect(status.rateLimits?.secondary?.usedPercent == 38)
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

private func makeRemoteAppServerFixtureExecutable() throws -> URL {
    let script = """
    #!/bin/sh
    cat >/dev/null
    printf '%s\\n' '{"id":2,"result":{"account":{"email":"remote@example.com","planType":"team"}}}'
    printf '%s\\n' '{"id":3,"result":{"rateLimits":{"limitId":"team","limitName":"Team","planType":"team","primary":{"usedPercent":69,"resetsAt":2000000000,"windowDurationMins":300},"secondary":{"usedPercent":38,"resetsAt":2000500000,"windowDurationMins":10080}}}}'
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
