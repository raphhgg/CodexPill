import Foundation

enum MenuBarRuntimeWorkflowScenario {
    static let proofLayer = "workflow-event-log"

    private static let manifestBackedScenarioIDs: Set<String> = [
        "add-account-isolated-success",
        "add-account-failure-cleanup",
        "switch-account-local-confirmed",
        "switch-account-remote-install-verify",
        "remote-host-install-switch-current-account",
        "remote-host-verification-failure",
        "remove-account-active-targets-sign-out",
        "remove-account-signout-failure-keeps-control",
        "notifications-account-available-policy",
        "notifications-current-runs-out-action",
        "notifications-dedupe-after-delivery",
        "launch-at-login-enable-confirmation",
        "launch-at-login-blocked-opens-settings",
        "status-bar-hover-label",
        "status-bar-shortcut-reveal",
        "status-bar-usage-bars-preferences"
    ]

    static func normalize(_ scenario: String?) -> String? {
        guard let scenario = scenario?.trimmingCharacters(in: .whitespacesAndNewlines),
              !scenario.isEmpty,
              manifestBackedScenarioIDs.contains(scenario) else {
            return nil
        }
        return scenario
    }
}

struct MenuBarValidationEvent: Codable, Equatable {
    let ts: String
    let scenario: String
    let proofLayer: String
    let invariantIds: [String]
    let event: String
    let step: String
    let payload: [String: String]

    init(
        timestamp: Date = .now,
        scenario: String,
        proofLayer: String,
        invariantIds: [String],
        event: String,
        step: String,
        payload: [String: String] = [:]
    ) {
        self.ts = Self.makeTimestampFormatter().string(from: timestamp)
        self.scenario = scenario
        self.proofLayer = proofLayer
        self.invariantIds = invariantIds
        self.event = event
        self.step = step
        self.payload = payload
    }

    private static func makeTimestampFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

func sanitizedValidationPayload(_ payload: [String: String]) -> [String: String] {
    payload.mapValues(sanitizedValidationPayloadValue)
}

func sanitizedValidationPayloadValue(_ value: String) -> String {
    var sanitized = value
    let replacements: [(pattern: String, template: String)] = [
        (#"(?i)(bearer\s+)[A-Za-z0-9._~+/=-]+"#, "$1<redacted>"),
        (#"(?i)((?:access|refresh|id)_?token["'=:\s]+)[^&\s"']+"#, "$1<redacted>"),
        (#"(?i)(api[_-]?key["'=:\s]+)[^&\s"']+"#, "$1<redacted>"),
        (#"/Users/[^/\s]+"#, "/Users/<redacted>"),
        (#"file://(?:/Users/[^/\s]+)"#, "file:///Users/<redacted>")
    ]

    for replacement in replacements {
        sanitized = sanitized.replacingOccurrences(
            of: replacement.pattern,
            with: replacement.template,
            options: .regularExpression
        )
    }

    return sanitized
}

protocol MenuBarValidationSink: Sendable {
    func record(_ snapshot: MenuBarValidationSnapshot) throws
    func record(_ event: MenuBarValidationEvent) throws
}

struct FileMenuBarValidationSink: MenuBarValidationSink {
    let outputURL: URL
    let eventsOutputURL: URL

    func record(_ snapshot: MenuBarValidationSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: outputURL, options: .atomic)
    }

    func record(_ event: MenuBarValidationEvent) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(event) + Data("\n".utf8)

        try FileManager.default.createDirectory(
            at: eventsOutputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if !FileManager.default.fileExists(atPath: eventsOutputURL.path) {
            FileManager.default.createFile(atPath: eventsOutputURL.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: eventsOutputURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}

enum MenuBarValidationConfiguration {
    static let outputPathEnvironmentKey = "CODEXPILL_VALIDATION_OUTPUT"
    static let eventsOutputPathEnvironmentKey = "CODEXPILL_VALIDATION_EVENTS_OUTPUT"
    static let scenarioEnvironmentKey = "CODEXPILL_VALIDATION_SCENARIO"

    static func makeSink(environment: [String: String] = ProcessInfo.processInfo.environment) -> MenuBarValidationSink? {
        guard let outputPath = environment[outputPathEnvironmentKey], !outputPath.isEmpty else {
            return nil
        }

        let outputURL = URL(fileURLWithPath: outputPath)
        let eventsURL: URL
        if let explicitEventsPath = environment[eventsOutputPathEnvironmentKey], !explicitEventsPath.isEmpty {
            eventsURL = URL(fileURLWithPath: explicitEventsPath)
        } else {
            eventsURL = outputURL.deletingLastPathComponent().appendingPathComponent("validation-events.jsonl")
        }

        return FileMenuBarValidationSink(outputURL: outputURL, eventsOutputURL: eventsURL)
    }

    static func scenario(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        MenuBarRuntimeWorkflowScenario.normalize(environment[scenarioEnvironmentKey])
    }
}
