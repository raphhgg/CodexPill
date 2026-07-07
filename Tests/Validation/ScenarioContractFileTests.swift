import Foundation
import Testing

struct ScenarioContractFileTests {
    @Test
    func dedicatedScenarioContractsMatchAggregateManifestEntries() throws {
        let root = try repositoryRoot()
        let manifestURL = root
            .appendingPathComponent(".kite", isDirectory: true)
            .appendingPathComponent("scenarios.json")
        let contractsDirectory = root
            .appendingPathComponent(".kite", isDirectory: true)
            .appendingPathComponent("scenarios", isDirectory: true)

        let manifestData = try Data(contentsOf: manifestURL)
        let manifestObject = try JSONObject.make(from: manifestData)
        let manifest = try JSONDecoder().decode(ScenarioManifest.self, from: manifestData)
        let scenarioObjects = try manifestObject.objectArray(forKey: "scenarios")
        let manifestScenarioPairs = try scenarioObjects.map { object in
            (try object.string(forKey: "id"), object)
        }
        let manifestIDs = manifestScenarioPairs.map(\.0)
        let manifestScenariosByID = Dictionary(grouping: manifestScenarioPairs) { pair in
            pair.0
        }
        .compactMapValues { pairs in
            pairs.count == 1 ? pairs[0].1 : nil
        }

        let contractURLs = try dedicatedContractURLs(in: contractsDirectory)
        let contractPairs = try contractURLs.map { url in
            let object = try JSONObject.make(from: Data(contentsOf: url))
            return (try object.string(forKey: "id"), url)
        }
        let contractIDs = contractPairs.map(\.0)
        let contractIDsByURL = Dictionary(grouping: contractPairs) { pair in
            pair.0
        }
        .compactMapValues { pairs in
            pairs.count == 1 ? pairs[0].1 : nil
        }

        #expect(manifestIDs.count == Set(manifestIDs).count)
        #expect(contractURLs.count == manifest.scenarios.count)
        #expect(contractIDs.count == Set(contractIDs).count)
        #expect(Set(contractIDsByURL.keys) == Set(manifest.scenarios.map(\.id)))

        for scenario in manifest.scenarios {
            let contractURL = try #require(contractIDsByURL[scenario.id])
            #expect(contractURL.lastPathComponent == "\(scenario.id).json")

            let contractObject = try JSONObject.make(from: Data(contentsOf: contractURL))
            #expect(contractObject == manifestScenariosByID[scenario.id])
        }
    }

    private func repositoryRoot(filePath: String = #filePath) throws -> URL {
        var directory = URL(fileURLWithPath: filePath).deletingLastPathComponent()

        while directory.path != "/" {
            let markerURL = directory
                .appendingPathComponent(".kite", isDirectory: true)
                .appendingPathComponent("scenarios.json")
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

    func objectArray(forKey key: String) throws -> [JSONObject] {
        guard case let .object(dictionary) = self,
              case let .array(array) = dictionary[key] else {
            throw ScenarioContractFileTestError.missingJSONArray(key)
        }
        return array
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
    case missingJSONArray(String)
    case missingJSONString(String)
    case unsupportedJSONValue
}
