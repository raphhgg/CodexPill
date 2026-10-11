import AppKit
import Testing

@testable import Refill

struct StatusBarIconRendererTests {
    @Test
    func levelsShowWhatIsLeftAndKeepMissingLimitsEmpty() {
        let levels = StatusBarGlyphLevels(sessionUsedPercent: 30, weeklyUsedPercent: nil)

        #expect(levels.sessionRemainingPercent == 70)
        #expect(levels.weeklyRemainingPercent == nil)
    }

    @Test
    func levelsClampOutOfRangeUsage() {
        let levels = StatusBarGlyphLevels(sessionUsedPercent: 120, weeklyUsedPercent: -5)

        #expect(levels.sessionRemainingPercent == 0)
        #expect(levels.weeklyRemainingPercent == 100)
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
        #expect(StatusBarGlyphLevels.solidPunchSlots(remainingPercent: remainingPercent) == expectedSolidSlots)
    }

    @Test(arguments: StatusBarIndicatorStyle.allCases)
    func glyphIsATemplateImageSoTheMenuBarRecolorsIt(style: StatusBarIndicatorStyle) {
        let image = StatusBarIconRenderer().makeImage(
            style: style,
            levels: StatusBarGlyphLevels(sessionUsedPercent: 45, weeklyUsedPercent: 30)
        )

        #expect(image.isTemplate)
    }
}
