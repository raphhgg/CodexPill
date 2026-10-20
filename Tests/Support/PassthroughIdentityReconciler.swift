import Foundation

@testable import rusage

struct PassthroughIdentityReconciler: StoredAccountIdentityReconciler {
    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts
    }
}
