import Foundation

struct HostSealValidationSnapshot: Encodable {
    let hostName: String
    let validationResult: String
    let message: String
}

struct HostSealRefreshFailureSnapshot: Encodable {
    let hostName: String
    let fallbackAccountName: String
    let connectionState: String
    let activeAccountPresented: Bool
    let remoteActiveCardVisible: Bool
    let failureMessage: String?
}
