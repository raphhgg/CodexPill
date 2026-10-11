import AppKit
import CryptoKit
import Testing

@testable import Refill

struct StatusBarIconRendererTests {
    @Test
    func configuredPrimaryAndSecondaryColorsChangeRenderedOutput() throws {
        let renderer = StatusBarIconRenderer()

        let sessionGreen = try imageDigest(
            renderer.makeImage(
                style: .twinPills,
                primaryPercent: 100,
                secondaryPercent: nil,
                monochrome: false,
                primaryColor: NSColor(calibratedRed: 0.16, green: 0.62, blue: 0.28, alpha: 1),
                secondaryColor: .systemTeal
            )
        )
        let sessionOrange = try imageDigest(
            renderer.makeImage(
                style: .twinPills,
                primaryPercent: 100,
                secondaryPercent: nil,
                monochrome: false,
                primaryColor: NSColor(calibratedRed: 0.84, green: 0.42, blue: 0.18, alpha: 1),
                secondaryColor: .systemTeal
            )
        )

        let weeklyPink = try imageDigest(
            renderer.makeImage(
                style: .twinPills,
                primaryPercent: nil,
                secondaryPercent: 100,
                monochrome: false,
                primaryColor: .controlAccentColor,
                secondaryColor: NSColor(calibratedRed: 0.72, green: 0.21, blue: 0.66, alpha: 1)
            )
        )
        let weeklyBlue = try imageDigest(
            renderer.makeImage(
                style: .twinPills,
                primaryPercent: nil,
                secondaryPercent: 100,
                monochrome: false,
                primaryColor: .controlAccentColor,
                secondaryColor: NSColor(calibratedRed: 0.18, green: 0.46, blue: 0.86, alpha: 1)
            )
        )

        #expect(sessionGreen != sessionOrange)
        #expect(weeklyPink != weeklyBlue)
    }

    @Test
    func missingWindowIsItsOwnMeterStateAndNotZero() {
        #expect(StatusBarMeter(percent: nil) == .missing)
        #expect(StatusBarMeter(percent: 0) == .level(0))
        #expect(StatusBarMeter(percent: 40) == .level(0.4))
        #expect(StatusBarMeter(percent: 140) == .level(1))
    }

    @Test(arguments: [StatusBarIndicatorStyle.dualArcBadge, .stackedBars, .twinPills])
    func missingWindowDrawsDifferentlyFromZeroPercent(style: StatusBarIndicatorStyle) throws {
        let renderer = StatusBarIconRenderer()
        func digest(sessionPercent: Int?) throws -> String {
            try imageDigest(
                renderer.makeImage(
                    style: style,
                    primaryPercent: sessionPercent,
                    secondaryPercent: 40,
                    monochrome: false,
                    primaryColor: .systemGreen,
                    secondaryColor: .systemBlue
                )
            )
        }

        #expect(try digest(sessionPercent: nil) != digest(sessionPercent: 0))
    }

    private func imageDigest(_ image: NSImage) throws -> String {
        let data = try #require(image.tiffRepresentation)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
