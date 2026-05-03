import Foundation

@MainActor
final class CodexPillSealProofRecorder {
    let account: AccountValidationRecorder?
    let host: HostValidationRecorder?

    private let cancel: () -> Void

    init(accountRecorder: AccountSealProofRecorder) {
        self.account = accountRecorder
        self.host = nil
        self.cancel = { accountRecorder.cancelIfUnfinished() }
    }

    init(hostRecorder: HostSealProofRecorder) {
        self.account = nil
        self.host = hostRecorder
        self.cancel = { hostRecorder.cancelIfUnfinished() }
    }

    func cancelIfUnfinished() {
        cancel()
    }
}
