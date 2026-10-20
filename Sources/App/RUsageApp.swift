import SwiftUI

@main
struct RUsageApp: App {
    @NSApplicationDelegateAdaptor(RUsageAppDelegate.self) private var appDelegate

    var body: some Scene { Settings {} }
}
