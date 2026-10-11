import AppKit

struct StatusBarGlyphLevels: Equatable, Sendable {
    let sessionRemainingPercent: Int?
    let weeklyRemainingPercent: Int?

    static let punchSlotsPerRow = 5

    init(sessionUsedPercent: Int?, weeklyUsedPercent: Int?) {
        sessionRemainingPercent = sessionUsedPercent.map(Self.remainingPercent(used:))
        weeklyRemainingPercent = weeklyUsedPercent.map(Self.remainingPercent(used:))
    }

    static func solidPunchSlots(remainingPercent: Int?) -> Int {
        guard let remainingPercent else { return 0 }
        return (remainingPercent * punchSlotsPerRow + 99) / 100
    }

    private static func remainingPercent(used: Int) -> Int {
        100 - min(max(used, 0), 100)
    }
}

struct StatusBarIconRenderer {
    static let glyphSize = NSSize(width: 18, height: 18)

    func makeImage(style: StatusBarIndicatorStyle, levels: StatusBarGlyphLevels) -> NSImage {
        let image = NSImage(size: Self.glyphSize, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            switch style {
            case .hourglass:
                HourglassGlyph.draw(levels, in: context)
            case .moon:
                MoonGlyph.draw(levels, in: context)
            case .punchCard:
                PunchCardGlyph.draw(levels, in: context)
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

private func ink(_ alpha: CGFloat = 1) -> CGColor {
    CGColor(gray: 0, alpha: alpha)
}

private func fraction(_ percent: Int) -> CGFloat {
    CGFloat(percent) / 100
}

private enum HourglassGlyph {
    static var outline: CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 4.8, y: 2.9))
        path.addLine(to: CGPoint(x: 13.2, y: 2.9))
        path.addCurve(to: CGPoint(x: 9.7, y: 9), control1: CGPoint(x: 13.2, y: 6), control2: CGPoint(x: 10.1, y: 7.6))
        path.addCurve(to: CGPoint(x: 13.2, y: 15.1), control1: CGPoint(x: 10.1, y: 10.4), control2: CGPoint(x: 13.2, y: 12))
        path.addLine(to: CGPoint(x: 4.8, y: 15.1))
        path.addCurve(to: CGPoint(x: 8.3, y: 9), control1: CGPoint(x: 4.8, y: 12), control2: CGPoint(x: 7.9, y: 10.4))
        path.addCurve(to: CGPoint(x: 4.8, y: 2.9), control1: CGPoint(x: 7.9, y: 7.6), control2: CGPoint(x: 4.8, y: 6))
        path.closeSubpath()
        return path
    }

    static var topBulb: CGPath { bulb(rimY: 4.1, neckY: 8.8, bulge: 6.3, shoulder: 7.7) }
    static var bottomBulb: CGPath { bulb(rimY: 13.9, neckY: 9.2, bulge: 11.7, shoulder: 10.3) }

    static func draw(_ levels: StatusBarGlyphLevels, in context: CGContext) {
        context.setLineJoin(.round)
        context.setLineWidth(1.2)
        context.setStrokeColor(ink())
        context.addPath(outline)
        context.strokePath()

        context.setLineCap(.round)
        context.setLineWidth(1.4)
        strokeLine(y: 1.6, to: 14.4, alpha: 1, in: context)
        strokeLine(y: 16.6, to: 14.4, alpha: 0.3, in: context)

        if let session = levels.sessionRemainingPercent.map(fraction) {
            fill(topBulb, from: 8.8 - 4.7 * session, to: 9, in: context)
            fill(bottomBulb, from: 13.9 - 4.7 * (1 - session), to: 14, in: context)
        }

        if let weekly = levels.weeklyRemainingPercent.map(fraction), weekly > 0 {
            strokeLine(y: 16.6, to: 3.6 + 10.8 * weekly, alpha: 1, in: context)
        }
    }

    private static func bulb(rimY: CGFloat, neckY: CGFloat, bulge: CGFloat, shoulder: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 6, y: rimY))
        path.addLine(to: CGPoint(x: 12, y: rimY))
        path.addCurve(to: CGPoint(x: 9.25, y: neckY), control1: CGPoint(x: 12, y: bulge), control2: CGPoint(x: 9.6, y: shoulder))
        path.addLine(to: CGPoint(x: 8.75, y: neckY))
        path.addCurve(to: CGPoint(x: 6, y: rimY), control1: CGPoint(x: 8.4, y: shoulder), control2: CGPoint(x: 6, y: bulge))
        path.closeSubpath()
        return path
    }

    private static func fill(_ bulb: CGPath, from top: CGFloat, to bottom: CGFloat, in context: CGContext) {
        context.saveGState()
        context.addPath(bulb)
        context.clip()
        context.setFillColor(ink())
        context.fill(CGRect(x: 5, y: top, width: 8, height: bottom - top))
        context.restoreGState()
    }

    private static func strokeLine(y: CGFloat, to endX: CGFloat, alpha: CGFloat, in context: CGContext) {
        context.setStrokeColor(ink(alpha))
        context.move(to: CGPoint(x: 3.6, y: y))
        context.addLine(to: CGPoint(x: endX, y: y))
        context.strokePath()
    }
}

private enum MoonGlyph {
    static let center = CGPoint(x: 9, y: 9)
    static let moonRadius: CGFloat = 5.2
    static let orbitRadius: CGFloat = 7.9
    static let top = -CGFloat.pi / 2

    static func draw(_ levels: StatusBarGlyphLevels, in context: CGContext) {
        let moonRect = CGRect(x: center.x - moonRadius, y: center.y - moonRadius, width: moonRadius * 2, height: moonRadius * 2)
        let orbitRect = moonRect.insetBy(dx: moonRadius - orbitRadius, dy: moonRadius - orbitRadius)

        if let session = levels.sessionRemainingPercent.map(fraction) {
            context.setFillColor(ink(0.25))
            context.fillEllipse(in: moonRect)
            context.setFillColor(ink())
            context.addPath(litPhase(session))
            context.fillPath()
        } else {
            context.saveGState()
            context.setLineWidth(1.1)
            context.setLineDash(phase: 0, lengths: [1.5, 1.5])
            context.setStrokeColor(ink())
            context.strokeEllipse(in: moonRect)
            context.restoreGState()
        }

        guard let weekly = levels.weeklyRemainingPercent.map(fraction) else {
            context.setLineWidth(1.1)
            context.setStrokeColor(ink(0.3))
            context.strokeEllipse(in: orbitRect)
            return
        }

        context.setLineWidth(1.3)
        context.setStrokeColor(ink(0.25))
        context.strokeEllipse(in: orbitRect)
        guard weekly > 0 else { return }
        context.setLineCap(.round)
        context.setStrokeColor(ink())
        context.addArc(center: center, radius: orbitRadius, startAngle: top, endAngle: top + weekly * 2 * .pi, clockwise: false)
        context.strokePath()
    }

    private static func litPhase(_ lit: CGFloat) -> CGPath {
        let clamped = min(max(lit, 0.001), 0.999)
        let terminatorWidth = max(abs(2 * clamped - 1), 0.001)
        let path = CGMutablePath()
        path.addArc(center: center, radius: moonRadius, startAngle: top, endAngle: -top, clockwise: false)
        let terminator = CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: terminatorWidth, y: 1)
        path.addArc(
            center: .zero,
            radius: moonRadius,
            startAngle: -top,
            endAngle: clamped > 0.5 ? 3 * -top : top,
            clockwise: clamped <= 0.5,
            transform: terminator
        )
        path.closeSubpath()
        return path
    }
}

private enum PunchCardGlyph {
    static func draw(_ levels: StatusBarGlyphLevels, in context: CGContext) {
        drawRow(y: 2.2, remainingPercent: levels.sessionRemainingPercent, in: context)
        drawRow(y: 10.4, remainingPercent: levels.weeklyRemainingPercent, in: context)
    }

    private static func drawRow(y: CGFloat, remainingPercent: Int?, in context: CGContext) {
        let solidSlots = StatusBarGlyphLevels.solidPunchSlots(remainingPercent: remainingPercent)
        let hollowAlpha: CGFloat = remainingPercent == nil ? 0.35 : 0.55
        context.setLineWidth(0.9)
        for index in 0..<StatusBarGlyphLevels.punchSlotsPerRow {
            let slot = CGRect(x: 1.9 + CGFloat(index) * 3, y: y, width: 2.4, height: 5.4)
            if index < solidSlots {
                context.setFillColor(ink())
                context.addPath(CGPath(roundedRect: slot, cornerWidth: 1.2, cornerHeight: 1.2, transform: nil))
                context.fillPath()
            } else {
                context.setStrokeColor(ink(hollowAlpha))
                context.addPath(CGPath(roundedRect: slot.insetBy(dx: 0.45, dy: 0.45), cornerWidth: 0.75, cornerHeight: 0.75, transform: nil))
                context.strokePath()
            }
        }
    }
}
