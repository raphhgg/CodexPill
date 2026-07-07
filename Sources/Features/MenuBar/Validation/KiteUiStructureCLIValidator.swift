import Foundation

struct KiteUiStructureValidationSummary: Equatable {
    let contractId: String
    let scenarioId: String
    let assertionCount: Int
}

struct KiteUiStructureValidationFailure: Error, Equatable, CustomStringConvertible, LocalizedError {
    let code: String
    let message: String
    let path: String?
    let terminationStatus: Int32

    init(code: String, message: String, path: String?, terminationStatus: Int32) {
        self.code = code
        self.message = Self.sanitizedMessage(code: code, message: message)
        self.path = path
        self.terminationStatus = terminationStatus
    }

    var description: String {
        let pathSuffix = path.map { " (\($0))" } ?? ""
        return "\(code): \(message)\(pathSuffix)"
    }

    var errorDescription: String? {
        description
    }

    private static func sanitizedMessage(code: String, message: String) -> String {
        guard code == "ui_structure_contract.private_payload" else {
            return message
        }
        return "Kite rejected the UI structure contract because it contains private payload."
    }
}

struct KiteUiStructureCLIValidator {
    private let commandRunner: any CommandRunner
    private let executableURL: URL
    private let commandName: String

    init(
        commandRunner: any CommandRunner = ProcessCommandRunner(),
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/env"),
        commandName: String = "kite"
    ) {
        self.commandRunner = commandRunner
        self.executableURL = executableURL
        self.commandName = commandName
    }

    func validate(artifactURL: URL) async throws -> KiteUiStructureValidationSummary {
        let result = try await commandRunner.run(
            executableURL: executableURL,
            arguments: [
                commandName,
                "ui-structure",
                "validate",
                "--artifact",
                artifactURL.path,
                "--json"
            ]
        )
        let envelope = try? Self.decodeEnvelope(from: result.standardOutput)

        if result.terminationStatus == 0, let envelope, envelope.status == "passed" {
            return try Self.summary(from: envelope, terminationStatus: result.terminationStatus)
        }

        if let envelope, envelope.status == "failed" {
            throw Self.failure(from: envelope, terminationStatus: result.terminationStatus)
        }

        throw KiteUiStructureValidationFailure(
            code: result.terminationStatus == 0
                ? "kite.ui_structure.invalid_output"
                : "kite.ui_structure.validation_failed",
            message: result.terminationStatus == 0
                ? "Kite UI structure validation passed without typed JSON output."
                : "Kite UI structure validation failed without typed JSON output.",
            path: nil,
            terminationStatus: result.terminationStatus
        )
    }

    private static func decodeEnvelope(from data: Data) throws -> KiteUiStructureValidationEnvelope {
        try JSONDecoder().decode(KiteUiStructureValidationEnvelope.self, from: data)
    }

    private static func summary(
        from envelope: KiteUiStructureValidationEnvelope,
        terminationStatus: Int32
    ) throws -> KiteUiStructureValidationSummary {
        guard
            let contractId = envelope.contractId,
            let scenarioId = envelope.scenarioId,
            let assertionCount = envelope.assertionCount
        else {
            throw KiteUiStructureValidationFailure(
                code: "kite.ui_structure.invalid_output",
                message: "Kite UI structure validation passed without a complete summary.",
                path: nil,
                terminationStatus: terminationStatus
            )
        }

        return KiteUiStructureValidationSummary(
            contractId: contractId,
            scenarioId: scenarioId,
            assertionCount: assertionCount
        )
    }

    private static func failure(
        from envelope: KiteUiStructureValidationEnvelope,
        terminationStatus: Int32
    ) -> KiteUiStructureValidationFailure {
        KiteUiStructureValidationFailure(
            code: envelope.code ?? "kite.ui_structure.validation_failed",
            message: envelope.message ?? "Kite UI structure validation failed.",
            path: envelope.path,
            terminationStatus: terminationStatus
        )
    }
}

private struct KiteUiStructureValidationEnvelope: Decodable {
    let status: String?
    let contractId: String?
    let scenarioId: String?
    let assertionCount: Int?
    let code: String?
    let message: String?
    let path: String?
}
