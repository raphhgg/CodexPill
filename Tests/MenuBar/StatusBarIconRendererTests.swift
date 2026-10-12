import AppKit
import Testing

@testable import Refill

struct StatusBarIconRendererTests {
    @Test(arguments: [
        (UsagePercentMode.used, StatusBarGlyphReading.both(sessionPercent: 32, weeklyPercent: 28), "32% used", "28% used"),
        (.left, .both(sessionPercent: 68, weeklyPercent: 72), "68% left", "72% left")
    ])
    func glyphFillsTheSamePercentTheCardShows(
        mode: UsagePercentMode,
        expected: StatusBarGlyphReading,
        sessionText: String,
        weeklyText: String
    ) {
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let session = UsageWindow(kind: .session, usedPercent: 32, resetsAt: now.addingTimeInterval(3_600), durationMinutes: 300)
        let weekly = UsageWindow(kind: .weekly, usedPercent: 28, resetsAt: now.addingTimeInterval(86_400), durationMinutes: 10_080)

        #expect(StatusBarGlyphReading(windows: [session, weekly], mode: mode, now: now) == expected)
        #expect(usageMeterPercentText(for: session, mode: mode, now: now) == sessionText)
        #expect(usageMeterPercentText(for: weekly, mode: mode, now: now) == weeklyText)
    }

    @Test(arguments: [
        (30, nil, StatusBarGlyphReading.single(percent: 30)),
        (nil, 25, .single(percent: 25)),
        (nil, nil, .noData),
        (120, -5, .both(sessionPercent: 100, weeklyPercent: 0))
    ] as [(Int?, Int?, StatusBarGlyphReading)])
    func readingKeepsOnlyTheLimitsTheAccountHas(sessionPercent: Int?, weeklyPercent: Int?, expected: StatusBarGlyphReading) {
        #expect(StatusBarGlyphReading(sessionPercent: sessionPercent, weeklyPercent: weeklyPercent) == expected)
    }

    @Test(arguments: [
        (nil, 0),
        (0, 0),
        (1, 1),
        (5, 1),
        (10, 1),
        (25, 1),
        (28, 1),
        (30, 2),
        (32, 2),
        (50, 3),
        (75, 4),
        (90, 4),
        (99, 4),
        (100, 5)
    ] as [(Int?, Int)])
    func punchCardFillsTheNearestSlotCount(percent: Int?, expectedSolidSlots: Int) {
        #expect(StatusBarGlyphReading.solidPunchSlots(percent: percent) == expectedSolidSlots)
    }

    @Test
    func glassesLiquidCoversThePercentOfItsGlassByArea() throws {
        for glass in [GlassesGlyph.sessionGlass, GlassesGlyph.weeklyGlass, GlassesGlyph.singleGlass] {
            let glassArea = coveredArea(of: glass)
            #expect(GlassesGlyph.liquidPath(percent: 0, in: glass) == nil)

            for percent in [5, 10, 25, 32, 50, 75, 90, 100] {
                let liquid = try #require(GlassesGlyph.liquidPath(percent: percent, in: glass))
                let filled = coveredArea(of: liquid) / glassArea
                #expect(abs(filled - Double(percent) / 100) < 0.02, "\(percent)% filled \(filled)")
            }
        }
    }

    @Test
    func moonLitPhaseCoversThePercentOfTheDiscByArea() throws {
        let discArea = coveredArea(of: CGPath(ellipseIn: MoonGlyph.moonRect, transform: nil))
        #expect(MoonGlyph.litPath(percent: 0) == nil)

        for percent in [5, 10, 25, 32, 50, 75, 90, 100] {
            let lit = try #require(MoonGlyph.litPath(percent: percent))
            let filled = coveredArea(of: lit) / discArea
            #expect(abs(filled - Double(percent) / 100) < 0.02, "\(percent)% lit \(filled)")
        }
    }

    @Test(arguments: StatusBarIndicatorStyle.allCases)
    func glyphIsATemplateImageSoTheMenuBarRecolorsIt(style: StatusBarIndicatorStyle) {
        let image = StatusBarIconRenderer().makeImage(
            style: style,
            reading: StatusBarGlyphReading(sessionPercent: 45, weeklyPercent: 30)
        )

        #expect(image.isTemplate)
    }

    /// Rasterizes the path at 16x inside the 18 pt glyph box and sums the antialiased coverage.
    private func coveredArea(of path: CGPath) -> Double {
        let scale = 16
        let side = 18 * scale
        var pixels = [UInt8](repeating: 0, count: side * side)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )!
            context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            context.setFillColor(gray: 1, alpha: 1)
            context.addPath(path)
            context.fillPath()
        }
        return pixels.reduce(0) { $0 + Double($1) / 255 }
    }
}
