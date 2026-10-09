import Foundation

@testable import CodexPill

struct PassthroughIdentityReconciler: StoredAccountIdentityReconciler {
    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts
    }
}
