import Foundation

extension Timer {
    /// `scheduledTimer` only fires in the default run loop mode, so it pauses while a menu is open.
    /// This one also fires while the user is tracking a menu.
    @MainActor
    static func repeatingInCommonModes(interval: TimeInterval, block: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { block() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
