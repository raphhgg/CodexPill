import Foundation

/// Isolated runs read a usage-summary fixture from disk instead of calling cursor.com.
/// A missing file reads as a network failure.
struct ValidationCursorUsageWebClient: CursorUsageWebClient {
    static let fileName = "cursor-usage-summary.json"

    let fileURL: URL

    func usageSummary(using _: CursorAccessToken) async throws -> Data {
        guard let data = try? Data(contentsOf: fileURL) else {
            throw CursorUsageWebError.transport
        }
        return data
    }
}
