import AppKit
import Testing

@testable import Refill

struct StatusBarIconRendererTests {
    @Test(arguments: [
        (30, 60, StatusBarGlyphReading.both(sessionRemainingPercent: 70, weeklyRemainingPercent: 40)),
        (30, nil, .single(remainingPercent: 70)),
        (nil, 25, .single(remainingPercent: 75)),
        (nil, nil, .noData),
        (120, -5, .both(sessionRemainingPercent: 0, weeklyRemainingPercent: 100))
    ] as [(Int?, Int?, StatusBarGlyphReading)])
    func readingShowsWhatIsLeftForTheLimitsTheAccountHas(
        sessionUsedPercent: Int?,
        weeklyUsedPercent: Int?,
        expected: StatusBarGlyphReading
    ) {
        let reading = StatusBarGlyphReading(sessionUsedPercent: sessionUsedPercent, weeklyUsedPercent: weeklyUsedPercent)

        #expect(reading == expected)
    }

    @Test(arguments: [
        (nil, 0),
        (0, 0),
        (1, 1),
        (20, 1),
        (21, 2),
        (40, 2),
        (79, 4),
        (80, 4),
        (81, 5),
        (100, 5)
    ] as [(Int?, Int)])
    func punchCardRoundsUpSoAnyAmountLeftShowsASolidSlot(remainingPercent: Int?, expectedSolidSlots: Int) {
        #expect(StatusBarGlyphReading.solidPunchSlots(remainingPercent: remainingPercent) == expectedSolidSlots)
    }

    @Test(arguments: StatusBarIndicatorStyle.allCases)
    func glyphIsATemplateImageSoTheMenuBarRecolorsIt(style: StatusBarIndicatorStyle) {
        let image = StatusBarIconRenderer().makeImage(
            style: style,
            reading: StatusBarGlyphReading(sessionUsedPercent: 45, weeklyUsedPercent: 30)
        )

        #expect(image.isTemplate)
    }
}
