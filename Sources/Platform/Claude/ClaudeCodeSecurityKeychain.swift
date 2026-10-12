import Foundation

/// Runs `/usr/bin/security`. Secrets come back through stdout, never through arguments.
protocol SecurityCommandRunning: Sendable {
    func run(_ arguments: [String], timeout: Duration) -> SecurityCommandResult
}

enum SecurityCommandResult: Equatable, Sendable {
    case exited(status: Int32, output: Data)
    case timedOut
    case launchFailed
}

/// Claude Code's Keychain item, read through `/usr/bin/security` as Claude Code does. Claude Code creates it with
/// `security`, so only `security` is on its access list: a direct Keychain read from Refill shows a prompt, even with
/// authentication UI set to skip, while `security` reads it without one. Refill never writes or deletes it.
struct ClaudeCodeSecurityKeychain: Sendable {
    static let readTimeout: Duration = .seconds(10)
    /// Long enough for the user to answer a Keychain prompt after a click.
    static let promptTimeout: Duration = .seconds(2 * 60)

    /// `security` exits with the low byte of the `OSStatus`.
    private static let itemNotFound: Int32 = 44 // errSecItemNotFound
    private static let accessRefused: Set<Int32> = [
        36, // errSecInteractionNotAllowed, such as a locked Keychain
        51, // errSecAuthFailed
        128, // errSecUserCanceled
    ]

    var runner: any SecurityCommandRunning = SystemSecurityCommandRunner()
    var account = NSUserName()

    /// `security` can't be told to skip its prompt. It shows none for an item it created, which is every item Claude
    /// Code writes, so `allowingPrompt` only gives the user time to answer one. A read that runs out of time reads as
    /// access needed, because `security` was most likely waiting on a prompt.
    func read(service: String, allowingPrompt: Bool) -> ClaudeKeychainRead {
        let result = runner.run(
            ["find-generic-password", "-a", account, "-s", service, "-w"],
            timeout: allowingPrompt ? Self.promptTimeout : Self.readTimeout
        )
        switch result {
        case let .exited(0, output):
            return Self.password(fromOutput: output).map(ClaudeKeychainRead.found) ?? .failed
        case .exited(Self.itemNotFound, _):
            return .notFound
        case let .exited(status, _) where Self.accessRefused.contains(status):
            return .needsPermission
        case .timedOut:
            return .needsPermission
        case .exited, .launchFailed:
            return .failed
        }
    }

    /// `security -w` prints the password followed by a newline, or as hex when it is not plain text.
    static func password(fromOutput output: Data) -> Data? {
        let trimmed = output.last == UInt8(ascii: "\n") ? output.dropLast() : output[...]
        guard !trimmed.isEmpty else { return nil }
        return Data(hex: trimmed) ?? Data(trimmed)
    }
}

struct SystemSecurityCommandRunner: SecurityCommandRunning {
    var executable = URL(fileURLWithPath: "/usr/bin/security")

    func run(_ arguments: [String], timeout: Duration) -> SecurityCommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let stdout = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return .launchFailed
        }

        // Read while it runs, so a full pipe can't stall it.
        let output = OutputCollector()
        let reader = stdout.fileHandleForReading
        let reading = DispatchGroup()
        reading.enter()
        DispatchQueue.global().async {
            output.data = reader.readDataToEndOfFile()
            reading.leave()
        }

        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        guard exited.wait(timeout: .now() + seconds) == .success else {
            process.terminate()
            exited.wait()
            return .timedOut
        }
        reading.wait()
        return .exited(status: process.terminationStatus, output: output.data)
    }
}

private final class OutputCollector: @unchecked Sendable {
    var data = Data()
}

private extension Data {
    /// Nil unless `hex` is an even number of lowercase or uppercase hex digits.
    init?(hex: some Collection<UInt8>) {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        var high: UInt8?
        for character in hex {
            guard let nibble = Self.nibble(character) else { return nil }
            if let pending = high {
                bytes.append(pending << 4 | nibble)
                high = nil
            } else {
                high = nibble
            }
        }
        self.init(bytes)
    }

    private static func nibble(_ character: UInt8) -> UInt8? {
        switch character {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): character - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): character - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): character - UInt8(ascii: "A") + 10
        default: nil
        }
    }
}
