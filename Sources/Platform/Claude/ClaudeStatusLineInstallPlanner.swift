import Foundation

enum ClaudeStatusLinePlan: Equatable, Sendable {
    enum UnchangedReason: Equatable, Sendable {
        case alreadyInstalled
        case notInstalled
    }

    case unchanged(UnchangedReason)
    /// `settings` is the complete new `settings.json`; `previousCommand` is the
    /// user's own status line command that the relay wraps (install) or that is
    /// restored (uninstall).
    case write(settings: Data, previousCommand: String?)
}

enum ClaudeStatusLinePlanError: Error, Equatable, Sendable {
    case settingsNotJSON
    case settingsNotAnObject
    case statusLineNotAnObject
    case commandNotAString
}

/// Plans edits to Claude Code's `settings.json` so its status line runs the
/// CodexPill relay in front of the user's previous command. Output is
/// re-serialized with sorted keys, so key order may change on write.
enum ClaudeStatusLineInstallPlanner {
    static let relayFileName = "codexpill-claude-usage-relay.sh"

    static func planInstall(
        settings: Data?,
        relayPath: String
    ) throws(ClaudeStatusLinePlanError) -> ClaudeStatusLinePlan {
        var root = try parseSettings(settings)
        var statusLine = try statusLineObject(in: root) ?? [:]
        let existingCommand = try command(in: statusLine)

        let previousCommand: String?
        if let existingCommand, let installed = installedRelay(in: existingCommand) {
            previousCommand = installed.previousCommand
        } else {
            previousCommand = existingCommand
        }

        let newCommand = relayCommand(relayPath: relayPath, previousCommand: previousCommand)
        if newCommand == existingCommand, statusLine["type"] as? String == "command" {
            return .unchanged(.alreadyInstalled)
        }

        statusLine["type"] = "command"
        statusLine["command"] = newCommand
        root["statusLine"] = statusLine
        return .write(settings: try serialize(root), previousCommand: previousCommand)
    }

    static func planUninstall(settings: Data?) throws(ClaudeStatusLinePlanError) -> ClaudeStatusLinePlan {
        guard settings != nil else { return .unchanged(.notInstalled) }
        var root = try parseSettings(settings)
        guard var statusLine = try statusLineObject(in: root),
              let existingCommand = try command(in: statusLine),
              let installed = installedRelay(in: existingCommand) else {
            return .unchanged(.notInstalled)
        }

        if let previousCommand = installed.previousCommand {
            statusLine["command"] = previousCommand
            root["statusLine"] = statusLine
        } else {
            statusLine["command"] = nil
            statusLine["type"] = nil
            root["statusLine"] = statusLine.isEmpty ? nil : statusLine
        }
        return .write(settings: try serialize(root), previousCommand: installed.previousCommand)
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func relayCommand(relayPath: String, previousCommand: String?) -> String {
        guard let previousCommand else { return shellQuote(relayPath) }
        return shellQuote(relayPath) + " " + shellQuote(previousCommand)
    }

    private static func installedRelay(in command: String) -> (relayPath: String, previousCommand: String?)? {
        guard let words = unquoteWords(command),
              (1...2).contains(words.count),
              (words[0] as NSString).lastPathComponent == relayFileName else {
            return nil
        }
        return (words[0], words.count == 2 ? words[1] : nil)
    }

    /// Reverses `shellQuote` words joined by single spaces. Any other shell
    /// syntax returns nil, which callers treat as "not our command".
    private static func unquoteWords(_ command: String) -> [String]? {
        var words: [String] = []
        var current = ""
        var isInWord = false
        var index = command.startIndex

        while index < command.endIndex {
            switch command[index] {
            case "'":
                let contentStart = command.index(after: index)
                guard let close = command[contentStart...].firstIndex(of: "'") else { return nil }
                current += command[contentStart..<close]
                index = command.index(after: close)
                isInWord = true
            case "\\":
                let next = command.index(after: index)
                guard next < command.endIndex, command[next] == "'" else { return nil }
                current.append("'")
                index = command.index(after: next)
                isInWord = true
            case " ":
                guard isInWord else { return nil }
                words.append(current)
                current = ""
                isInWord = false
                index = command.index(after: index)
                guard index < command.endIndex else { return nil }
            default:
                return nil
            }
        }

        guard isInWord else { return nil }
        words.append(current)
        return words
    }

    private static func parseSettings(_ settings: Data?) throws(ClaudeStatusLinePlanError) -> [String: Any] {
        guard let settings else { return [:] }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: settings, options: [.fragmentsAllowed])
        } catch {
            throw .settingsNotJSON
        }
        guard let root = object as? [String: Any] else { throw .settingsNotAnObject }
        return root
    }

    private static func statusLineObject(in root: [String: Any]) throws(ClaudeStatusLinePlanError) -> [String: Any]? {
        guard let value = root["statusLine"] else { return nil }
        guard let statusLine = value as? [String: Any] else { throw .statusLineNotAnObject }
        return statusLine
    }

    private static func command(in statusLine: [String: Any]) throws(ClaudeStatusLinePlanError) -> String? {
        guard let value = statusLine["command"] else { return nil }
        guard let command = value as? String else { throw .commandNotAString }
        return command
    }

    private static func serialize(_ root: [String: Any]) throws(ClaudeStatusLinePlanError) -> Data {
        do {
            var data = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            data.append(0x0A)
            return data
        } catch {
            // Unreachable for objects that came from JSONSerialization.
            throw .settingsNotJSON
        }
    }
}
