import Foundation

enum ClaudeUsageReadError: Error, Equatable, Sendable {
    case unreadable
    case malformed(ClaudeUsageParseError)
}

struct ClaudeUsageReader: Sendable {
    static let fileName = "claude-usage.json"

    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let supportRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return supportRoot
            .appendingPathComponent("CodexPill", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    func read(now: Date = Date()) throws(ClaudeUsageReadError) -> ClaudeUsageStatus {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .notConnected
        } catch {
            throw .unreadable
        }

        let record: ClaudeUsageRecord
        do {
            record = try ClaudeUsageRecord.parse(data)
        } catch {
            throw .malformed(error)
        }
        return ClaudeUsageStatus.evaluate(record: record, now: now)
    }
}
