import Foundation

struct CodexCLICommand: Equatable {
    let executableURL: URL
    let arguments: [String]
}

struct CodexAppServerConfiguration: Equatable {
    var command: CodexCLICommand
    var environment: [String: String]?
    var responseTimeout: Duration
    var clientInfo: CodexAppServerClientInfo

    init(
        command: CodexCLICommand,
        environment: [String: String]?,
        responseTimeout: Duration = .seconds(10),
        clientInfo: CodexAppServerClientInfo = .codexPill
    ) {
        self.command = command
        self.environment = environment
        self.responseTimeout = responseTimeout
        self.clientInfo = clientInfo
    }

    static func live(environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
        CodexAppServerConfiguration(
            command: makeAppServerCommand(environment: environment),
            environment: environment,
            responseTimeout: .seconds(10),
            clientInfo: .codexPill
        )
    }

    static func makeAppServerCommand(environment: [String: String]) -> CodexCLICommand {
        if let overridePath = environment["CODEX_CLI_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !overridePath.isEmpty {
            return CodexCLICommand(
                executableURL: URL(fileURLWithPath: overridePath),
                arguments: ["app-server"]
            )
        }

        let bundlePath = Bundle.main.sharedSupportPath.map {
            URL(fileURLWithPath: $0)
                .appendingPathComponent("codex")
                .standardizedFileURL.path
        }
        let fallbackPaths = [
            bundlePath,
            "/Applications/Codex.app/Contents/Resources/codex"
        ].compactMap { $0 }

        let fileManager = FileManager.default
        if let resolvedPath = fallbackPaths.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return CodexCLICommand(
                executableURL: URL(fileURLWithPath: resolvedPath),
                arguments: ["app-server"]
            )
        }

        return CodexCLICommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["codex", "app-server"]
        )
    }
}

struct CodexAppServerClientInfo: Equatable {
    var name: String
    var title: String
    var version: String

    static let codexPill = CodexAppServerClientInfo(
        name: "codexpill",
        title: "CodexPill",
        version: "0.1.0"
    )
}
