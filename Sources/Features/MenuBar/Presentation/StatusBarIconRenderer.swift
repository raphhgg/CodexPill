import AppKit

/// The percents the glyph fills, in the same mode as the card text: 32% used fills 32% of the glyph.
enum StatusBarGlyphReading: Equatable, Sendable {
    case noData
    case single(percent: Int)
    case both(sessionPercent: Int, weeklyPercent: Int)

    static let punchSlotsPerRow = 5

    init(sessionPercent: Int?, weeklyPercent: Int?) {
        switch (sessionPercent.map(Self.clamped), weeklyPercent.map(Self.clamped)) {
        case let (session?, weekly?):
            self = .both(sessionPercent: session, weeklyPercent: weekly)
        case let (session?, nil):
            self = .single(percent: session)
        case let (nil, weekly?):
            self = .single(percent: weekly)
        case (nil, nil):
            self = .noData
        }
    }

    init(windows: [UsageWindow], mode: UsagePercentMode, now: Date = .now) {
        let percents = statusItemBarPercents(for: windows, mode: mode, now: now)
        self.init(sessionPercent: percents.primary, weeklyPercent: percents.secondary)
    }

    /// Rounds half up, but any amount above 0% fills at least one slot and only 100% fills the row.
    static func solidPunchSlots(percent: Int?) -> Int {
        guard let percent, percent > 0 else { return 0 }
        guard percent < 100 else { return punchSlotsPerRow }
        return min(max((percent * punchSlotsPerRow + 50) / 100, 1), punchSlotsPerRow - 1)
    }

    private static func clamped(_ percent: Int) -> Int {
        min(max(percent, 0), 100)
    }
}

struct StatusBarIconRenderer {
    static let glyphSize = NSSize(width: 18, height: 18)

    func makeImage(style: StatusBarIndicatorStyle, reading: StatusBarGlyphReading, percentMode: UsagePercentMode) -> NSImage {
        let image = NSImage(size: Self.glyphSize, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            switch style {
            case .hourglass:
                HourglassGlyph.draw(reading, percentMode: percentMode, in: context)
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
}

private func ink(_ alpha: CGFloat = 1) -> CGColor {
    CGColor(gray: 0, alpha: alpha)
}

private func fraction(_ percent: Int) -> CGFloat {
    CGFloat(percent) / 100
}

enum HourglassGlyph {
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

    /// Used sand has fallen into the bottom bulb; what is left still waits in the top bulb.
    /// Only that one bulb is drawn, so the ink always matches the percent the card shows.
    static func sandPath(percent: Int, percentMode: UsagePercentMode) -> CGPath? {
        guard percent > 0 else { return nil }
        let bulb = percentMode == .used ? bottomBulb : topBulb
        guard percent < 100 else { return bulb }
        let bounds = bulb.boundingBoxOfPath
        let target = bulb.area * fraction(percent)
        var top = bounds.minY
        var bottom = bounds.maxY
        for _ in 0..<24 {
            let level = (top + bottom) / 2
            if sand(in: bulb, from: level).area > target {
                top = level
            } else {
                bottom = level
            }
        }
        return sand(in: bulb, from: (top + bottom) / 2)
    }

    static func draw(_ reading: StatusBarGlyphReading, percentMode: UsagePercentMode, in context: CGContext) {
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
        case let .single(percent):
            fillSand(percent, percentMode: percentMode, in: context)
        case let .both(session, weekly):
            fillSand(session, percentMode: percentMode, in: context)
            strokeLine(y: 16.6, to: 14.4, alpha: 0.3, in: context)
            if weekly > 0 {
                strokeLine(y: 16.6, to: 3.6 + 10.8 * fraction(weekly), alpha: 1, in: context)
            }
        }
    }

    /// The measuring bulb gets a faint track, like the moon's dark side, so 0% still differs from no data.
    private static func fillSand(_ percent: Int, percentMode: UsagePercentMode, in context: CGContext) {
        context.setFillColor(ink(0.25))
        context.addPath(percentMode == .used ? bottomBulb : topBulb)
        context.fillPath()
        guard let sand = sandPath(percent: percent, percentMode: percentMode) else { return }
        context.setFillColor(ink())
        context.addPath(sand)
        context.fillPath()
    }

    private static func sand(in bulb: CGPath, from level: CGFloat) -> CGPath {
        let bounds = bulb.boundingBoxOfPath
        return bulb.intersection(CGPath(rect: CGRect(x: bounds.minX, y: level, width: bounds.width, height: bounds.maxY - level), transform: nil))
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

    private static func strokeLine(y: CGFloat, to endX: CGFloat, alpha: CGFloat, in context: CGContext) {
        context.setStrokeColor(ink(alpha))
        context.move(to: CGPoint(x: 3.6, y: y))
        context.addLine(to: CGPoint(x: endX, y: y))
        context.strokePath()
    }
}

enum MoonGlyph {
    static let center = CGPoint(x: 9, y: 9)
    static let moonRadius: CGFloat = 5.2
    static let orbitRadius: CGFloat = 7.9
    static let top = -CGFloat.pi / 2
    static let moonRect = CGRect(x: center.x - moonRadius, y: center.y - moonRadius, width: moonRadius * 2, height: moonRadius * 2)

    /// Lit from the right. Half the disc plus or minus half an ellipse of width |2f - 1| lights exactly f of its area.
    static func litPath(percent: Int) -> CGPath? {
        guard percent > 0 else { return nil }
        guard percent < 100 else { return CGPath(ellipseIn: moonRect, transform: nil) }
        let lit = fraction(percent)
        let terminatorWidth = max(abs(2 * lit - 1), 0.001)
        let path = CGMutablePath()
        path.addArc(center: center, radius: moonRadius, startAngle: top, endAngle: -top, clockwise: false)
        let terminator = CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: terminatorWidth, y: 1)
        path.addArc(
            center: .zero,
            radius: moonRadius,
            startAngle: -top,
            endAngle: lit > 0.5 ? 3 * -top : top,
            clockwise: lit <= 0.5,
            transform: terminator
        )
        path.closeSubpath()
        return path
    }

    static func draw(_ reading: StatusBarGlyphReading, in context: CGContext) {
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
        case let .single(percent):
            fillPhase(percent, context: context)
            return
        case let .both(session, weeklyPercent):
            fillPhase(session, context: context)
            weekly = fraction(weeklyPercent)
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

    private static func fillPhase(_ percent: Int, context: CGContext) {
        context.setFillColor(ink(0.25))
        context.fillEllipse(in: moonRect)
        guard let lit = litPath(percent: percent) else { return }
        context.setFillColor(ink())
        context.addPath(lit)
        context.fillPath()
    }
}

private enum PunchCardGlyph {
    static func draw(_ reading: StatusBarGlyphReading, in context: CGContext) {
        switch reading {
        case .noData:
            drawRow(y: 2.2, percent: nil, in: context)
            drawRow(y: 10.4, percent: nil, in: context)
        case let .single(percent):
            drawRow(y: 6.3, percent: percent, in: context)
        case let .both(session, weekly):
            drawRow(y: 2.2, percent: session, in: context)
            drawRow(y: 10.4, percent: weekly, in: context)
        }
    }

    private static func drawRow(y: CGFloat, percent: Int?, in context: CGContext) {
        let solidSlots = StatusBarGlyphReading.solidPunchSlots(percent: percent)
        let hollowAlpha: CGFloat = percent == nil ? 0.35 : 0.55
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

private extension CGPath {
    /// Shoelace area over the path flattened into short segments.
    var area: CGFloat {
        var total: CGFloat = 0
        var subpath: CGFloat = 0
        var start = CGPoint.zero
        var current = CGPoint.zero
        func line(to point: CGPoint) {
            subpath += current.x * point.y - point.x * current.y
            current = point
        }
        func closeSubpath() {
            line(to: start)
            total += abs(subpath) / 2
            subpath = 0
        }
        applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                if subpath != 0 { closeSubpath() }
                start = points[0]
                current = points[0]
            case .addLineToPoint:
                line(to: points[0])
            case .addQuadCurveToPoint:
                let from = current
                for step in 1...16 {
                    let t = CGFloat(step) / 16, u = 1 - t
                    line(to: CGPoint(
                        x: u * u * from.x + 2 * u * t * points[0].x + t * t * points[1].x,
                        y: u * u * from.y + 2 * u * t * points[0].y + t * t * points[1].y
                    ))
                }
            case .addCurveToPoint:
                let from = current
                for step in 1...16 {
                    let t = CGFloat(step) / 16, u = 1 - t
                    line(to: CGPoint(
                        x: u * u * u * from.x + 3 * u * u * t * points[0].x + 3 * u * t * t * points[1].x + t * t * t * points[2].x,
                        y: u * u * u * from.y + 3 * u * u * t * points[0].y + 3 * u * t * t * points[1].y + t * t * t * points[2].y
                    ))
                }
            case .closeSubpath:
                closeSubpath()
            @unknown default:
                break
            }
        }
        if subpath != 0 { closeSubpath() }
        return total
    }
}
