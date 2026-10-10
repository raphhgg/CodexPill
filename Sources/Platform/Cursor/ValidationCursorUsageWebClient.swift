import Foundation

/// Isolated runs read usage-summary and usage-events fixtures from disk instead of calling cursor.com.
/// A missing file reads as a network failure. The events fixture is returned for page 1 only.
struct ValidationCursorUsageWebClient: CursorUsageWebClient {
    static let fileName = "cursor-usage-summary.json"
    static let eventsFileName = "cursor-usage-events.json"

    let fileURL: URL

    func usageSummary(using _: CursorAccessToken) async throws -> Data {
        guard let data = try? Data(contentsOf: fileURL) else {
            throw CursorUsageWebError.transport
        }
        return data
    }

    func usageEvents(using _: CursorAccessToken, from _: Date, to _: Date, page: Int, pageSize _: Int) async throws -> Data {
        guard page == 1 else { return Data("{}".utf8) }
        let eventsURL = fileURL.deletingLastPathComponent().appendingPathComponent(Self.eventsFileName)
        guard let data = try? Data(contentsOf: eventsURL) else {
            throw CursorUsageWebError.transport
        }
        return data
    }
}
