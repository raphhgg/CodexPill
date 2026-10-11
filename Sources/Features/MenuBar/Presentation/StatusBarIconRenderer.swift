import AppKit

enum StatusBarGlyphReading: Equatable, Sendable {
    case noData
    case single(remainingPercent: Int)
    case both(sessionRemainingPercent: Int, weeklyRemainingPercent: Int)

    static let punchSlotsPerRow = 5

    init(sessionUsedPercent: Int?, weeklyUsedPercent: Int?) {
        switch (sessionUsedPercent.map(Self.remainingPercent(used:)), weeklyUsedPercent.map(Self.remainingPercent(used:))) {
        case let (session?, weekly?):
            self = .both(sessionRemainingPercent: session, weeklyRemainingPercent: weekly)
        case let (session?, nil):
            self = .single(remainingPercent: session)
        case let (nil, weekly?):
            self = .single(remainingPercent: weekly)
        case (nil, nil):
            self = .noData
        }
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

    func makeImage(style: StatusBarIndicatorStyle, reading: StatusBarGlyphReading) -> NSImage {
        let image = NSImage(size: Self.glyphSize, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            switch style {
            case .hourglass:
                HourglassGlyph.draw(reading, in: context)
            case .moon:
                MoonGlyph.draw(reading, in: context)
            case .punchCard:
                PunchCardGlyph.draw(reading, in: context)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The app's pill, for when no tool is set up yet: half filled, half outlined, tilted like the app icon.
    func makeAppGlyph() -> NSImage {
        let image = NSImage(size: Self.glyphSize, flipped: false) { rect in
            let pillWidth: CGFloat = 7
            let pillLength: CGFloat = 17
            let outlineWidth: CGFloat = 1
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: rect.midY)
            transform.rotate(byDegrees: -45)
            transform.concat()

            let pill = NSRect(x: -pillWidth / 2, y: -pillLength / 2, width: pillWidth, height: pillLength)
            let outline = NSBezierPath(
                roundedRect: pill.insetBy(dx: outlineWidth / 2, dy: outlineWidth / 2),
                xRadius: (pillWidth - outlineWidth) / 2,
                yRadius: (pillWidth - outlineWidth) / 2
            )
            outline.lineWidth = outlineWidth * 1.4
            NSColor.black.setStroke()
            outline.stroke()

            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: pill.minX, y: pill.minY, width: pill.width, height: pill.height / 2)).addClip()
            NSColor.black.setFill()
            NSBezierPath(roundedRect: pill, xRadius: pillWidth / 2, yRadius: pillWidth / 2).fill()
            NSGraphicsContext.restoreGraphicsState()
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

    static func draw(_ reading: StatusBarGlyphReading, in context: CGContext) {
        context.setLineJoin(.round)
        context.setLineWidth(1.2)
        context.setStrokeColor(ink())
        context.addPath(outline)
        context.strokePath()

        context.setLineCap(.round)
        context.setLineWidth(1.4)
        strokeLine(y: 1.6, to: 14.4, alpha: 1, in: context)

        switch reading {
        case .noData:
            strokeLine(y: 16.6, to: 14.4, alpha: 0.3, in: context)
        case let .single(remaining):
            fillSand(remaining, in: context)
        case let .both(session, weekly):
            fillSand(session, in: context)
            strokeLine(y: 16.6, to: 14.4, alpha: 0.3, in: context)
            if weekly > 0 {
                strokeLine(y: 16.6, to: 3.6 + 10.8 * fraction(weekly), alpha: 1, in: context)
            }
        }
    }

    private static func fillSand(_ remainingPercent: Int, in context: CGContext) {
        let remaining = fraction(remainingPercent)
        fill(topBulb, from: 8.8 - 4.7 * remaining, to: 9, in: context)
        fill(bottomBulb, from: 13.9 - 4.7 * (1 - remaining), to: 14, in: context)
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

    static func draw(_ reading: StatusBarGlyphReading, in context: CGContext) {
        let moonRect = CGRect(x: center.x - moonRadius, y: center.y - moonRadius, width: moonRadius * 2, height: moonRadius * 2)
        let orbitRect = moonRect.insetBy(dx: moonRadius - orbitRadius, dy: moonRadius - orbitRadius)

        let weekly: CGFloat
        switch reading {
        case .noData:
            context.setLineWidth(1.1)
            context.setStrokeColor(ink(0.35))
            context.strokeEllipse(in: moonRect)
            context.setStrokeColor(ink(0.3))
            context.strokeEllipse(in: orbitRect)
            return
        case let .single(remaining):
            fillPhase(remaining, in: moonRect, context: context)
            return
        case let .both(session, weeklyRemaining):
            fillPhase(session, in: moonRect, context: context)
            weekly = fraction(weeklyRemaining)
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

    private static func fillPhase(_ remainingPercent: Int, in moonRect: CGRect, context: CGContext) {
        context.setFillColor(ink(0.25))
        context.fillEllipse(in: moonRect)
        context.setFillColor(ink())
        context.addPath(litPhase(fraction(remainingPercent)))
        context.fillPath()
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
    static func draw(_ reading: StatusBarGlyphReading, in context: CGContext) {
        switch reading {
        case .noData:
            drawRow(y: 2.2, remainingPercent: nil, in: context)
            drawRow(y: 10.4, remainingPercent: nil, in: context)
        case let .single(remaining):
            drawRow(y: 6.3, remainingPercent: remaining, in: context)
        case let .both(session, weekly):
            drawRow(y: 2.2, remainingPercent: session, in: context)
            drawRow(y: 10.4, remainingPercent: weekly, in: context)
        }
    }

    private static func drawRow(y: CGFloat, remainingPercent: Int?, in context: CGContext) {
        let solidSlots = StatusBarGlyphReading.solidPunchSlots(remainingPercent: remainingPercent)
        let hollowAlpha: CGFloat = remainingPercent == nil ? 0.35 : 0.55
        context.setLineWidth(0.9)
        for index in 0..<StatusBarGlyphReading.punchSlotsPerRow {
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
