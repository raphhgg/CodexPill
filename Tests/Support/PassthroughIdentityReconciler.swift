import Foundation

@testable import RUsage

struct PassthroughIdentityReconciler: StoredAccountIdentityReconciler {
    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts
    }
}
