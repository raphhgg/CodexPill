import Foundation

struct RemoteHost: Codable, Equatable {
    let destination: String
    let displayName: String

    init(destination: String, displayName: String? = nil) {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.destination = trimmed
        self.displayName = (trimmedDisplayName?.isEmpty == false ? trimmedDisplayName : nil) ?? Self.defaultDisplayName(for: trimmed)
    }

    private static func defaultDisplayName(for destination: String) -> String {
        guard let hostComponent = destination.split(separator: "@").last else {
            return destination
        }
        return String(hostComponent)
    }
}
