import Foundation
import Testing

@testable import rusage

struct ClaudeSignInStoreTests {
    private let expiry = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func theFileStoreKeepsBothTokensAndTheRefreshMarkerInOnePrivateFile() throws {
        let files = ClaudeOwnSignInFiles()
        defer { files.remove() }
        let store = files.store
        let signIn = ClaudeSignIn.fake(access: "a1", refresh: "r1", expiresAt: expiry, email: "sam@example.com", planName: "max_20x")

        #expect(store.read(allowingPrompt: false) == .notFound)
        #expect(store.save(signIn, refreshPending: true, allowingPrompt: false))
        #expect(store.read(allowingPrompt: false) == .found(signIn, refreshPending: true))

        #expect(store.save(signIn, refreshPending: false, allowingPrompt: false))
        #expect(store.read(allowingPrompt: false) == .found(signIn, refreshPending: false))
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.root.path) == ["claude-sign-in.json"])

        #expect(store.delete())
        #expect(store.read(allowingPrompt: false) == .notFound)
        #expect(store.delete())
    }

    @Test
    func anItemThatIsNotASignInReadsAsFailed() throws {
        let files = ClaudeOwnSignInFiles()
        defer { files.remove() }
        try FileManager.default.createDirectory(at: files.root, withIntermediateDirectories: true)
        try Data(#"{"accessToken":"","refreshToken":"r1","expiresAt":0,"refreshPending":false}"#.utf8).write(to: files.store.fileURL)

        #expect(files.store.read(allowingPrompt: false) == .failed)
    }
}

struct ClaudeRefreshLockTests {
    @Test
    func twoHoldersInOneProcessTakeTurns() async throws {
        let files = ClaudeOwnSignInFiles()
        defer { files.remove() }
        let gate = TestGate()
        let order = ClaudeEventLog()

        let first = Task {
            await files.lock.withLock {
                order.append("first in")
                await gate.pass()
                order.append("first out")
            }
        }
        await gate.waitUntilReached()
        let second = Task {
            await files.lock.withLock { order.append("second in") }
        }
        try await Task.sleep(for: .milliseconds(200))
        #expect(order.events == ["first in"])

        await gate.open()
        #expect(await first.value != nil)
        #expect(await second.value != nil)
        #expect(order.events == ["first in", "first out", "second in"])
    }

    @Test
    func aLockHeldPastTheTimeoutReadsAsBusy() async {
        let files = ClaudeOwnSignInFiles()
        defer { files.remove() }
        var impatient = files.lock
        impatient.timeout = .milliseconds(150)
        let gate = TestGate()

        let holder = Task { await files.lock.withLock { await gate.pass() } }
        await gate.waitUntilReached()

        #expect(await impatient.withLock { "ran" } == nil)

        await gate.open()
        _ = await holder.value
        #expect(await impatient.withLock { "ran" } == "ran")
    }
}
