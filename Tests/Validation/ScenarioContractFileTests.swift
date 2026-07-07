import Foundation
import Testing

private let hostedUiStructureCommonNonClaims = [
    "Does not prove pixel rendering, typography, spacing, or screenshot visual fidelity.",
    "Does not prove native menu opening, native click routing, focus, or hittability.",
    "Does not prove the live macOS menu bar surface."
]

struct ScenarioContractFileTests {
    @Test
    func kiteValidationContractsPackageOwnsGenericStructurePayloads() throws {
        let root = try repositoryRoot()
        let project = try String(contentsOf: root.appendingPathComponent("Project.swift"), encoding: .utf8)
        let exporter = try String(
            contentsOf: root
                .appendingPathComponent("Sources", isDirectory: true)
                .appendingPathComponent("Features", isDirectory: true)
                .appendingPathComponent("MenuBar", isDirectory: true)
                .appendingPathComponent("Validation", isDirectory: true)
                .appendingPathComponent("MenuBarStructureContractExporter.swift"),
            encoding: .utf8
        )

        #expect(project.contains("https://github.com/raphhgg/kite-validation-contracts-swift.git"))
        #expect(project.contains(".package(product: \"KiteValidationContracts\")"))
        #expect(exporter.contains("import KiteValidationContracts"))
        #expect(exporter.contains("typealias UiStructureContractArtifact = KiteUiStructureContract"))
        #expect(!exporter.contains("struct UiStructureContractArtifact"))
        #expect(!exporter.contains("struct UiStructureNodeArtifact"))
        #expect(!exporter.contains("struct UiStructureAssertionArtifact"))
    }

    @Test
    func scenarioPackFilesAreMinimalAndUniquelyAddressed() throws {
        let root = try repositoryRoot()
        let productURL = root
            .appendingPathComponent(".kite", isDirectory: true)
            .appendingPathComponent("product.json")
        let contractsDirectory = root
            .appendingPathComponent(".kite", isDirectory: true)
            .appendingPathComponent("scenarios", isDirectory: true)
        let makefile = try String(contentsOf: root.appendingPathComponent("Makefile"), encoding: .utf8)

        let productObject = try JSONObject.make(from: Data(contentsOf: productURL))
        #expect(try productObject.string(forKey: "kind") == "product_scenario_pack")
        #expect(try productObject.string(forKey: "schemaVersion") == "kite.validation.scenario-pack.v1")
        let defaults = try productObject.object(forKey: "scenarioDefaults")
        #expect(try defaults.string(forKey: "commandProfile") == "selected-tests")
        let commandProfiles = try defaults.object(forKey: "commandProfiles")
        let selectedTests = try commandProfiles.object(forKey: "selected-tests")
        #expect(try selectedTests.string(forKey: "run") == "make verify-selected-tests SCENARIO={scenarioId} TEST_SELECTORS=\"{commandInput.testSelectors}\"")
        let makeTarget = try commandProfiles.object(forKey: "make-target")
        #expect(try makeTarget.string(forKey: "run") == "make {commandTarget} SCENARIO={scenarioId}")
        #expect(!makefile.contains("CODEXPILL_VALIDATION_REQUEST"))
        #expect(makefile.contains("KITE_SCENARIO_REQUEST") == false)
        let commandInputTemplates = try defaults.object(forKey: "commandInputTemplates")
        let testSelectors = try commandInputTemplates.object(forKey: "testSelectors")
        #expect(try testSelectors.string(forKey: "item") == "-only-testing:{value}")
        #expect(try testSelectors.string(forKey: "separator") == " ")
        let presets = try defaults.object(forKey: "presets")
        let hostedUiStructure = try presets.object(forKey: "hosted-ui-structure")
        let hostedProof = try hostedUiStructure.object(forKey: "proof")
        #expect(try hostedProof.string(forKey: "layer") == "ui-structure-contract")
        #expect(try hostedProof.string(forKey: "artifactSource") == "hosted-menu-structure-exporter")
        #expect(try hostedProof.stringArray(forKey: "nonClaims") == hostedUiStructureCommonNonClaims)
        let hostedValidationIntent = try hostedUiStructure.object(forKey: "validationIntent")
        #expect(try hostedValidationIntent.stringArray(forKey: "nonClaims") == hostedUiStructureCommonNonClaims)
        let hostedArtifact = try hostedUiStructure.object(forKey: "artifact")
        #expect(try hostedArtifact.string(forKey: "kind") == "ui_structure_contract")
        #expect(try hostedArtifact.string(forKey: "path") == "build/verification/{scenarioId}/ui-structure-contract.json")
        #expect(makefile.contains("\nverify-selected-tests:"))

        let contractURLs = try dedicatedContractURLs(in: contractsDirectory)
        let contractIDs = try contractURLs.map { url in
            let object = try JSONObject.make(from: Data(contentsOf: url))
            let id = try object.string(forKey: "id")

            #expect(url.lastPathComponent == "\(id).json")
            #expect(object.containsObject(forKey: "feature"))
            #expect(!object.containsValue(forKey: "featureId"))
            #expect(!object.containsValue(forKey: "validationModes"))
            #expect(!object.containsValue(forKey: "command"))
            try assertMinimalCommandDeclaration(in: object, scenarioID: id, makefile: makefile)
            try assertHostedUiStructurePresetUsage(in: object, scenarioID: id)
            try assertNoLegacyKiteLocalEvidence(in: object, scenarioID: id)
            return id
        }

        #expect(contractIDs.count == 37)
        #expect(contractIDs.count == Set(contractIDs).count)
    }

    @Test
    func productDocsDoNotReferenceLegacyLocalScenarioReceipts() throws {
        let root = try repositoryRoot()
        let docsDirectory = root.appendingPathComponent("docs", isDirectory: true)
        let legacyReceiptNames = [
            "scenario-summary.json",
            "workflow-receipt.json",
            "contract-receipt.json",
            "validation-receipt.json",
            "cleanup-receipt.json"
        ]

        let offenders = try markdownURLs(in: docsDirectory).flatMap { url in
            let text = try String(contentsOf: url, encoding: .utf8)
            let documentOffenders: [String] = legacyReceiptNames.compactMap { receiptName -> String? in
                guard text.contains(receiptName) else {
                    return nil
                }
                return "\(relativePath(for: url, from: root)) contains \(receiptName)"
            }
            return documentOffenders
        }

        #expect(offenders == [])
    }

    private func assertNoLegacyKiteLocalEvidence(
        in object: JSONObject,
        scenarioID: String
    ) throws {
        let legacyEvidence = Set([
            "scenario-summary",
            "workflow-receipt",
            "contract-receipt",
            "validation-receipt",
            "cleanup-receipt"
        ])
        let legacyArtifactKinds = Set([
            "reconciliation_report",
            "workflow_event_log",
            "contract_receipt",
            "validation_receipt",
            "cleanup_receipt"
        ])
        let expectedArtifacts = try object.arrayObjectsIfPresent(forKey: "expectedArtifacts")

        for artifact in expectedArtifacts {
            let kind = try artifact.string(forKey: "kind")
            let path = try artifact.string(forKey: "path")

            #expect(
                !legacyArtifactKinds.contains(kind),
                "\(scenarioID) should rely on Kite's scenario receipt instead of requiring \(kind)"
            )
            #expect(
                !path.hasSuffix("scenario-summary.json"),
                "\(scenarioID) should not require product-local scenario-summary.json"
            )
            #expect(
                !path.hasSuffix("workflow-receipt.json")
                    && !path.hasSuffix("contract-receipt.json")
                    && !path.hasSuffix("validation-receipt.json")
                    && !path.hasSuffix("cleanup-receipt.json"),
                "\(scenarioID) should not require product-local receipt artifacts"
            )
        }

        let validationIntent = try object.object(forKey: "validationIntent")
        let requiredEvidence = try validationIntent.stringArrayIfPresent(forKey: "requiredEvidence")
        #expect(
            legacyEvidence.isDisjoint(with: Set(requiredEvidence)),
            "\(scenarioID) requiredEvidence should not list legacy local summary or receipt evidence"
        )
    }

    private func assertMinimalCommandDeclaration(
        in object: JSONObject,
        scenarioID: String,
        makefile: String
    ) throws {
        if scenarioID == "token-usage-privacy-no-raw-session" {
            let commandTarget = try object.string(forKey: "commandTarget")
            #expect(try object.string(forKey: "commandProfile") == "make-target")
            #expect(commandTarget == "verify-token-usage-privacy-scenario")
            #expect(
                makefile.contains("\n\(commandTarget):"),
                "\(scenarioID) commandTarget \(commandTarget) should be a Make target"
            )
            return
        }

        #expect(!object.containsValue(forKey: "commandTarget"))
        #expect(!object.containsValue(forKey: "commandProfile"))

        let commandInputs = try object.object(forKey: "commandInputs")
        let selectors = try commandInputs.stringArray(forKey: "testSelectors")
        #expect(!selectors.isEmpty, "\(scenarioID) should declare focused test selectors")
        #expect(selectors.allSatisfy { $0.hasPrefix("CodexPillTests/") })
    }

    private func assertHostedUiStructurePresetUsage(
        in object: JSONObject,
        scenarioID: String
    ) throws {
        let hostedStructureScenarioIDs: Set<String> = [
            "hosted-menu-default",
            "menu-busy-status",
            "menu-empty-catalog",
            "menu-account-overflow",
            "menu-unmatched-active-account"
        ]
        guard hostedStructureScenarioIDs.contains(scenarioID) else {
            return
        }

        #expect(try object.stringArray(forKey: "presets") == ["hosted-ui-structure"])
        #expect(!object.containsValue(forKey: "expectedArtifacts"))

        let artifact = try object.object(forKey: "artifact")
        #expect(try artifact.stringArray(forKey: "claimScope") == ["\(scenarioID)-structure"])

        let commonNonClaims = Set(hostedUiStructureCommonNonClaims)
        let proof = try object.object(forKey: "proof")
        let validationIntent = try object.object(forKey: "validationIntent")
        #expect(commonNonClaims.isDisjoint(with: Set(try proof.stringArrayIfPresent(forKey: "nonClaims"))))
        #expect(commonNonClaims.isDisjoint(with: Set(try validationIntent.stringArrayIfPresent(forKey: "nonClaims"))))
    }

    private func repositoryRoot(filePath: String = #filePath) throws -> URL {
        var directory = URL(fileURLWithPath: filePath).deletingLastPathComponent()

        while directory.path != "/" {
            let markerURL = directory
                .appendingPathComponent(".kite", isDirectory: true)
                .appendingPathComponent("product.json")
            if FileManager.default.fileExists(atPath: markerURL.path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }

        throw ScenarioContractFileTestError.missingRepositoryRoot
    }

    private func dedicatedContractURLs(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ScenarioContractFileTestError.missingContractsDirectory(directory.path)
        }

        return try enumerator.compactMap { entry in
            guard let url = entry as? URL, url.pathExtension == "json" else {
                return nil
            }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true ? url : nil
        }
        .sorted { $0.path < $1.path }
    }

    private func markdownURLs(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ScenarioContractFileTestError.missingDocsDirectory(directory.path)
        }

        return try enumerator.compactMap { entry in
            guard let url = entry as? URL, url.pathExtension == "md" else {
                return nil
            }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true ? url : nil
        }
        .sorted { $0.path < $1.path }
    }

    private func relativePath(for url: URL, from root: URL) -> String {
        url.path.replacingOccurrences(of: "\(root.path)/", with: "")
    }
}

private enum JSONObject: Equatable {
    case object([String: JSONObject])
    case array([JSONObject])
    case string(String)
    case number(Decimal)
    case bool(Bool)
    case null

    static func make(from data: Data) throws -> JSONObject {
        try make(from: JSONSerialization.jsonObject(with: data))
    }

    private static func make(from value: Any) throws -> JSONObject {
        switch value {
        case let object as [String: Any]:
            return .object(try object.mapValues { try make(from: $0) })
        case let array as [Any]:
            return .array(try array.map { try make(from: $0) })
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            return .number(number.decimalValue)
        case _ as NSNull:
            return .null
        default:
            throw ScenarioContractFileTestError.unsupportedJSONValue
        }
    }

    func containsObject(forKey key: String) -> Bool {
        guard case let .object(dictionary) = self,
              case .object = dictionary[key] else {
            return false
        }
        return true
    }

    func object(forKey key: String) throws -> JSONObject {
        guard case let .object(dictionary) = self,
              case let .object(value) = dictionary[key] else {
            throw ScenarioContractFileTestError.missingJSONObject(key)
        }
        return .object(value)
    }

    func arrayObjects(forKey key: String) throws -> [JSONObject] {
        guard case let .object(dictionary) = self,
              case let .array(values) = dictionary[key] else {
            throw ScenarioContractFileTestError.missingJSONArray(key)
        }
        return try values.map { value in
            guard case .object = value else {
                throw ScenarioContractFileTestError.missingJSONObject(key)
            }
            return value
        }
    }

    func arrayObjectsIfPresent(forKey key: String) throws -> [JSONObject] {
        guard case let .object(dictionary) = self,
              let jsonValue = dictionary[key] else {
            return []
        }
        guard case let .array(values) = jsonValue else {
            throw ScenarioContractFileTestError.missingJSONArray(key)
        }
        return try values.map { value in
            guard case .object = value else {
                throw ScenarioContractFileTestError.missingJSONObject(key)
            }
            return value
        }
    }

    func stringArray(forKey key: String) throws -> [String] {
        guard case let .object(dictionary) = self,
              case let .array(values) = dictionary[key] else {
            throw ScenarioContractFileTestError.missingJSONArray(key)
        }
        return try values.map { value in
            guard case let .string(string) = value else {
                throw ScenarioContractFileTestError.missingJSONString(key)
            }
            return string
        }
    }

    func stringArrayIfPresent(forKey key: String) throws -> [String] {
        guard case let .object(dictionary) = self,
              let jsonValue = dictionary[key] else {
            return []
        }
        guard case let .array(values) = jsonValue else {
            throw ScenarioContractFileTestError.missingJSONArray(key)
        }
        return try values.map { value in
            guard case let .string(string) = value else {
                throw ScenarioContractFileTestError.missingJSONString(key)
            }
            return string
        }
    }

    func containsValue(forKey key: String) -> Bool {
        guard case let .object(dictionary) = self else {
            return false
        }
        return dictionary[key] != nil
    }

    func string(forKey key: String) throws -> String {
        guard case let .object(dictionary) = self,
              case let .string(value) = dictionary[key] else {
            throw ScenarioContractFileTestError.missingJSONString(key)
        }
        return value
    }
}

private enum ScenarioContractFileTestError: Error {
    case missingRepositoryRoot
    case missingContractsDirectory(String)
    case missingDocsDirectory(String)
    case missingJSONObject(String)
    case missingJSONArray(String)
    case missingJSONString(String)
    case unsupportedJSONValue
}
