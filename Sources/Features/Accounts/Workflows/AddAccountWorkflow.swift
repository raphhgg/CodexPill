import CryptoKit
import Foundation

protocol CodexAuthSnapshotImporting {
    func saveAuthSnapshot(
        _ authData: Data,
        named name: String,
        existing: CodexAccount?
    ) throws -> CodexAccount
}

extension CodexAuthSnapshotService: CodexAuthSnapshotImporting {}

struct AddAccountStartedSession {
    let accountName: String
    let capture: any CodexDeviceAuthCaptureHandling
}

struct AddAccountResult {
    let savedAccount: CodexAccount
    let activeAccountID: UUID?
}

struct AddAccountWorkflow {
    private let authService: CodexAuthSnapshotImporting
    private let appController: CodexAppRelaunching
    private let captureClient: any CodexDeviceAuthCapturing
    private let repository: AccountCatalogPersisting
    private let accountMatcher: CodexAccountMatcher

    init(
        authService: CodexAuthSnapshotImporting,
        appController: CodexAppRelaunching,
        captureClient: any CodexDeviceAuthCapturing = CodexLoginCaptureClient(),
        repository: AccountCatalogPersisting,
        accountMatcher: CodexAccountMatcher = CodexAccountMatcher()
    ) {
        self.authService = authService
        self.appController = appController
        self.captureClient = captureClient
        self.repository = repository
        self.accountMatcher = accountMatcher
    }

    func begin(named accountName: String?) async throws -> AddAccountStartedSession {
        let resolvedName = resolveAccountName(accountName, fallbackEmail: nil)
        try appController.assertCodexAvailable()
        let isolatedSession = try IsolatedCodexHomeSession.create()

        do {
            let capture = try await captureClient.beginDeviceAuth(in: isolatedSession)
            return AddAccountStartedSession(
                accountName: resolvedName,
                capture: capture
            )
        } catch {
            try? isolatedSession.cleanup()
            throw error
        }
    }

    func complete(
        startedSession: AddAccountStartedSession,
        existingAccounts: [CodexAccount],
        previousActiveAccountID: UUID?
    ) async throws -> AddAccountResult {
        let authData: Data
        do {
            authData = try await startedSession.capture.waitForCapturedAuth()
        } catch {
            await startedSession.capture.cancel()
            try? await startedSession.capture.cleanup()
            throw error
        }

        defer {
            Task {
                await startedSession.capture.cancel()
                try? await startedSession.capture.cleanup()
            }
        }

        let matchOutcome = accountMatcher.match(
            liveStableAccountID: CodexAuthDataParser.stableAccountID(from: authData),
            liveAuthPrincipalIdentity: CodexAuthDataParser.authPrincipalIdentity(from: authData),
            liveWorkspaceIdentity: CodexAuthDataParser.workspaceIdentity(from: authData),
            liveAuthFingerprint: snapshotFingerprint(for: authData),
            liveRemoteIdentity: CodexAuthDataParser.remoteIdentity(from: authData),
            accounts: existingAccounts
        )
        let matchedAccountID = matchOutcome.isSafeForOverwrite ? matchOutcome.matchedAccountID : nil
        let existing = matchedAccountID.flatMap { id in
            existingAccounts.first(where: { $0.id == id })
        }
        let resolvedName = existing?.name ?? resolveAccountName(
            startedSession.accountName,
            fallbackEmail: CodexAuthDataParser.email(from: authData)
        )

        guard !existingAccounts.contains(where: {
            $0.id != existing?.id &&
                $0.name.caseInsensitiveCompare(resolvedName) == .orderedSame
        }) else {
            throw SaveCurrentAccountWorkflowError.duplicateAccountName
        }

        let saved = try authService.saveAuthSnapshot(
            authData,
            named: resolvedName,
            existing: existing
        )

        var updatedAccounts = existingAccounts
        if let existingIndex = updatedAccounts.firstIndex(where: { $0.id == saved.id }) {
            updatedAccounts[existingIndex] = saved
        } else {
            updatedAccounts.append(saved)
        }
        updatedAccounts.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        try repository.saveAccounts(updatedAccounts)

        return AddAccountResult(
            savedAccount: saved,
            activeAccountID: previousActiveAccountID
        )
    }

    private func resolveAccountName(_ customName: String?, fallbackEmail: String?) -> String {
        let trimmedCustomName = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedCustomName.isEmpty {
            return trimmedCustomName
        }

        let trimmedEmail = fallbackEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedEmail.isEmpty {
            return trimmedEmail
        }

        return "Codex Account"
    }

    private func snapshotFingerprint(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
