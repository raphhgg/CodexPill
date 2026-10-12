import Foundation
import Testing

@testable import Refill

/// `security` stood in by a runner that answers each call with a scripted result.
private final class FakeSecurity: SecurityCommandRunning, @unchecked Sendable {
    struct Call: Equatable {
        let arguments: [String]
        let input: String?
        let timeout: Duration
    }

    private let lock = NSLock()
    private var result: SecurityCommandResult
    private var recorded: [Call] = []

    init(_ result: SecurityCommandResult) {
        self.result = result
    }

    var calls: [Call] {
        lock.withLock { recorded }
    }

    func run(_ arguments: [String], input: Data?, timeout: Duration) -> SecurityCommandResult {
        lock.withLock {
            recorded.append(Call(arguments: arguments, input: input.map { String(decoding: $0, as: UTF8.self) }, timeout: timeout))
            return result
        }
    }
}

struct ClaudeCodeSecurityKeychainTests {
    private static let specialPassword = #"{"claudeAiOauth":{"accessToken":"fake-a\"b\\c $d `e` é 💥"}}"#

    private func keychain(_ result: SecurityCommandResult) -> (ClaudeCodeSecurityKeychain, FakeSecurity) {
        let security = FakeSecurity(result)
        return (ClaudeCodeSecurityKeychain(runner: security, account: "person"), security)
    }

    private func describe(_ read: ClaudeKeychainRead) -> String {
        switch read {
        case .notFound: "notFound"
        case .needsPermission: "needsPermission"
        case .failed: "failed"
        case let .found(data): "found " + String(decoding: data, as: UTF8.self)
        }
    }

    @Test
    func aBackgroundReadAsksSecurityForThePasswordByNameWithAShortTimeout() {
        let (keychain, security) = keychain(.exited(status: 0, output: Data(#"{"claudeAiOauth":{}}"#.utf8 + [0x0A])))

        #expect(describe(keychain.read(service: "Claude Code-credentials", allowingPrompt: false)) == #"found {"claudeAiOauth":{}}"#)
        #expect(security.calls == [.init(
            arguments: ["find-generic-password", "-a", "person", "-s", "Claude Code-credentials", "-w"],
            input: nil,
            timeout: .seconds(10)
        )])
    }

    @Test
    func aReadAfterAClickWaitsLongEnoughForTheUserToAnswerAPrompt() {
        let (keychain, security) = keychain(.exited(status: 0, output: Data("{}\n".utf8)))

        _ = keychain.read(service: "Claude Code-credentials", allowingPrompt: true)

        #expect(security.calls.map(\.timeout) == [.seconds(120)])
    }

    @Test
    func aPasswordWithSpecialCharactersComesBackExactlyWhetherSecurityPrintsItAsTextOrHex() {
        let password = Self.specialPassword
        let hex = Data(password.utf8).map { String(format: "%02x", $0) }.joined()

        let (text, _) = keychain(.exited(status: 0, output: Data((password + "\n").utf8)))
        let (hexed, _) = keychain(.exited(status: 0, output: Data((hex + "\n").utf8)))

        #expect(describe(text.read(service: "s", allowingPrompt: false)) == "found " + password)
        #expect(describe(hexed.read(service: "s", allowingPrompt: false)) == "found " + password)
    }

    @Test(arguments: [
        (SecurityCommandResult.exited(status: 44, output: Data()), "notFound"),
        (.exited(status: 36, output: Data()), "needsPermission"),
        (.exited(status: 51, output: Data()), "needsPermission"),
        (.exited(status: 128, output: Data()), "needsPermission"),
        (.timedOut, "needsPermission"),
        (.exited(status: 1, output: Data()), "failed"),
        (.exited(status: 0, output: Data("\n".utf8)), "failed"),
        (.launchFailed, "failed"),
    ])
    func eachSecurityOutcomeReadsAsItsKeychainResult(result: SecurityCommandResult, expected: String) {
        let (keychain, _) = keychain(result)

        #expect(describe(keychain.read(service: "Claude Code-credentials", allowingPrompt: false)) == expected)
    }

    @Test
    func aMissingItemMeansClaudeCodeIsSignedOutAndRefusedAccessAsksForAccess() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SecurityKeychain-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lookup = { (result: SecurityCommandResult) in
            ClaudeCredentialsSource(
                configDirectory: root,
                keychain: SystemClaudeKeychain(keychain: ClaudeCodeSecurityKeychain(runner: FakeSecurity(result), account: "person"))
            ).lookup(allowingPrompt: false)
        }

        guard case .signedOut = lookup(.exited(status: 44, output: Data())) else {
            Issue.record("expected signed out")
            return
        }
        guard case .keychainAccessNeeded = lookup(.exited(status: 51, output: Data())) else {
            Issue.record("expected Keychain access needed")
            return
        }
    }

    @Test
    func aSwitchWritesThroughSecurityStdinAndNeverPutsTheSignInInArguments() throws {
        let (keychain, security) = keychain(.exited(status: 0, output: Data()))
        let password = Self.specialPassword

        #expect(keychain.write(Data(password.utf8), service: "Claude Code-credentials") == true)

        let call = try #require(security.calls.first)
        #expect(call.arguments == ["-i"])
        let line = try #require(call.input)
        #expect(line.hasPrefix(#"add-generic-password -U -a "person" -s "Claude Code-credentials" -X ""#))
        let hex = try #require(line.split(separator: "\"").dropLast().last)
        #expect(ClaudeCodeSecurityKeychain.password(fromOutput: Data(hex.utf8)) == Data(password.utf8))
        #expect(!line.contains("fake-a"))
    }

    @Test
    func aRefusedWriteFailsAndAWriteTooLongForStdinIsLeftToTheCaller() {
        let (refused, _) = keychain(.exited(status: 51, output: Data()))
        let (tooLong, security) = keychain(.exited(status: 0, output: Data()))

        #expect(refused.write(Data("{}".utf8), service: "Claude Code-credentials") == false)
        #expect(tooLong.write(Data(repeating: UInt8(ascii: "x"), count: 2_000), service: "Claude Code-credentials") == nil)
        #expect(security.calls.isEmpty)
    }

    @Test
    func deletingAMissingItemCountsAsDeleted() {
        #expect(keychain(.exited(status: 44, output: Data())).0.delete(service: "s"))
        #expect(keychain(.exited(status: 0, output: Data())).0.delete(service: "s"))
        #expect(!keychain(.exited(status: 51, output: Data())).0.delete(service: "s"))
    }
}

/// The real runner, with a shell script standing in for `security`.
struct SystemSecurityCommandRunnerTests {
    private func runner(script: String) throws -> (SystemSecurityCommandRunner, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SecurityRunner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("security")
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return (SystemSecurityCommandRunner(executable: executable), root)
    }

    @Test
    func stdinReachesSecurityAndItsOutputAndExitStatusComeBack() throws {
        let (runner, root) = try runner(script: "#!/bin/sh\ncat\nexit 7\n")
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(runner.run(["-i"], input: Data("secret line\n".utf8), timeout: .seconds(10))
            == .exited(status: 7, output: Data("secret line\n".utf8)))
    }

    @Test
    func aSecurityThatHangsIsStoppedAtTheTimeout() throws {
        let (runner, root) = try runner(script: "#!/bin/sh\nexec sleep 30\n")
        defer { try? FileManager.default.removeItem(at: root) }
        let start = ContinuousClock.now

        #expect(runner.run(["find-generic-password"], input: nil, timeout: .milliseconds(300)) == .timedOut)
        #expect(ContinuousClock.now - start < .seconds(5))
    }
}
