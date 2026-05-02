import AppKit

enum StatusBarProgressColorDefaults {
    static let accent = NSColor.controlAccentColor
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
    var resolvedStatusItemAccentColor: NSColor {
        self?.nsColor ?? StatusBarProgressColorDefaults.accent
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
