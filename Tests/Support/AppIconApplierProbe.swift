@testable import Refill

@MainActor
final class AppIconApplierProbe: AppIconApplying {
    private(set) var appliedColors: [AppIconColor] = []

    func apply(_ color: AppIconColor) {
        appliedColors.append(color)
    }
}
