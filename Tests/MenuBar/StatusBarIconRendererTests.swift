import AppKit
import CryptoKit
import Testing

@testable import CodexPill

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

    private func imageDigest(_ image: NSImage) throws -> String {
        let data = try #require(image.tiffRepresentation)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
