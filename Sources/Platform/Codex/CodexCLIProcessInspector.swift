import Darwin
import Foundation

struct CodexCLIProcessInspector {
    func runningCLISessionCount() -> Int {
        Set(runningCLIProcesses().map(\.sessionKey)).count
    }

    func runningCLIProcesses() -> [CodexCLIProcess] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,tty=,comm=,args="]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return [] }

        let output = String(decoding: data, as: UTF8.self)

        return output
            .split(whereSeparator: \.isNewline)
            .compactMap(parseProcess)
    }

    func terminate(processes: [CodexCLIProcess]) {
        let uniqueProcesses = Array(Set(processes)).sorted { lhs, rhs in
            if lhs.ppid == rhs.pid { return true }
            if rhs.ppid == lhs.pid { return false }
            return lhs.pid > rhs.pid
        }

        uniqueProcesses.forEach { process in
            kill(process.pid, SIGTERM)
        }

        Thread.sleep(forTimeInterval: 0.35)

        uniqueProcesses
            .filter(\.isRunning)
            .forEach { process in
                kill(process.pid, SIGKILL)
            }
    }

    private func parseProcess(_ line: Substring) -> CodexCLIProcess? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let components = trimmed.split(maxSplits: 4, whereSeparator: \.isWhitespace)
        guard components.count >= 4,
              let pid = Int32(components[0]),
              let ppid = Int32(components[1])
        else {
            return nil
        }

        let tty = String(components[2])
        let command = String(components[3])
        let args = components.count > 4 ? String(components[4]) : ""

        guard isCodexCLIProcess(command: command, args: args) else { return nil }

        return CodexCLIProcess(
            pid: pid,
            ppid: ppid,
            tty: tty,
            command: command,
            arguments: args
        )
    }

    private func isCodexCLIProcess(command: String, args: String) -> Bool {
        if args.contains(" app-server") || args.hasSuffix("app-server") {
            return false
        }

        let commandName = URL(fileURLWithPath: command).lastPathComponent
        if commandName == "codex" {
            return true
        }

        if commandName == "node" && args.contains("/bin/codex") {
            return true
        }

        return false
    }
}

struct CodexCLIProcess: Hashable {
    let pid: Int32
    let ppid: Int32
    let tty: String
    let command: String
    let arguments: String

    var sessionKey: String {
        tty == "??" ? "pid:\(pid)" : "tty:\(tty)"
    }

    var isRunning: Bool {
        kill(pid, 0) == 0
    }
}
