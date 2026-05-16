import AppKit

enum StatusBarProgressColorDefaults {
    static let sessionAccent = NSColor(
        calibratedRed: 52 / 255,
        green: 120 / 255,
        blue: 246 / 255,
        alpha: 1
    )
    static let weeklyAccent = NSColor(
        calibratedRed: 0 / 255,
        green: 178 / 255,
        blue: 204 / 255,
        alpha: 1
    )
    static let accent = weeklyAccent
}

extension StatusItemAccentColor {
    init(nsColor color: NSColor) {
        let normalized = color.normalizedStatusItemAccentColor
        self.init(
            red: Double(normalized.redComponent),
            green: Double(normalized.greenComponent),
            blue: Double(normalized.blueComponent),
            alpha: Double(normalized.alphaComponent)
        )
    }

    var nsColor: NSColor {
        NSColor(
            deviceRed: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }
}

extension Optional where Wrapped == StatusItemAccentColor {
    func resolvedStatusItemAccentColor(default defaultColor: NSColor) -> NSColor {
        self?.nsColor ?? defaultColor
    }

    var resolvedStatusItemAccentColor: NSColor {
        resolvedStatusItemAccentColor(default: StatusBarProgressColorDefaults.accent)
    }
}

extension NSColor {
    var normalizedStatusItemAccentColor: NSColor {
        if let deviceRGB = usingColorSpace(.deviceRGB) {
            return deviceRGB
        }

        if let sRGB = usingColorSpace(.sRGB) {
            return sRGB
        }

        return self
    }

    func isEqualToStatusItemAccentColor(_ other: NSColor) -> Bool {
        let left = normalizedStatusItemAccentColor
        let right = other.normalizedStatusItemAccentColor

        return abs(left.redComponent - right.redComponent) < 0.001
            && abs(left.greenComponent - right.greenComponent) < 0.001
            && abs(left.blueComponent - right.blueComponent) < 0.001
            && abs(left.alphaComponent - right.alphaComponent) < 0.001
    }
}
