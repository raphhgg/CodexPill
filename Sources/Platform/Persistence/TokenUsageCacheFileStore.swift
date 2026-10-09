import Foundation

struct TokenUsageCacheFileStore<Entry: Codable>: Sendable {
    let cacheFile: URL
    let schemaVersion: Int

    func readEntries() -> [Entry] {
        readPayload().map { Array($0.entries.values) } ?? []
    }

    func writeEntry(_ entry: Entry, forKey key: String) throws {
        try FilePermissionHardening.createPrivateDirectory(at: cacheFile.deletingLastPathComponent())

        var entries = readPayload()?.entries ?? [:]
        entries[key] = entry
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(Payload(schemaVersion: schemaVersion, entries: entries))
            .write(to: cacheFile, options: [.atomic])
        try FilePermissionHardening.repairPrivateFile(at: cacheFile)
    }

    private func readPayload() -> Payload? {
        guard let data = try? Data(contentsOf: cacheFile),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.schemaVersion == schemaVersion
        else {
            return nil
        }
        return payload
    }

    private struct Payload: Codable {
        var schemaVersion: Int
        var entries: [String: Entry]
    }
}
