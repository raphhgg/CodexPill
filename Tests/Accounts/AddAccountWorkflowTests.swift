import Foundation
import Testing

@testable import CodexPill

struct AddAccountWorkflowTests {
    @Test
    func beginStartsIsolatedDeviceAuthAndReturnsResolvedName() async throws {
        let capture = DeviceAuthCaptureSpy(
            prompt: CodexDeviceAuthPrompt(
                verificationURL: URL(string: "https://auth.openai.com/codex/device")!,
                userCode: "ABCD-1234"
            ),
            capturedAuth: Data()
        )
        let captureClient = DeviceAuthCaptureClientSpy(capture: capture)
        let appController = AppControllerSpy()
        let workflow = AddAccountWorkflow(
            authService: SnapshotImportSpy(savedAccount: makeAccount(name: "ignored", fingerprint: "fingerprint")),
            appController: appController,
            captureClient: captureClient,
            repository: RepositorySpy()
        )

        let started = try await workflow.begin(named: "  Business 2  ")

        #expect(appController.availabilityCheckCount == 1)
        #expect(started.accountName == "Business 2")
        #expect(captureClient.startedSessions.count == 1)
    }

    @Test
    func completeAddAccountPersistsCapturedAccountWithoutChangingActiveAccount() async throws {
        let capturedAuth = authData(
            accountID: "business-2",
            email: "person@example.com",
            planType: "team"
        )
        let capture = DeviceAuthCaptureSpy(
            prompt: CodexDeviceAuthPrompt(
                verificationURL: URL(string: "https://auth.openai.com/codex/device")!,
                userCode: "ABCD-1234"
            ),
            capturedAuth: capturedAuth
        )
        let repository = RepositorySpy()
        let authService = SnapshotImportSpy(savedAccount: makeAccount(name: "ignored", fingerprint: "old"))
        let workflow = AddAccountWorkflow(
            authService: authService,
            appController: AppControllerSpy(),
            captureClient: DeviceAuthCaptureClientSpy(capture: capture),
            repository: repository
        )

        let result = try await workflow.complete(
            startedSession: AddAccountStartedSession(
                accountName: "Business 2",
                capture: capture
            ),
            existingAccounts: [],
            previousActiveAccountID: UUID()
        )

        #expect(authService.savedNames == ["Business 2"])
        #expect(authService.savedAuthData == capturedAuth)
        #expect(repository.savedAccounts?.count == 1)
        #expect(result.savedAccount.email == "person@example.com")
        #expect(result.savedAccount.planType == "team")
        #expect(result.activeAccountID != result.savedAccount.id)
        #expect(capture.cancelCount == 1)
        #expect(capture.cleanupCount == 1)
    }

    @Test
    func completeAddAccountUpdatesMatchedExistingAccountInsteadOfAppendingDuplicate() async throws {
        let existing = makeAccount(
            name: "Business 2",
            fingerprint: "old-fingerprint",
            stableAccountID: "business-2",
            subject: "auth0|business-2",
            chatGPTUserID: "user-business-2",
            workspaceAccountID: "org-business-2"
        )
        let capturedAuth = authData(
            accountID: "business-2",
            email: "business@example.com",
            planType: "team",
            subject: "auth0|business-2",
            chatGPTUserID: "user-business-2",
            workspaceAccountID: "org-business-2"
        )
        let capture = DeviceAuthCaptureSpy(
            prompt: CodexDeviceAuthPrompt(
                verificationURL: URL(string: "https://auth.openai.com/codex/device")!,
                userCode: nil
            ),
            capturedAuth: capturedAuth
        )
        let authService = SnapshotImportSpy(
            savedAccount: makeAccount(
                id: existing.id,
                name: "ignored",
                fingerprint: "fresh-fingerprint",
                stableAccountID: "business-2",
                subject: "auth0|business-2",
                chatGPTUserID: "user-business-2",
                workspaceAccountID: "org-business-2"
            )
        )
        let repository = RepositorySpy()
        let workflow = AddAccountWorkflow(
            authService: authService,
            appController: AppControllerSpy(),
            captureClient: DeviceAuthCaptureClientSpy(capture: capture),
            repository: repository
        )

        let result = try await workflow.complete(
            startedSession: AddAccountStartedSession(
                accountName: "Business 2",
                capture: capture
            ),
            existingAccounts: [existing],
            previousActiveAccountID: nil
        )

        #expect(authService.savedExistingAccountIDs == [existing.id])
        #expect(repository.savedAccounts?.count == 1)
        #expect(repository.savedAccounts?.first?.id == existing.id)
        #expect(result.savedAccount.id == existing.id)
    }

    @Test
    func completeAddAccountRejectsDuplicateNameForDifferentAccount() async {
        let existing = makeAccount(name: "Business 2", fingerprint: "existing")
        let other = makeAccount(name: "Other", fingerprint: "other")
        let capture = DeviceAuthCaptureSpy(
            prompt: CodexDeviceAuthPrompt(
                verificationURL: URL(string: "https://auth.openai.com/codex/device")!,
                userCode: nil
            ),
            capturedAuth: authData(
                accountID: "other",
                email: "other@example.com",
                planType: "plus"
            )
        )
        let workflow = AddAccountWorkflow(
            authService: SnapshotImportSpy(savedAccount: other),
            appController: AppControllerSpy(),
            captureClient: DeviceAuthCaptureClientSpy(capture: capture),
            repository: RepositorySpy()
        )

        await #expect(throws: SaveCurrentAccountWorkflowError.duplicateAccountName) {
            _ = try await workflow.complete(
                startedSession: AddAccountStartedSession(
                    accountName: "Business 2",
                    capture: capture
                ),
                existingAccounts: [existing],
                previousActiveAccountID: nil
            )
        }
    }

    private func makeAccount(
        id: UUID = UUID(),
        name: String,
        fingerprint: String,
        stableAccountID: String? = nil,
        subject: String? = nil,
        chatGPTUserID: String? = nil,
        workspaceAccountID: String? = nil
    ) -> CodexAccount {
        CodexAccount(
            id: id,
            name: name,
            snapshotFileName: "\(id.uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: nil,
            planType: nil,
            rateLimits: nil,
            identity: CodexAccountIdentity(
                stableAccountID: stableAccountID,
                authPrincipalIdentity: CodexAuthPrincipalIdentity(
                    subject: subject,
                    chatGPTUserID: chatGPTUserID
                ),
                workspaceIdentity: CodexWorkspaceIdentity(
                    workspaceAccountID: workspaceAccountID,
                    workspaceLabel: nil
                ),
                snapshotFingerprint: fingerprint,
                remoteIdentity: nil
            )
        )
    }

    private func authData(
        accountID: String,
        email: String,
        planType: String,
        subject: String? = nil,
        chatGPTUserID: String? = nil,
        workspaceAccountID: String? = nil
    ) -> Data {
        let payload: [String: Any] = [
            "email": email,
            "sub": subject ?? "auth0|\(accountID)",
            "https://api.openai.com/auth": [
                "chatgpt_plan_type": planType,
                "chatgpt_user_id": chatGPTUserID ?? "user-\(accountID)",
                "organizations": [
                    ["id": workspaceAccountID ?? "org-\(accountID)", "title": "Workspace", "is_default": true]
                ]
            ]
        ]
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)
        let payloadBase64 = payloadData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let idToken = "header.\(payloadBase64).signature"
        let object: [String: Any] = [
            "tokens": [
                "account_id": accountID,
                "id_token": idToken
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: object)
    }
}

private final class SnapshotImportSpy: CodexAuthSnapshotImporting {
    let savedAccount: CodexAccount
    private(set) var savedNames: [String] = []
    private(set) var savedExistingAccountIDs: [UUID?] = []
    private(set) var savedAuthData: Data?

    init(savedAccount: CodexAccount) {
        self.savedAccount = savedAccount
    }

    func saveAuthSnapshot(_ authData: Data, named name: String, existing: CodexAccount?) throws -> CodexAccount {
        savedNames.append(name)
        savedExistingAccountIDs.append(existing?.id)
        savedAuthData = authData
        var account = existing ?? savedAccount
        account.name = existing?.name ?? name
        account.email = CodexAuthDataParser.email(from: authData)
        account.planType = CodexAuthDataParser.planType(from: authData)
        return account
    }
}

private final class DeviceAuthCaptureClientSpy: CodexDeviceAuthCapturing {
    let capture: any CodexDeviceAuthCaptureHandling
    private(set) var startedSessions: [IsolatedCodexHomeSession] = []

    init(capture: any CodexDeviceAuthCaptureHandling) {
        self.capture = capture
    }

    func beginDeviceAuth(in session: IsolatedCodexHomeSession) async throws -> any CodexDeviceAuthCaptureHandling {
        startedSessions.append(session)
        return capture
    }
}

private final class DeviceAuthCaptureSpy: CodexDeviceAuthCaptureHandling {
    let prompt: CodexDeviceAuthPrompt
    let capturedAuth: Data
    private(set) var cancelCount = 0
    private(set) var cleanupCount = 0

    init(prompt: CodexDeviceAuthPrompt, capturedAuth: Data) {
        self.prompt = prompt
        self.capturedAuth = capturedAuth
    }

    func deviceAuthPrompt() async -> CodexDeviceAuthPrompt {
        prompt
    }

    func waitForCapturedAuth() async throws -> Data {
        capturedAuth
    }

    func cancel() async {
        cancelCount += 1
    }

    func cleanup() async throws {
        cleanupCount += 1
    }
}

private final class AppControllerSpy: CodexAppRelaunching {
    var relaunchCount = 0
    var availabilityCheckCount = 0
    var availabilityError: Error?

    func assertCodexAvailable() throws {
        availabilityCheckCount += 1
        if let availabilityError {
            throw availabilityError
        }
    }

    func relaunchCodex() async throws {
        relaunchCount += 1
    }
}

private final class RepositorySpy: AccountCatalogPersisting {
    var savedAccounts: [CodexAccount]?

    func saveAccounts(_ accounts: [CodexAccount]) throws {
        savedAccounts = accounts
    }
}
