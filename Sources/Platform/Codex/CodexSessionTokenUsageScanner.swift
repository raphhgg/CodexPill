import Foundation

struct CodexSessionTokenUsageScanResult: Equatable {
    var buckets: [CodexSessionTokenUsageBucket]
    var summary: CodexSessionTokenUsageScanSummary
}

struct CodexSessionTokenUsageBucket: Equatable {
    var day: Date
    var usage: CodexSessionTokenUsage
    var models: [String]
}

struct CodexSessionTokenUsage: Equatable {
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
    var reasoningOutputTokens: Int
    var totalTokens: Int

    static let zero = CodexSessionTokenUsage(
        inputTokens: 0,
        cachedInputTokens: 0,
        outputTokens: 0,
        reasoningOutputTokens: 0,
        totalTokens: 0
    )

    static func + (lhs: CodexSessionTokenUsage, rhs: CodexSessionTokenUsage) -> CodexSessionTokenUsage {
        CodexSessionTokenUsage(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            cachedInputTokens: lhs.cachedInputTokens + rhs.cachedInputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            reasoningOutputTokens: lhs.reasoningOutputTokens + rhs.reasoningOutputTokens,
            totalTokens: lhs.totalTokens + rhs.totalTokens
        )
    }

    static func - (lhs: CodexSessionTokenUsage, rhs: CodexSessionTokenUsage) -> CodexSessionTokenUsage {
        CodexSessionTokenUsage(
            inputTokens: lhs.inputTokens - rhs.inputTokens,
            cachedInputTokens: lhs.cachedInputTokens - rhs.cachedInputTokens,
            outputTokens: lhs.outputTokens - rhs.outputTokens,
            reasoningOutputTokens: lhs.reasoningOutputTokens - rhs.reasoningOutputTokens,
            totalTokens: lhs.totalTokens - rhs.totalTokens
        )
    }

    var hasPositiveTotal: Bool {
        totalTokens > 0
    }
}

struct CodexSessionTokenUsageScanSummary: Equatable {
    var filesRead: Int
    var tokenCountRowsRead: Int
    var cumulativeRowsUsed: Int
    var cumulativeRowsIgnored: Int
    var malformedRowsIgnored: Int
    var nonUsageRowsIgnored: Int
}

struct CodexSessionTokenUsageScanner {
    private let fileManager: FileManager
    private let calendar: Calendar

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        self.calendar = calendar
    }

    func scan(sessionsDirectory: URL, dayRange: DateInterval) throws -> CodexSessionTokenUsageScanResult {
        var accumulator = BucketAccumulator()
        var summary = CodexSessionTokenUsageScanSummary(
            filesRead: 0,
            tokenCountRowsRead: 0,
            cumulativeRowsUsed: 0,
            cumulativeRowsIgnored: 0,
            malformedRowsIgnored: 0,
            nonUsageRowsIgnored: 0
        )

        for file in try sessionFiles(in: sessionsDirectory) {
            guard let day = sessionDay(for: file, under: sessionsDirectory),
                  dayRange.contains(day)
            else {
                continue
            }

            summary.filesRead += 1
            let scan = scanFile(file, day: day)
            accumulator.merge(scan.buckets)
            summary.tokenCountRowsRead += scan.summary.tokenCountRowsRead
            summary.cumulativeRowsUsed += scan.summary.cumulativeRowsUsed
            summary.cumulativeRowsIgnored += scan.summary.cumulativeRowsIgnored
            summary.malformedRowsIgnored += scan.summary.malformedRowsIgnored
            summary.nonUsageRowsIgnored += scan.summary.nonUsageRowsIgnored
        }

        return CodexSessionTokenUsageScanResult(
            buckets: accumulator.buckets(),
            summary: summary
        )
    }

    private func scanFile(_ url: URL, day: Date) -> CodexSessionTokenUsageScanResult {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return CodexSessionTokenUsageScanResult(buckets: [], summary: emptySummary)
        }

        var summary = emptySummary
        var accumulator = BucketAccumulator()
        var currentModel: String?
        var previousTotalUsage: CodexSessionTokenUsage?

        for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            guard
                let data = String(line).data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let payload = object["payload"] as? [String: Any]
            else {
                summary.malformedRowsIgnored += 1
                continue
            }

            switch payload["type"] as? String {
            case "turn_context":
                currentModel = payload["model"] as? String
                summary.nonUsageRowsIgnored += 1
            case "token_count":
                summary.tokenCountRowsRead += 1
                if let usage = usagePayload(named: "last_token_usage", in: payload), usage.hasPositiveTotal {
                    accumulator.add(usage, model: currentModel, day: day)
                } else if let totalUsage = usagePayload(named: "total_token_usage", in: payload) {
                    let delta = previousTotalUsage.map { totalUsage - $0 } ?? totalUsage
                    previousTotalUsage = totalUsage
                    if delta.hasPositiveTotal {
                        accumulator.add(delta, model: currentModel, day: day)
                        summary.cumulativeRowsUsed += 1
                    } else {
                        summary.cumulativeRowsIgnored += 1
                    }
                }
            default:
                if currentModel == nil, let model = payload["model"] as? String, !model.isEmpty {
                    currentModel = model
                }
                summary.nonUsageRowsIgnored += 1
            }
        }

        return CodexSessionTokenUsageScanResult(
            buckets: accumulator.buckets(),
            summary: summary
        )
    }

    private func sessionFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { entry in
            guard
                let url = entry as? URL,
                url.pathExtension == "jsonl",
                try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            else {
                return nil
            }
            return url
        }
        .sorted { $0.path < $1.path }
    }

    private func sessionDay(for file: URL, under root: URL) -> Date? {
        let rootParts = root.standardizedFileURL.pathComponents
        let fileParts = file.standardizedFileURL.pathComponents
        let parts = Array(fileParts.dropFirst(rootParts.count))
        guard parts.count >= 4,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return nil
        }

        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        ))
    }

    private func usagePayload(named name: String, in payload: [String: Any]) -> CodexSessionTokenUsage? {
        let container = (payload["info"] as? [String: Any]) ?? payload
        guard let usage = container[name] as? [String: Any] else {
            return nil
        }

        return CodexSessionTokenUsage(
            inputTokens: intValue(for: "input_tokens", in: usage),
            cachedInputTokens: intValue(for: "cached_input_tokens", in: usage),
            outputTokens: intValue(for: "output_tokens", in: usage),
            reasoningOutputTokens: intValue(for: "reasoning_output_tokens", in: usage),
            totalTokens: intValue(for: "total_tokens", in: usage)
        )
    }

    private func intValue(for key: String, in object: [String: Any]) -> Int {
        if let value = object[key] as? Int {
            return value
        }
        if let value = object[key] as? Double {
            return Int(value)
        }
        return 0
    }

    private var emptySummary: CodexSessionTokenUsageScanSummary {
        CodexSessionTokenUsageScanSummary(
            filesRead: 0,
            tokenCountRowsRead: 0,
            cumulativeRowsUsed: 0,
            cumulativeRowsIgnored: 0,
            malformedRowsIgnored: 0,
            nonUsageRowsIgnored: 0
        )
    }
}

private struct BucketAccumulator {
    private var usageByDay: [Date: CodexSessionTokenUsage] = [:]
    private var modelsByDay: [Date: Set<String>] = [:]

    mutating func add(_ usage: CodexSessionTokenUsage, model: String?, day: Date) {
        usageByDay[day, default: .zero] = usageByDay[day, default: .zero] + usage
        if let model, !model.isEmpty {
            modelsByDay[day, default: []].insert(model)
        }
    }

    mutating func merge(_ buckets: [CodexSessionTokenUsageBucket]) {
        for bucket in buckets {
            usageByDay[bucket.day, default: .zero] = usageByDay[bucket.day, default: .zero] + bucket.usage
            modelsByDay[bucket.day, default: []].formUnion(bucket.models)
        }
    }

    func buckets() -> [CodexSessionTokenUsageBucket] {
        usageByDay.keys.sorted().map { day in
            CodexSessionTokenUsageBucket(
                day: day,
                usage: usageByDay[day, default: .zero],
                models: Array(modelsByDay[day, default: []]).sorted()
            )
        }
    }
}
