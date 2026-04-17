import Foundation

@Observable
final class AccountOperationState {
    private(set) var pendingErrorMessage: String?
    private(set) var statusMessage = "Ready"
    private(set) var isBusy = false

    func begin(status: String) {
        isBusy = true
        statusMessage = status
    }

    func setIdleStatus(_ status: String) {
        statusMessage = status
        isBusy = false
    }

    func succeed() {
        statusMessage = "Done"
        isBusy = false
    }

    func fail(_ error: Error) {
        statusMessage = "Ready"
        pendingErrorMessage = error.localizedDescription
        isBusy = false
    }
    func consumePendingErrorMessage() -> String? {
        let message = pendingErrorMessage
        pendingErrorMessage = nil
        return message
    }
}
