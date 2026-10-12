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

    func makeImage(style: StatusBarIndicatorStyle, reading: StatusBarGlyphReading) -> NSImage {
        let image = NSImage(size: Self.glyphSize, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            switch style {
            case .glasses:
                GlassesGlyph.draw(reading, in: context)
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

/// Two glasses: the session on the left, the weekly limit on the right. The liquid fills each glass by area.
enum GlassesGlyph {
    static var sessionGlass: CGPath { glass(centerX: 5, topWidth: 6.4, bottomWidth: 4.6) }
    static var weeklyGlass: CGPath { glass(centerX: 13, topWidth: 6.4, bottomWidth: 4.6) }
    static var singleGlass: CGPath { glass(centerX: 9, topWidth: 9, bottomWidth: 6.6) }

    /// Fills the glass from the bottom up to the level where the liquid covers `percent` of its area.
    static func liquidPath(percent: Int, in glass: CGPath) -> CGPath? {
        guard percent > 0 else { return nil }
        guard percent < 100 else { return glass }
        let bounds = glass.boundingBoxOfPath
        let target = glass.area * fraction(percent)
        var top = bounds.minY
        var bottom = bounds.maxY
        for _ in 0..<24 {
            let level = (top + bottom) / 2
            if liquid(in: glass, from: level).area > target {
                top = level
            } else {
                bottom = level
            }
        }
        return liquid(in: glass, from: (top + bottom) / 2)
    }

    static func draw(_ reading: StatusBarGlyphReading, in context: CGContext) {
        switch reading {
        case .noData:
            drawGlass(sessionGlass, percent: nil, outlineAlpha: 0.35, in: context)
            drawGlass(weeklyGlass, percent: nil, outlineAlpha: 0.35, in: context)
        case let .single(percent):
            drawGlass(singleGlass, percent: percent, outlineAlpha: 1, in: context)
        case let .both(session, weekly):
            drawGlass(sessionGlass, percent: session, outlineAlpha: 1, in: context)
            drawGlass(weeklyGlass, percent: weekly, outlineAlpha: 1, in: context)
        }
    }

    private static func drawGlass(_ glass: CGPath, percent: Int?, outlineAlpha: CGFloat, in context: CGContext) {
        context.setLineWidth(1.1)
        context.setLineJoin(.round)
        context.setStrokeColor(ink(outlineAlpha))
        context.addPath(glass)
        context.strokePath()
        guard let percent, let liquid = liquidPath(percent: percent, in: glass) else { return }
        context.setFillColor(ink())
        context.addPath(liquid)
        context.fillPath()
    }

    private static func liquid(in glass: CGPath, from level: CGFloat) -> CGPath {
        let bounds = glass.boundingBoxOfPath.insetBy(dx: -1, dy: 0)
        return glass.intersection(CGPath(rect: CGRect(x: bounds.minX, y: level, width: bounds.width, height: bounds.maxY - level), transform: nil))
    }

    /// A tumbler narrowing toward a base with rounded corners.
    private static func glass(centerX: CGFloat, topWidth: CGFloat, bottomWidth: CGFloat) -> CGPath {
        let top: CGFloat = 2.6
        let bottom: CGFloat = 15.6
        let corner: CGFloat = 1.2
        let rimHalf = topWidth / 2
        let baseHalf = bottomWidth / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: centerX - rimHalf, y: top))
        path.addLine(to: CGPoint(x: centerX + rimHalf, y: top))
        path.addLine(to: CGPoint(x: centerX + baseHalf, y: bottom - corner))
        path.addQuadCurve(to: CGPoint(x: centerX + baseHalf - corner, y: bottom), control: CGPoint(x: centerX + baseHalf - 0.05, y: bottom))
        path.addLine(to: CGPoint(x: centerX - baseHalf + corner, y: bottom))
        path.addQuadCurve(to: CGPoint(x: centerX - baseHalf, y: bottom - corner), control: CGPoint(x: centerX - baseHalf + 0.05, y: bottom))
        path.closeSubpath()
        return path
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
