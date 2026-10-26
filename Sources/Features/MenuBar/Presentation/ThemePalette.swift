import AppKit
import SwiftUI

/// The colors a theme gives each part of the menu.
///
/// Hue themes and Monochrome draw the three tools as a strong, a middle and a soft shade of one color, so the
/// Token Usage card always adds a marker shape and a dash per tool. Tool Colors gives each tool its own color.
struct ThemePalette {
    let theme: AppTheme

    /// A tool's color in the Token Usage card, and its Session bar under Tool Colors.
    func toolColor(_ tool: TokenUsageTool) -> NSColor {
        switch theme {
        case .toolColors:
            return Self.toolColor(tool)
        case .monochrome:
            return NSColor.labelColor.withAlphaComponent([0.88, 0.52, 0.26][tool.shade])
        default:
            let hue = hue
            return NSColor(
                hue: hue.hue,
                saturation: hue.saturation * [1, 0.7, 0.45][tool.shade],
                brightness: [0.95, 0.72, 0.5][tool.shade],
                alpha: 1
            )
        }
    }

    /// The Session bar on a tool card.
    func sessionColor(for tool: TokenUsageTool) -> NSColor {
        switch theme {
        case .toolColors:
            return Self.toolColor(tool)
        default:
            return toolColor(.codex)
        }
    }

    /// The Weekly bar on a tool card: a softer version of the Session color.
    func weeklyColor(for tool: TokenUsageTool) -> NSColor {
        switch theme {
        case .toolColors:
            return Self.toolColor(tool).withAlphaComponent(0.6)
        case .monochrome:
            return NSColor.labelColor.withAlphaComponent(0.55)
        default:
            let hue = hue
            return NSColor(hue: hue.hue, saturation: hue.saturation * 0.55, brightness: 0.85, alpha: 1)
        }
    }

    /// Hue and saturation sampled from each icon's liquid.
    private var hue: (hue: CGFloat, saturation: CGFloat) {
        switch theme {
        case .cobalt: (0.605, 0.78)
        case .lagoon: (0.55, 0.62)
        case .emerald: (0.40, 0.58)
        case .violet: (0.705, 0.68)
        case .honey: (0.105, 0.72)
        case .rose: (0.94, 0.62)
        case .monochrome, .toolColors: (0, 0)
        }
    }

    private static func toolColor(_ tool: TokenUsageTool) -> NSColor {
        switch tool {
        case .codex: .systemTeal
        case .claudeCode: .systemOrange
        case .cursor: .systemIndigo
        }
    }
}

extension UsageProvider {
    /// The same tool in the Token Usage card's terms.
    var tokenUsageTool: TokenUsageTool {
        switch self {
        case .codex: .codex
        case .claude: .claudeCode
        case .cursor: .cursor
        }
    }
}

private extension TokenUsageTool {
    /// Each tool keeps its shade whatever the menu's order, so a tool reads the same after a reorder.
    var shade: Int {
        switch self {
        case .codex: 0
        case .claudeCode: 1
        case .cursor: 2
        }
    }
}
