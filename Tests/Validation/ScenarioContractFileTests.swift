import Foundation
import Testing

struct ScenarioContractFileTests {
    @Test
    func scenarioPackFilesAreMinimalAndUniquelyAddressed() throws {
        let root = try repositoryRoot()
        let productURL = root
            .appendingPathComponent(".kite", isDirectory: true)
            .appendingPathComponent("product.json")
        let contractsDirectory = root
            .appendingPathComponent(".kite", isDirectory: true)
            .appendingPathComponent("scenarios", isDirectory: true)

        let productObject = try JSONObject.make(from: Data(contentsOf: productURL))
        #expect(try productObject.string(forKey: "kind") == "product_scenario_pack")
        #expect(try productObject.string(forKey: "schemaVersion") == "kite.validation.scenario-pack.v1")

        let contractURLs = try dedicatedContractURLs(in: contractsDirectory)
        let contractIDs = try contractURLs.map { url in
            let object = try JSONObject.make(from: Data(contentsOf: url))
            let id = try object.string(forKey: "id")

            #expect(url.lastPathComponent == "\(id).json")
            #expect(object.containsObject(forKey: "feature"))
            #expect(!object.containsValue(forKey: "featureId"))
            #expect(!object.containsValue(forKey: "validationModes"))
            return id
        }

        #expect(contractIDs.count == 37)
        #expect(contractIDs.count == Set(contractIDs).count)
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
}

private struct ScenarioManifest: Decodable {
    let scenarios: [ScenarioReference]
}

private struct ScenarioReference: Decodable {
    let id: String
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
    case missingJSONString(String)
    case unsupportedJSONValue
}
