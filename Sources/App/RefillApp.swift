import SwiftUI

@main
struct RefillApp: App {
    @NSApplicationDelegateAdaptor(RefillAppDelegate.self) private var appDelegate

    var body: some Scene { Settings {} }
}
