import Foundation

/// One deduplicated Claude Code API response: a local day, a model, and its tokens.
struct ClaudeTokenUsageRow: Codable, Equatable, Sendable {
    /// `message.id` and `requestId`, so the same response written to several rows or files counts once.
    var key: String
    var day: Date
    var model: String
    var tokens: Int
}

/// What one session file contributed, so unchanged files are not read again.
struct ClaudeTokenUsageFileContribution: Codable, Equatable, Sendable {
    var cacheKey: String
    var fileSize: Int
    var modificationDate: Date?
    var rows: [ClaudeTokenUsageRow]
}

struct ClaudeTokenUsageScanResult: Equatable, Sendable {
    var days: [ToolDailyTokenUsage]
    var fileContributions: [ClaudeTokenUsageFileContribution]
}

/// Reads token counts from Claude Code's local session transcripts.
///
/// Claude Code writes one JSONL file per session under `<config>/projects/<project>/`, with subagent
/// sessions in nested folders. Assistant rows carry `message.usage`. Only token counts, the model, the
/// timestamp, and the response IDs are read. Prompt and response content is never decoded into memory
/// beyond the line being parsed and never kept.
struct ClaudeSessionTokenUsageScanner: Sendable {
    private static let maximumLineByteCount = 1 * 1024 * 1024
    private static let chunkByteCount = 64 * 1024
    private static let assistantNeedle = Data(#""assistant""#.utf8)
    private static let usageNeedle = Data(#""usage""#.utf8)
    /// Claude Code deletes transcripts after 30 days by default. Cached rows for deleted files are kept this long.
    private static let retainedHistoryDayCount = 400

    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// `CLAUDE_CONFIG_DIR/projects` when set, otherwise `~/.claude/projects`, matching Claude Code.
    static func defaultProjectsDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        ClaudeCredentialsSource.configDirectory(environment: environment)
            .appendingPathComponent("projects", isDirectory: true)
    }

    /// Scans files changed since the period began and reuses cached rows for the rest.
    ///
    /// Rows from files Claude Code has since deleted stay in the result, so history outlives its transcripts.
    func scan(
        projectsDirectory: URL,
        interval: DateInterval,
        cachedFileContributions: [ClaudeTokenUsageFileContribution],
        now: Date = Date()
    ) throws -> ClaudeTokenUsageScanResult {
        let cachedByKey = Dictionary(
            cachedFileContributions.map { ($0.cacheKey, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        var contributionsByKey = cachedByKey

        for file in try sessionFiles(in: projectsDirectory) {
            try Task.checkCancellation()
            if let cached = cachedByKey[file.cacheKey],
               cached.fileSize == file.fileSize,
               cached.modificationDate.isSameInstant(as: file.modificationDate) {
                continue
            }
            // A file last written before the period began holds no rows inside it.
            if cachedByKey[file.cacheKey] == nil,
               let modified = file.modificationDate,
               modified < interval.start {
                continue
            }
            contributionsByKey[file.cacheKey] = ClaudeTokenUsageFileContribution(
                cacheKey: file.cacheKey,
                fileSize: file.fileSize,
                modificationDate: file.modificationDate,
                rows: try rows(in: file.url)
            )
        }

        let oldestRetainedDay = calendar.date(
            byAdding: .day,
            value: -Self.retainedHistoryDayCount,
            to: calendar.startOfDay(for: now)
        ) ?? .distantPast
        let contributions = contributionsByKey.values
            .filter { contribution in contribution.rows.contains { $0.day >= oldestRetainedDay } }
            .sorted { $0.cacheKey < $1.cacheKey }

        return ClaudeTokenUsageScanResult(
            days: Self.days(from: contributions, in: interval, calendar: calendar),
            fileContributions: contributions
        )
    }

    static func days(
        from contributions: [ClaudeTokenUsageFileContribution],
        in interval: DateInterval,
        calendar: Calendar
    ) -> [ToolDailyTokenUsage] {
        var rowsByKey: [String: ClaudeTokenUsageRow] = [:]
        for contribution in contributions {
            for row in contribution.rows {
                rowsByKey[row.key] = row
            }
        }
        let usage = rowsByKey.values
            .filter { interval.contains($0.day) }
            .map { ToolDailyTokenUsage(day: $0.day, tokensByModel: [$0.model: $0.tokens]) }
        return ToolTokenUsageDays.filled(usage, in: interval, calendar: calendar)
    }

    private func rows(in url: URL) throws -> [ClaudeTokenUsageRow] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        // Streaming writes repeat a response's usage on each row. The last one wins.
        var rowsByKey: [String: ClaudeTokenUsageRow] = [:]
        var buffer = Data()
        var discardingOversizedLine = false
        while true {
            try Task.checkCancellation()
            let chunk = handle.readData(ofLength: Self.chunkByteCount)
            guard !chunk.isEmpty else { break }
            buffer.append(chunk)

            var lineStart = buffer.startIndex
            while let newline = buffer[lineStart...].firstIndex(of: 0x0A) {
                if discardingOversizedLine {
                    discardingOversizedLine = false
                } else {
                    addRow(from: buffer[lineStart..<newline], to: &rowsByKey)
                }
                lineStart = buffer.index(after: newline)
            }
            if lineStart > buffer.startIndex {
                buffer.removeSubrange(..<lineStart)
            }
            if buffer.count > Self.maximumLineByteCount {
                buffer.removeAll()
                discardingOversizedLine = true
            }
        }
        if !discardingOversizedLine {
            addRow(from: buffer[...], to: &rowsByKey)
        }
        return rowsByKey.values.sorted { $0.key < $1.key }
    }

    private func addRow(from line: Data.SubSequence, to rowsByKey: inout [String: ClaudeTokenUsageRow]) {
        guard line.count <= Self.maximumLineByteCount,
              line.range(of: Self.assistantNeedle) != nil,
              line.range(of: Self.usageNeedle) != nil
        else {
            return
        }
        autoreleasepool {
            guard let entry = try? JSONDecoder().decode(TranscriptEntry.self, from: Data(line)),
                  entry.type == "assistant",
                  let message = entry.message,
                  let usage = message.usage,
                  let timestamp = entry.timestamp.flatMap(Self.parseTimestamp)
            else {
                return
            }
            let tokens = usage.totalTokens
            guard tokens > 0 else { return }
            let model = message.model.flatMap { $0.isEmpty || $0 == "<synthetic>" ? nil : $0 } ?? "unknown"
            let key = [message.id, entry.requestId].compactMap { $0 }.joined(separator: ":")
            let row = ClaudeTokenUsageRow(
                key: key.isEmpty ? "\(timestamp.timeIntervalSince1970):\(model):\(tokens)" : key,
                day: calendar.startOfDay(for: timestamp),
                model: model,
                tokens: tokens
            )
            rowsByKey[row.key] = row
        }
    }

    private func sessionFiles(in directory: URL) throws -> [SessionFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let rootPath = directory.standardizedFileURL.path
        var files: [SessionFile] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let size = values.fileSize, size > 0
            else {
                continue
            }
            let path = url.standardizedFileURL.path
            let relativePath = path.hasPrefix(rootPath) ? String(path.dropFirst(rootPath.count)) : url.lastPathComponent
            files.append(SessionFile(
                url: url,
                cacheKey: relativePath,
                fileSize: size,
                modificationDate: values.contentModificationDate
            ))
        }
        return files
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}

private struct SessionFile {
    var url: URL
    var cacheKey: String
    var fileSize: Int
    var modificationDate: Date?
}

private struct TranscriptEntry: Decodable {
    var type: String?
    var timestamp: String?
    var requestId: String?
    var message: Message?

    struct Message: Decodable {
        var id: String?
        var model: String?
        var usage: Usage?
    }

    struct Usage: Decodable {
        var input_tokens: Int?
        var output_tokens: Int?
        var cache_creation_input_tokens: Int?
        var cache_read_input_tokens: Int?

        var totalTokens: Int {
            (input_tokens ?? 0) + (output_tokens ?? 0) + (cache_creation_input_tokens ?? 0) + (cache_read_input_tokens ?? 0)
        }
    }

    // `message.content` and every other field are skipped, never decoded.
    private enum CodingKeys: String, CodingKey {
        case type, timestamp, requestId, message
    }
}

private extension Optional where Wrapped == Date {
    func isSameInstant(as other: Date?) -> Bool {
        switch (self, other) {
        case (.none, .none):
            return true
        case (.some(let lhs), .some(let rhs)):
            return abs(lhs.timeIntervalSince(rhs)) < 0.001
        default:
            return false
        }
    }
}
