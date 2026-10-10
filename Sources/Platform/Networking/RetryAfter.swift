import Foundation

enum RetryAfter {
    /// The wait an HTTP `Retry-After` header asks for, given as delay seconds or an HTTP date.
    /// Nil when the header is missing or unreadable. A date in the past means no wait.
    static func delay(_ header: String?, now: Date) -> TimeInterval? {
        guard let value = header?.trimmingCharacters(in: .whitespaces) else { return nil }
        if let seconds = Int(value) {
            return seconds >= 0 ? TimeInterval(seconds) : nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value).map { max($0.timeIntervalSince(now), 0) }
    }
}
