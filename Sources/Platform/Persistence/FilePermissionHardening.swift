import Foundation

enum FilePermissionHardening {
    static let privateDirectoryPermissions = 0o700
    static let privateFilePermissions = 0o600

    static func createPrivateDirectory(
        at url: URL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: privateDirectoryPermissions]
        )
        try repairPrivateDirectory(at: url, fileManager: fileManager)
    }

    static func repairPrivateDirectory(
        at url: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.setAttributes(
            [.posixPermissions: privateDirectoryPermissions],
            ofItemAtPath: url.path
        )
    }

    static func repairPrivateFile(
        at url: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.setAttributes(
            [.posixPermissions: privateFilePermissions],
            ofItemAtPath: url.path
        )
    }
}
