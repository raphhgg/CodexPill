import Foundation

@testable import CodexPill

struct RemoteHostStub: RemoteHostSwitchWorkflowOperations, RemoteHostAccountSigningOut {
    var status: CodexAccountStatus?
    var statusesByDestination: [String: CodexAccountStatus] = [:]
    var readError: Error?
    var readErrorsByDestination: [String: Error] = [:]
    var switchError: Error?

    func testConnection(to host: RemoteHost) async throws {}
    func installationState(for account: CodexAccount, on host: RemoteHost) async throws -> RemoteHostAccountInstallationState { .installed }
    func installAccount(_ account: CodexAccount, on host: RemoteHost) async throws {}
    func switchToAccount(_ account: CodexAccount, on host: RemoteHost) async throws {
        if let switchError {
            throw switchError
        }
    }
    func signOut(on host: RemoteHost) async throws {}
    func refreshCodexAppServer(on host: RemoteHost) async throws {}
    func readCurrentAccountStatus(on host: RemoteHost) async throws -> CodexAccountStatus {
        if let scopedError = readErrorsByDestination[host.destination] {
            throw scopedError
        }
        if let readError {
            throw readError
        }
        if let scopedStatus = statusesByDestination[host.destination] {
            return scopedStatus
        }
        if let status {
            return status
        }
        return CodexAccountStatus(email: nil, planType: nil, usage: nil)
    }
}
