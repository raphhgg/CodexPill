import AppKit
import Testing

@testable import rusage

struct AppIconColorTests {
    private let appBundle = Bundle(for: MenuBarCoordinator.self)

    @Test
    func cobaltKeepsTheBundleIcon() {
        #expect(AppIconColor.cobalt.overrideImage(in: appBundle) == nil)
    }

    @Test(arguments: [AppIconColor.lagoon, .emerald, .violet, .honey, .rose, .graphite])
    func alternateColorsLoadTheirBundledIcon(color: AppIconColor) throws {
        let image = try #require(color.overrideImage(in: appBundle))

        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }
}
