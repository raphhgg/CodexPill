import Foundation

struct CodexSessionTokenUsageScanResult: Equatable {
    var buckets: [CodexDailyTokenUsage]
    var summary: CodexSessionTokenUsageScanSummary
}

struct CodexSessionTokenUsageScanSummary: Equatable {
    var filesRead: Int
    var tokenCountRowsRead: Int
    var cumulativeRowsUsed: Int
    var cumulativeRowsIgnored: Int
    var malformedRowsIgnored: Int
    var nonUsageRowsIgnored: Int
}

struct CodexSessionTokenUsageScanner: Sendable {
    private static let defaultMaximumScannableFileByteCount = 0
    private static let defaultMaximumDailyScanByteBudget = 0
    private static let defaultMaximumLineByteCount = 1 * 1024 * 1024

    private let calendar: Calendar
    private let discoverer: CodexSessionTokenUsageFileDiscovering
    private let fileParser: CodexSessionTokenUsageFileParsing
    private let maximumScannableFileByteCount: Int
    private let maximumDailyScanByteBudget: Int

    init(
        fileManager: FileManager = .default,
        maximumScannableFileByteCount: Int = Self.defaultMaximumScannableFileByteCount,
        maximumDailyScanByteBudget: Int = Self.defaultMaximumDailyScanByteBudget,
        maximumLineByteCount: Int = Self.defaultMaximumLineByteCount,
        calendar: Calendar = .current
    ) {
        self.maximumScannableFileByteCount = maximumScannableFileByteCount
        self.maximumDailyScanByteBudget = maximumDailyScanByteBudget
        self.calendar = calendar
        discoverer = CodexSessionTokenUsageFileDiscoverer(fileManager: fileManager, calendar: calendar)
        fileParser = CodexSessionTokenUsageFileParser(maximumLineByteCount: maximumLineByteCount)
    }

    func scan(
        sessionsDirectory: URL,
        period: CodexTokenUsagePeriod,
        now: Date = Date(),
        progress: (@Sendable (TokenUsageScanProgress) -> Void)? = nil
    ) throws -> CodexSessionTokenUsageScanResult {
        let interval = dayRange(for: period, now: now)
        let result = try scan(sessionsDirectory: sessionsDirectory, dayRange: interval, progress: progress)
        return CodexSessionTokenUsageScanResult(
            buckets: fillMissingDays(in: interval, from: result.buckets),
            summary: result.summary
        )
    }

    func scanAllHistory(
        sessionsDirectory: URL,
        progress: (@Sendable (TokenUsageScanProgress) -> Void)? = nil
    ) throws -> CodexSessionTokenUsageScanResult {
        try scan(sessionsDirectory: sessionsDirectory, dayRange: nil, progress: progress)
    }

    func scan(
        sessionsDirectory: URL,
        dayRange: DateInterval,
        progress: (@Sendable (TokenUsageScanProgress) -> Void)? = nil
    ) throws -> CodexSessionTokenUsageScanResult {
        try scan(sessionsDirectory: sessionsDirectory, dayRange: Optional(dayRange), progress: progress)
    }

    private func scan(
        sessionsDirectory: URL,
        dayRange: DateInterval?,
        progress: (@Sendable (TokenUsageScanProgress) -> Void)? = nil
    ) throws -> CodexSessionTokenUsageScanResult {
        var accumulator = BucketAccumulator()
        var summary = CodexSessionTokenUsageScanSummary.empty
        var scannedByteCountByDay: [Date: Int] = [:]
        let files = try discoverer.sessionFiles(in: sessionsDirectory)
        progress?(TokenUsageScanProgress(scannedFiles: 0, totalFiles: files.count))

        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            defer {
                progress?(TokenUsageScanProgress(scannedFiles: index + 1, totalFiles: files.count))
            }
            if let dayRange, !dayRange.contains(file.day) {
                continue
            }

            guard let fileByteCount = scannableByteCount(for: file.url) else {
                summary.nonUsageRowsIgnored += 1
                continue
            }
            let scannedByteCountForDay = scannedByteCountByDay[file.day, default: 0]
            guard maximumDailyScanByteBudget <= 0
                    || scannedByteCountForDay + fileByteCount <= maximumDailyScanByteBudget
            else {
                summary.nonUsageRowsIgnored += 1
                continue
            }

            let scan = try fileParser.scanFile(file.url, day: file.day)
            accumulator.merge(scan.buckets)
            scannedByteCountByDay[file.day, default: 0] += fileByteCount
            summary.filesRead += 1
            summary.merge(scan.summary)
        }

        return CodexSessionTokenUsageScanResult(
            buckets: accumulator.buckets(),
            summary: summary
        )
    }

    private func scannableByteCount(for url: URL) -> Int? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize
        else {
            return nil
        }
        guard maximumScannableFileByteCount > 0 else {
            return fileSize
        }
        guard fileSize <= maximumScannableFileByteCount else {
            return nil
        }
        return fileSize
    }

    private func dayRange(for period: CodexTokenUsagePeriod, now: Date) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: 1 - period.dayCount, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return DateInterval(start: start, end: end)
    }

    private func fillMissingDays(
        in dayRange: DateInterval,
        from buckets: [CodexDailyTokenUsage]
    ) -> [CodexDailyTokenUsage] {
        var usageByDay = Dictionary(uniqueKeysWithValues: buckets.map { ($0.day, $0.usage) })
        var days: [CodexDailyTokenUsage] = []
        var day = dayRange.start

        while day < dayRange.end {
            days.append(CodexDailyTokenUsage(day: day, usage: usageByDay.removeValue(forKey: day) ?? .zero))
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            day = nextDay
        }

        return days
    }
}

private struct CodexSessionTokenUsageFileCandidate: Equatable {
    let url: URL
    let day: Date
}

private protocol CodexSessionTokenUsageFileDiscovering: Sendable {
    func sessionFiles(in directory: URL) throws -> [CodexSessionTokenUsageFileCandidate]
}

private struct CodexSessionTokenUsageFileDiscoverer: CodexSessionTokenUsageFileDiscovering, @unchecked Sendable {
    private let fileManager: FileManager
    private let calendar: Calendar

    init(fileManager: FileManager, calendar: Calendar) {
        self.fileManager = fileManager
        self.calendar = calendar
    }

    func sessionFiles(in directory: URL) throws -> [CodexSessionTokenUsageFileCandidate] {
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
                try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
                let day = sessionDay(for: url, under: directory)
            else {
                return nil
            }
            return CodexSessionTokenUsageFileCandidate(url: url, day: day)
        }
        .sorted { lhs, rhs in
            if lhs.day != rhs.day {
                return lhs.day > rhs.day
            }
            return lhs.url.path > rhs.url.path
        }
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
}

private protocol CodexSessionTokenUsageFileParsing: Sendable {
    func scanFile(_ url: URL, day: Date) throws -> CodexSessionTokenUsageScanResult
}

private struct CodexSessionTokenUsageFileParser: CodexSessionTokenUsageFileParsing {
    private static let chunkByteCount = 64 * 1024
    private static let throttleChunkInterval = 1
    private static let throttleSleepInterval: TimeInterval = 0.025
    private static let tokenCountNeedle = Data(#""token_count""#.utf8)

    private let maximumLineByteCount: Int

    init(maximumLineByteCount: Int) {
        self.maximumLineByteCount = maximumLineByteCount
    }

    func scanFile(_ url: URL, day: Date) throws -> CodexSessionTokenUsageScanResult {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return CodexSessionTokenUsageScanResult(buckets: [], summary: .empty)
        }
        defer { try? handle.close() }

        var summary = CodexSessionTokenUsageScanSummary.empty
        var accumulator = BucketAccumulator()
        var highestTotalUsage: CodexTokenUsageTotals?

        var buffer = Data()
        var discardingOversizedLine = false
        var chunkCount = 0
        while true {
            try Task.checkCancellation()
            let chunk = handle.readData(ofLength: Self.chunkByteCount)
            guard !chunk.isEmpty else { break }
            chunkCount += 1
            buffer.append(chunk)

            var lineStartIndex = buffer.startIndex
            while let newlineIndex = buffer[lineStartIndex...].firstIndex(of: 0x0A) {
                let line = buffer[lineStartIndex..<newlineIndex]
                if discardingOversizedLine {
                    discardingOversizedLine = false
                } else if line.count <= maximumLineByteCount {
                    processLine(
                        line,
                        day: day,
                        summary: &summary,
                        accumulator: &accumulator,
                        highestTotalUsage: &highestTotalUsage
                    )
                } else {
                    summary.malformedRowsIgnored += 1
                }
                lineStartIndex = buffer.index(after: newlineIndex)
            }
            if lineStartIndex > buffer.startIndex {
                buffer.removeSubrange(..<lineStartIndex)
            }

            if buffer.count > maximumLineByteCount {
                buffer.removeAll()
                discardingOversizedLine = true
                summary.malformedRowsIgnored += 1
            }

            if chunkCount.isMultiple(of: Self.throttleChunkInterval) {
                Thread.sleep(forTimeInterval: Self.throttleSleepInterval)
            }
        }
        if !buffer.isEmpty, !discardingOversizedLine {
            processLine(
                buffer,
                day: day,
                summary: &summary,
                accumulator: &accumulator,
                highestTotalUsage: &highestTotalUsage
            )
        }

        return CodexSessionTokenUsageScanResult(
            buckets: accumulator.buckets(),
            summary: summary
        )
    }

    private func processLine(
        _ lineData: Data.SubSequence,
        day: Date,
        summary: inout CodexSessionTokenUsageScanSummary,
        accumulator: inout BucketAccumulator,
        highestTotalUsage: inout CodexTokenUsageTotals?
    ) {
        autoreleasepool {
            processLineWithAutoreleaseBoundary(
                lineData,
                day: day,
                summary: &summary,
                accumulator: &accumulator,
                highestTotalUsage: &highestTotalUsage
            )
        }
    }

    private func processLineWithAutoreleaseBoundary(
        _ lineData: Data.SubSequence,
        day: Date,
        summary: inout CodexSessionTokenUsageScanSummary,
        accumulator: inout BucketAccumulator,
        highestTotalUsage: inout CodexTokenUsageTotals?
    ) {
        guard !lineData.isEmpty else { return }
        guard lineData.range(of: Self.tokenCountNeedle) != nil else {
            summary.nonUsageRowsIgnored += 1
            return
        }
        let line = String(decoding: lineData, as: UTF8.self)
        guard containsStringValue("token_count", forKey: "type", in: line) else {
            summary.nonUsageRowsIgnored += 1
            return
        }

        summary.tokenCountRowsRead += 1
        if let usage = usagePayload(named: "last_token_usage", in: line), usage.hasPositiveTotal {
            accumulator.add(usage, day: day)
        } else if let totalUsage = usagePayload(named: "total_token_usage", in: line) {
            let delta = highestTotalUsage.map { totalUsage - $0 } ?? totalUsage
            if delta.hasPositiveTotal {
                accumulator.add(safeCumulativeDelta(delta), day: day)
                summary.cumulativeRowsUsed += 1
                highestTotalUsage = totalUsage
            } else {
                summary.cumulativeRowsIgnored += 1
            }
        }
    }

    private func usagePayload(named name: String, in line: String) -> CodexTokenUsageTotals? {
        guard let payload = objectPayload(named: name, in: line) else {
            return nil
        }
        return CodexTokenUsageTotals(
            inputTokens: intValue(for: "input_tokens", in: payload),
            cachedInputTokens: intValue(for: "cached_input_tokens", in: payload),
            outputTokens: intValue(for: "output_tokens", in: payload),
            reasoningOutputTokens: intValue(for: "reasoning_output_tokens", in: payload),
            totalTokens: intValue(for: "total_tokens", in: payload)
        )
    }

    private func objectPayload(named name: String, in line: String) -> Substring? {
        guard let markerRange = line.range(of: #""\#(name)""#),
              let colonIndex = line[markerRange.upperBound...].firstIndex(of: ":")
        else {
            return nil
        }

        var index = line.index(after: colonIndex)
        while index < line.endIndex, line[index].isWhitespace {
            index = line.index(after: index)
        }
        guard index < line.endIndex, line[index] == "{" else {
            return nil
        }

        let objectStart = index
        var depth = 0
        var isInsideString = false
        var isEscaped = false

        while index < line.endIndex {
            let character = line[index]
            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = isInsideString
            } else if character == "\"" {
                isInsideString.toggle()
            } else if !isInsideString {
                if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return line[objectStart...index]
                    }
                }
            }
            index = line.index(after: index)
        }

        return nil
    }

    private func intValue(for key: String, in text: Substring) -> Int {
        guard let keyRange = text.range(of: #""\#(key)""#),
              let colonIndex = text[keyRange.upperBound...].firstIndex(of: ":")
        else {
            return 0
        }

        var index = text.index(after: colonIndex)
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }

        var endIndex = index
        while endIndex < text.endIndex, text[endIndex].isNumber {
            endIndex = text.index(after: endIndex)
        }

        guard index < endIndex else {
            return 0
        }
        return Int(text[index..<endIndex]) ?? 0
    }

    private func containsStringValue(_ expectedValue: String, forKey key: String, in line: String) -> Bool {
        var searchStart = line.startIndex
        while let keyRange = line[searchStart...].range(of: #""\#(key)""#) {
            var index = keyRange.upperBound
            while index < line.endIndex, line[index].isWhitespace {
                index = line.index(after: index)
            }
            guard index < line.endIndex, line[index] == ":" else {
                searchStart = keyRange.upperBound
                continue
            }
            index = line.index(after: index)
            while index < line.endIndex, line[index].isWhitespace {
                index = line.index(after: index)
            }
            guard index < line.endIndex, line[index] == "\"" else {
                searchStart = keyRange.upperBound
                continue
            }
            index = line.index(after: index)
            let valueStart = index
            while index < line.endIndex, line[index] != "\"" {
                index = line.index(after: index)
            }
            if String(line[valueStart..<index]) == expectedValue {
                return true
            }
            searchStart = keyRange.upperBound
        }
        return false
    }

    private func safeCumulativeDelta(_ delta: CodexTokenUsageTotals) -> CodexTokenUsageTotals {
        guard !delta.hasNegativeComponent else {
            return delta.preservingOnlyTotalTokens()
        }
        return delta
    }
}

private struct BucketAccumulator {
    private var usageByDay: [Date: CodexTokenUsageTotals] = [:]

    mutating func add(_ usage: CodexTokenUsageTotals, day: Date) {
        usageByDay[day, default: .zero] = usageByDay[day, default: .zero] + usage
    }

    mutating func merge(_ buckets: [CodexDailyTokenUsage]) {
        for bucket in buckets {
            usageByDay[bucket.day, default: .zero] = usageByDay[bucket.day, default: .zero] + bucket.usage
        }
    }

    func buckets() -> [CodexDailyTokenUsage] {
        usageByDay.keys.sorted().map { day in
            CodexDailyTokenUsage(
                day: day,
                usage: usageByDay[day, default: .zero]
            )
        }
    }
}

private extension CodexSessionTokenUsageScanSummary {
    static var empty: CodexSessionTokenUsageScanSummary {
        CodexSessionTokenUsageScanSummary(
            filesRead: 0,
            tokenCountRowsRead: 0,
            cumulativeRowsUsed: 0,
            cumulativeRowsIgnored: 0,
            malformedRowsIgnored: 0,
            nonUsageRowsIgnored: 0
        )
    }

    mutating func merge(_ summary: CodexSessionTokenUsageScanSummary) {
        tokenCountRowsRead += summary.tokenCountRowsRead
        cumulativeRowsUsed += summary.cumulativeRowsUsed
        cumulativeRowsIgnored += summary.cumulativeRowsIgnored
        malformedRowsIgnored += summary.malformedRowsIgnored
        nonUsageRowsIgnored += summary.nonUsageRowsIgnored
    }
}
