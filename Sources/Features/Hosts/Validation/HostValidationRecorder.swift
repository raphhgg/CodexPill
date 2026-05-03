import Foundation

@MainActor
protocol HostValidationRecorder {
    func recordAddHostMenuAction()
    func recordAddHostSetupPresented()
    func recordAddHostValidationStarted(hostName: String)
    func recordAddHostValidationFailed(hostName: String, message: String)
    func recordRemoteHostSwitchMenuAction(targetName: String, hostName: String)
    func recordRemoteHostSwitchStarted(targetName: String, hostName: String)
    func recordRemoteHostActiveAccountChanged(targetName: String, hostName: String)
}
