import AppKit
import Testing

@testable import Refill

struct ThemePaletteTests {
    @Test
    func toolColorsGivesEachToolItsOwnSessionColor() {
        let palette = ThemePalette(theme: .toolColors)

        #expect(palette.sessionColor(for: .codex) == .systemTeal)
        #expect(palette.sessionColor(for: .claudeCode) == .systemOrange)
        #expect(palette.sessionColor(for: .cursor) == .systemIndigo)
    }

    @Test(arguments: [AppTheme.cobalt, .rose, .monochrome])
    func singleHueThemesShareBarColorsAndShadeTheTools(theme: AppTheme) {
        let palette = ThemePalette(theme: theme)

        #expect(palette.sessionColor(for: .codex) == palette.sessionColor(for: .cursor))
        #expect(palette.weeklyColor(for: .codex) != palette.sessionColor(for: .codex))
        #expect(Set([palette.toolColor(.codex), palette.toolColor(.claudeCode), palette.toolColor(.cursor)]).count == 3)
    }
}
