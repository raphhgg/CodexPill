import Foundation

struct HostSealValidationSnapshot: Encodable {
    let hostName: String
    let validationResult: String
    let message: String
}
