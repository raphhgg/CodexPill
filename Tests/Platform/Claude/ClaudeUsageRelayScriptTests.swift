import Foundation
import Testing

@testable import CodexPill

struct ClaudeUsageRelayScriptTests {
    private static let fullPayload = """
    {"hook_event_name":"Status","session_id":"secret-session-7f3a","transcript_path":"/Users/fixture/.claude/projects/secret-project/transcript.jsonl","cwd":"/Users/fixture/secret-repo","model":{"id":"claude-opus-4-1","display_name":"SecretModelName"},"workspace":{"current_dir":"/Users/fixture/secret-repo","project_dir":"/Users/fixture/secret-repo"},"version":"2.0.14","output_style":{"name":"default"},"cost":{"total_cost_usd":0.0123,"total_duration_ms":45000,"total_api_duration_ms":2300,"total_lines_added":156,"total_lines_removed":23},"prompt_cache":{"cache_read_input_tokens":98765,"cache_creation_input_tokens":4321},"exceeds_200k_tokens":false,"rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":1760050000},"seven_day":{"used_percentage":18,"resets_at":1760500000},"spend_limit":{"used_usd":12.5,"limit_usd":100,"resets_at":1761000000}}}

    """

    @Test
    func fullPayloadWritesOnlyTheCodexPillUsageShape() throws {
        let home = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let before = Int(Date().timeIntervalSince1970)

        _ = try runRelay(home: home, stdin: Data(Self.fullPayload.utf8))

        let after = Int(Date().timeIntervalSince1970)
        let raw = try Data(contentsOf: usageFile(home: home))
        let root = try #require(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
        #expect(Set(root.keys) == ["schema", "captured_at", "rate_limits"])
        #expect(root["schema"] as? Int == 1)
        let capturedAt = try #require(root["captured_at"] as? Int)
        #expect((before...after).contains(capturedAt))

        let rateLimits = try #require(root["rate_limits"] as? [String: Any])
        #expect(Set(rateLimits.keys) == ["five_hour", "seven_day"])
        let fiveHour = try #require(rateLimits["five_hour"] as? [String: Any])
        let sevenDay = try #require(rateLimits["seven_day"] as? [String: Any])
        #expect(Set(fiveHour.keys) == ["used_percentage", "resets_at"])
        #expect(Set(sevenDay.keys) == ["used_percentage", "resets_at"])
        #expect(fiveHour["used_percentage"] as? Double == 42.5)
        #expect(fiveHour["resets_at"] as? Int == 1760050000)
        #expect(sevenDay["used_percentage"] as? Double == 18)
        #expect(sevenDay["resets_at"] as? Int == 1760500000)

        let text = String(decoding: raw, as: UTF8.self)
        for secret in ["secret-session-7f3a", "secret-project", "secret-repo", "SecretModelName", "spend_limit", "98765", "0.0123"] {
            #expect(!text.contains(secret))
        }
    }

    @Test
    func previousCommandReceivesIdenticalStdinAndItsOutputAndStatusPassThrough() throws {
        let home = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let copy = home.appendingPathComponent("stdin-copy")
        let script = try makeCopyingScript(in: home, named: "prev.sh")
        let input = Data(Self.fullPayload.utf8)

        let result = try runRelay(home: home, stdin: input, previousCommand: "/bin/sh '\(script.path)' '\(copy.path)'")

        #expect(result.stdout == "PREV OUTPUT\n")
        #expect(result.status == 3)
        #expect(try Data(contentsOf: copy) == input)
    }

    @Test
    func previousCommandWithSingleQuoteAndSpacesRuns() throws {
        let home = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = home.appendingPathComponent("it's my dir", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let copy = directory.appendingPathComponent("stdin copy")
        let script = try makeCopyingScript(in: directory, named: "prev script.sh")

        let result = try runRelay(
            home: home,
            stdin: Data(Self.fullPayload.utf8),
            previousCommand: "/bin/sh \"\(script.path)\" \"\(copy.path)\""
        )

        #expect(result.stdout == "PREV OUTPUT\n")
        #expect(result.status == 3)
        #expect(try Data(contentsOf: copy) == Data(Self.fullPayload.utf8))
    }

    @Test
    func noPreviousCommandPrintsNothingAndSucceeds() throws {
        let home = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let result = try runRelay(home: home, stdin: Data(Self.fullPayload.utf8))

        #expect(result.stdout == "")
        #expect(result.status == 0)
    }

    @Test
    func payloadWithoutRateLimitsCreatesFileWithEmptyRateLimits() throws {
        let home = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        _ = try runRelay(home: home, stdin: Data(#"{"session_id":"abc","model":{"id":"claude-sonnet-4-5"}}"#.utf8))

        let root = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: usageFile(home: home))) as? [String: Any]
        )
        #expect(Set(root.keys) == ["schema", "captured_at", "rate_limits"])
        #expect(root["schema"] as? Int == 1)
        let rateLimits = try #require(root["rate_limits"] as? [String: Any])
        #expect(rateLimits.isEmpty)
    }

    @Test
    func payloadWithoutRateLimitsLeavesExistingFileByteIdentical() throws {
        let home = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let existing = Data(#"{"schema":1,"captured_at":1760000000,"rate_limits":{"five_hour":{"used_percentage":7,"resets_at":1760010000}}}"#.utf8 + [0x0A])
        try FileManager.default.createDirectory(
            at: usageFile(home: home).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try existing.write(to: usageFile(home: home))

        _ = try runRelay(home: home, stdin: Data(#"{"session_id":"abc"}"#.utf8))

        #expect(try Data(contentsOf: usageFile(home: home)) == existing)
    }

    @Test
    func unwritableAppSupportKeepsPassthroughOutputAndStatus() throws {
        let home = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let codexPill = usageFile(home: home).deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: codexPill.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not a directory".utf8).write(to: codexPill)

        let result = try runRelay(
            home: home,
            stdin: Data(Self.fullPayload.utf8),
            previousCommand: "printf 'PREV OUTPUT\\n'; exit 3"
        )

        #expect(result.stdout == "PREV OUTPUT\n")
        #expect(result.status == 3)
    }

    @Test
    func usageFileIsPrivateAndNoTemporaryFilesRemain() throws {
        let home = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        _ = try runRelay(home: home, stdin: Data(Self.fullPayload.utf8))
        _ = try runRelay(home: home, stdin: Data(Self.fullPayload.utf8))

        let directory = usageFile(home: home).deletingLastPathComponent()
        #expect(try posixPermissions(at: usageFile(home: home)) == 0o600)
        #expect(try posixPermissions(at: directory) == 0o700)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["claude-usage.json"])
    }

    @Test
    func garbageStdinStillReachesPreviousCommand() throws {
        let home = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let result = try runRelay(home: home, stdin: Data("not json {{{\n".utf8), previousCommand: "cat; exit 3")

        #expect(result.stdout == "not json {{{\n")
        #expect(result.status == 3)
    }

    @Test
    func plannedStatusLineCommandRunsRelayThenPreviousCommandInAShell() throws {
        let home = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let command = ClaudeStatusLineInstallPlanner.relayCommand(
            relayPath: relayScriptURL().path,
            previousCommand: #"printf '%s "quoted"\n' "it's"; exit 4"#
        )

        let result = try run(arguments: ["-c", command], home: home, stdin: Data(Self.fullPayload.utf8))

        #expect(result.stdout == "it's \"quoted\"\n")
        #expect(result.status == 4)
        let usage = try JSONSerialization.jsonObject(with: Data(contentsOf: usageFile(home: home))) as? [String: Any]
        #expect((usage?["rate_limits"] as? [String: Any])?.keys.sorted() == ["five_hour", "seven_day"])
    }

    private struct RelayResult {
        let stdout: String
        let status: Int32
    }

    private func runRelay(home: URL, stdin: Data, previousCommand: String? = nil) throws -> RelayResult {
        try run(arguments: [relayScriptURL().path] + (previousCommand.map { [$0] } ?? []), home: home, stdin: stdin)
    }

    private func run(arguments: [String], home: URL, stdin: Data) throws -> RelayResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = arguments
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        try process.run()
        input.fileHandleForWriting.write(stdin)
        try input.fileHandleForWriting.close()
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return RelayResult(stdout: String(decoding: stdout, as: UTF8.self), status: process.terminationStatus)
    }

    private func makeCopyingScript(in directory: URL, named name: String) throws -> URL {
        let script = directory.appendingPathComponent(name)
        try Data("cat > \"$1\"\nprintf 'PREV OUTPUT\\n'\nexit 3\n".utf8).write(to: script)
        return script
    }

    private func relayScriptURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/codexpill-claude-usage-relay.sh")
    }

    private func usageFile(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/CodexPill/claude-usage.json")
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeUsageRelayScriptTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? Int)
    }
}
