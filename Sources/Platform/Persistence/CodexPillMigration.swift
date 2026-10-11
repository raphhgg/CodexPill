import Foundation
import OSLog
import Security

private let migrationLogger = Logger(subsystem: "com.raphhgg.refill", category: "CodexPillMigration")

/// What CodexPill left on this Mac before the app became Refill.
struct CodexPillLegacyData {
    let folder: URL
    let preferences: [String: Any]
    /// CodexPill's Keychain service names, each with the name Refill uses for the same items.
    static let keychainServices = [
        (old: "CodexPill Claude Code account", new: SystemClaudeCodeAccountItems.service),
        (old: "CodexPill Cursor accounts", new: SystemCursorAccountKeychain.service),
    ]
}

/// Copies CodexPill's saved accounts, settings and Keychain items to Refill once, at the first launch after the
/// rename. CodexPill's copies are never changed, so they stay as a backup. Refill data that already exists wins.
struct CodexPillMigration {
    enum Outcome: Equatable {
        case alreadyRan
        case nothingToCopy
        case keptRefillData
        case copied
        /// Something was not copied. Whatever did copy stays, and the migration does not run again.
        case failed
    }

    static let doneKey = "codexPillMigrationDone"
    /// Refill's own scratch folders and Finder's file: none of them make the Refill folder hold data.
    private static let ignoredEntries: Set<String> = [".DS_Store", "claude-sign-in", "cursor-sign-in"]

    let legacy: CodexPillLegacyData
    let folder: URL
    let defaults: UserDefaults
    let defaultsDomain: String
    let keychain: any GenericPasswordStore
    var fileManager: FileManager = .default

    func run() -> Outcome {
        guard !defaults.bool(forKey: Self.doneKey) else { return .alreadyRan }
        defer { defaults.set(true, forKey: Self.doneKey) }

        copyPreferences()
        guard fileManager.fileExists(atPath: legacy.folder.path) else { return .nothingToCopy }
        do {
            guard try !refillHasData() else {
                migrationLogger.log("Refill already has data, CodexPill's folder left as is")
                return .keptRefillData
            }
            try copyFolder()
        } catch {
            migrationLogger.error("Copying CodexPill's folder failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
        return copyKeychainItems() ? .copied : .failed
    }

    private func copyPreferences() {
        let current = defaults.persistentDomain(forName: defaultsDomain) ?? [:]
        for (key, value) in legacy.preferences where current[key] == nil {
            defaults.set(value, forKey: key)
        }
    }

    private func refillHasData() throws -> Bool {
        guard fileManager.fileExists(atPath: folder.path) else { return false }
        for entry in try entries(of: folder) {
            switch entry.lastPathComponent {
            case "accounts.json":
                let catalog = (try? Data(contentsOf: entry)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [Any]
                if catalog?.isEmpty != true { return true }
            case "snapshots":
                if try !entries(of: entry).isEmpty { return true }
            default:
                return true
            }
        }
        return false
    }

    private func entries(of directory: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { !Self.ignoredEntries.contains($0.lastPathComponent) }
    }

    /// Copies into a staging folder first, so a crash midway leaves either no Refill folder or the empty one, and the
    /// next launch copies again.
    private func copyFolder() throws {
        let staging = folder.deletingLastPathComponent()
            .appendingPathComponent(".\(folder.lastPathComponent)-from-CodexPill", isDirectory: true)
        if fileManager.fileExists(atPath: staging.path) {
            try fileManager.removeItem(at: staging)
        }
        try fileManager.copyItem(at: legacy.folder, to: staging)
        try makePrivate(staging)
        if fileManager.fileExists(atPath: folder.path) {
            try fileManager.removeItem(at: folder)
        }
        try fileManager.moveItem(at: staging, to: folder)
        migrationLogger.log("Copied CodexPill's folder to Refill")
    }

    /// Owner-only access throughout. Files keep their owner execute bit.
    private func makePrivate(_ root: URL) throws {
        try FilePermissionHardening.repairPrivateDirectory(at: root, fileManager: fileManager)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let walk = fileManager.enumerator(at: root, includingPropertiesForKeys: keys) else { return }
        for case let item as URL in walk {
            let values = try item.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true { continue }
            if values.isDirectory == true {
                try FilePermissionHardening.repairPrivateDirectory(at: item, fileManager: fileManager)
            } else {
                let mode = try fileManager.attributesOfItem(atPath: item.path)[.posixPermissions] as? Int ?? 0
                let permissions = FilePermissionHardening.privateFilePermissions | (mode & 0o100)
                try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: item.path)
            }
        }
    }

    /// Copies each CodexPill item Refill does not have yet. Reading CodexPill's items can show a Keychain prompt.
    private func copyKeychainItems() -> Bool {
        var copiedAll = true
        for services in CodexPillLegacyData.keychainServices {
            do {
                let existing = Set(try keychain.accounts(service: services.new))
                for account in try keychain.accounts(service: services.old) where !existing.contains(account) {
                    do {
                        try keychain.add(keychain.read(service: services.old, account: account), service: services.new, account: account)
                    } catch {
                        copiedAll = false
                        migrationLogger.error("Copying a \(services.old, privacy: .public) item failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            } catch {
                copiedAll = false
                migrationLogger.error("Listing \(services.old, privacy: .public) items failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return copiedAll
    }
}

extension CodexPillMigration {
    /// The real folders and the CodexPill defaults domain that matches this build: `com.raphhgg.refill.dev` reads
    /// `com.raphhgg.codexpill.dev`.
    static func live(defaults: UserDefaults, bundleIdentifier: String?, fileManager: FileManager = .default) throws -> CodexPillMigration {
        let supportRoot = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let domain = bundleIdentifier ?? ""
        let preferences = legacyDefaultsDomain(for: domain).flatMap(defaults.persistentDomain(forName:)) ?? [:]
        return CodexPillMigration(
            legacy: CodexPillLegacyData(
                folder: supportRoot.appendingPathComponent("CodexPill", isDirectory: true),
                preferences: preferences
            ),
            folder: supportRoot.appendingPathComponent(AppPaths.appSupportFolderName, isDirectory: true),
            defaults: defaults,
            defaultsDomain: domain,
            keychain: SystemGenericPasswordStore(),
            fileManager: fileManager
        )
    }

    static func legacyDefaultsDomain(for bundleIdentifier: String) -> String? {
        let prefix = "com.raphhgg.refill"
        guard bundleIdentifier == prefix || bundleIdentifier.hasPrefix(prefix + ".") else { return nil }
        return "com.raphhgg.codexpill" + bundleIdentifier.dropFirst(prefix.count)
    }
}

protocol GenericPasswordStore {
    func accounts(service: String) throws -> [String]
    func read(service: String, account: String) throws -> Data
    func add(_ data: Data, service: String, account: String) throws
}

struct KeychainStatusError: Error, Equatable {
    let status: OSStatus
}

struct SystemGenericPasswordStore: GenericPasswordStore {
    func accounts(service: String) throws -> [String] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnAttributes: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw KeychainStatusError(status: status) }
        return (result as? [[CFString: Any]] ?? []).compactMap { $0[kSecAttrAccount] as? String }
    }

    func read(service: String, account: String) throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainStatusError(status: status) }
        return data
    }

    func add(_ data: Data, service: String, account: String) throws {
        let item: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrLabel: service,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData: data,
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { throw KeychainStatusError(status: status) }
    }
}
