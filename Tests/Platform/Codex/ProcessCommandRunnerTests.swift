import Foundation
import Testing

@testable import CodexPill

struct ProcessCommandRunnerTests {
    private let shell = URL(fileURLWithPath: "/bin/sh")

    @Test
    func capturesOutputLargerThanThePipeBufferOnBothStreams() async throws {
        let result = try await ProcessCommandRunner().run(
            executableURL: shell,
            arguments: ["-c", "head -c 1000000 /dev/zero & head -c 1000000 /dev/zero >&2 & wait; exit 3"]
        )

        #expect(result.terminationStatus == 3)
        #expect(result.standardOutput == Data(count: 1_000_000))
        #expect(result.standardError == Data(count: 1_000_000))
    }

    @Test
    func killsACommandThatIgnoresTerminationAfterTheTimeout() async throws {
        let fixture = try HangingProcessFixture()
        defer { fixture.remove() }
        let runner = ProcessCommandRunner(timeout: .milliseconds(100), terminationGracePeriod: .milliseconds(50))

        await #expect(throws: CommandRunnerError.timedOut) {
            try await runner.run(executableURL: shell, arguments: fixture.arguments)
        }

        #expect(try !isRunning(fixture.processIdentifier()))
    }

    @Test
    func cancellationStopsTheCommand() async throws {
        let fixture = try HangingProcessFixture()
        defer { fixture.remove() }
        let runner = ProcessCommandRunner(timeout: .seconds(30), terminationGracePeriod: .milliseconds(50))
        let task = Task {
            try await runner.run(executableURL: shell, arguments: fixture.arguments)
        }

        try await fixture.waitUntilStarted()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(try !isRunning(fixture.processIdentifier()))
    }

    private func isRunning(_ processIdentifier: Int32) -> Bool {
        kill(processIdentifier, 0) == 0
    }
}

private struct HangingProcessFixture {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ProcessCommandRunnerTests-\(UUID().uuidString)", isDirectory: true)

    init() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private var processIdentifierURL: URL {
        directoryURL.appendingPathComponent("pid")
    }

    var arguments: [String] {
        ["-c", "echo $$ > \"$1\"; trap '' TERM; while :; do :; done", "hanging-process", processIdentifierURL.path]
    }

    func waitUntilStarted() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while (try? processIdentifier()) == nil {
            guard ContinuousClock.now < deadline else { throw FixtureError.didNotStart }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func processIdentifier() throws -> Int32 {
        let contents = try String(contentsOf: processIdentifierURL, encoding: .utf8)
        guard let processIdentifier = Int32(contents.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw FixtureError.didNotStart
        }
        return processIdentifier
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private enum FixtureError: Error {
    case didNotStart
}
