import Foundation

/// Short, readable names for the model IDs the tools write, for example `claude-opus-5-5` → `Opus 5.5`.
enum ModelDisplayName {
    static func make(_ id: String) -> String {
        let parts = id.lowercased().split(separator: "-").map(String.init)
        guard let first = parts.first else { return id }

        switch first {
        case "unknown":
            return "Other"
        case "claude":
            // Both `claude-opus-5-5` and `claude-4.5-sonnet` exist. A trailing date (`20250929`) is dropped.
            let rest = parts.dropFirst().filter { !($0.count == 8 && $0.allSatisfy(\.isNumber)) }
            let family = rest.first { $0.first?.isLetter == true }
            let version = rest.filter { $0.first?.isNumber == true }.joined(separator: ".")
            guard let family else { return id }
            return version.isEmpty ? family.capitalized : "\(family.capitalized) \(version)"
        case "gpt" where parts.count >= 2:
            return (["GPT-\(parts[1])"] + parts.dropFirst(2).map(\.capitalized)).joined(separator: " ")
        default:
            return parts.map { $0.first?.isLetter == true ? $0.capitalized : $0 }.joined(separator: " ")
        }
    }
}
