import AppKit
import Testing

@testable import CodexPill

@MainActor
struct AppSettingsTests {
    @Test
    func progressAccentColorDefaultAndReset() {
        let defaults = makeDefaults()
        let settings = AppSettings(userDefaults: defaults)

        #expect(colorsEqual(settings.progressAccentColor, StatusBarProgressColorDefaults.accent))
        #expect(settings.hasCustomProgressAccentColor == false)

        settings.progressAccentColor = NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.78, alpha: 1)
        #expect(settings.hasCustomProgressAccentColor)

        settings.resetProgressAccentColor()

        #expect(colorsEqual(settings.progressAccentColor, StatusBarProgressColorDefaults.accent))
        #expect(settings.hasCustomProgressAccentColor == false)
    }

    @Test
    func progressAccentColorPersistsAcrossInstances() {
        let defaults = makeDefaults()
        let accent = NSColor(calibratedRed: 0.14, green: 0.55, blue: 0.31, alpha: 1)

        let first = AppSettings(userDefaults: defaults)
        first.progressAccentColor = accent

        let second = AppSettings(userDefaults: defaults)

        #expect(colorsEqual(second.progressAccentColor, accent))
        #expect(second.hasCustomProgressAccentColor)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AppSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func colorsEqual(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        let left = (lhs.usingColorSpace(.deviceRGB) ?? lhs.usingColorSpace(.sRGB)) ?? lhs
        let right = (rhs.usingColorSpace(.deviceRGB) ?? rhs.usingColorSpace(.sRGB)) ?? rhs

        return abs(left.redComponent - right.redComponent) < 0.001
            && abs(left.greenComponent - right.greenComponent) < 0.001
            && abs(left.blueComponent - right.blueComponent) < 0.001
            && abs(left.alphaComponent - right.alphaComponent) < 0.001
    }
}
