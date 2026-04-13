import AppKit

struct StatusBarIconRenderer {
    func makeImage(
        style: StatusBarIndicatorStyle,
        primaryPercent: Int?,
        secondaryPercent: Int?,
        monochrome: Bool
    ) -> NSImage {
        let size = NSSize(width: 19, height: 19)
        let image = NSImage(size: size)
        image.lockFocus()

        let palette = palette(monochrome: monochrome, primaryPercent: primaryPercent, secondaryPercent: secondaryPercent)
        let drawing = DrawingContext(
            rect: NSRect(origin: .zero, size: size).insetBy(dx: 0.8, dy: 0.8),
            primaryProgress: progress(for: primaryPercent),
            secondaryProgress: progress(for: secondaryPercent),
            trackColor: NSColor.tertiaryLabelColor.withAlphaComponent(0.45),
            primaryColor: palette.primary,
            secondaryColor: palette.secondary,
            baseColor: NSColor.labelColor
        )

        switch style {
        case .dualArcBadge:
            drawDualArcBadge(in: drawing)
        case .stackedBars:
            drawStackedBars(in: drawing)
        case .twinPills:
            drawTwinPills(in: drawing)
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func progress(for percent: Int?) -> CGFloat {
        guard let percent else { return 0 }
        return max(0, min(CGFloat(percent) / 100, 1))
    }

    private func palette(monochrome: Bool, primaryPercent: Int?, secondaryPercent: Int?) -> (primary: NSColor, secondary: NSColor) {
        guard !monochrome else {
            return (
                primary: NSColor.labelColor,
                secondary: NSColor.labelColor.withAlphaComponent(0.62)
            )
        }
        return (
            primary: color(for: primaryPercent, secondary: false),
            secondary: color(for: secondaryPercent, secondary: true)
        )
    }

    private func color(for percent: Int?, secondary: Bool) -> NSColor {
        guard let percent else { return secondary ? NSColor.secondaryLabelColor : NSColor.labelColor }
        switch percent {
        case 90...:
            return .systemRed
        case 70...:
            return .systemOrange
        default:
            return secondary ? .systemTeal : .controlAccentColor
        }
    }

    private func drawDualArcBadge(in context: DrawingContext) {
        let center = CGPoint(x: context.rect.midX, y: context.rect.midY)
        let radius = min(context.rect.width, context.rect.height) / 2 - 2.2
        let lineWidth: CGFloat = 3.0

        strokeArc(center: center, radius: radius, start: 270, end: 90, clockwise: true, color: context.trackColor, lineWidth: lineWidth)
        strokeArc(center: center, radius: radius, start: 270, end: 90, clockwise: false, color: context.trackColor, lineWidth: lineWidth)

        if context.primaryProgress > 0 {
            let primaryEnd = 270 - (180 * context.primaryProgress)
            strokeArc(center: center, radius: radius, start: 270, end: primaryEnd, clockwise: true, color: context.primaryColor, lineWidth: lineWidth)
        }

        if context.secondaryProgress > 0 {
            let secondaryEnd = 270 + (180 * context.secondaryProgress)
            strokeArc(center: center, radius: radius, start: 270, end: secondaryEnd, clockwise: false, color: context.secondaryColor, lineWidth: lineWidth)
        }
    }

    private func drawStackedBars(in context: DrawingContext) {
        let box = context.rect.insetBy(dx: 1.1, dy: 2.1)
        let topTrack = NSRect(x: box.minX, y: box.midY + 1.4, width: box.width, height: 4.8)
        let bottomTrack = NSRect(x: box.minX, y: box.midY - 6.2, width: box.width, height: 4.8)

        drawHorizontalBar(track: topTrack, progress: context.primaryProgress, fillColor: context.primaryColor, trackColor: context.trackColor)
        drawHorizontalBar(track: bottomTrack, progress: context.secondaryProgress, fillColor: context.secondaryColor, trackColor: context.trackColor)

        let divider = NSBezierPath(roundedRect: NSRect(x: box.minX + 2.4, y: box.midY - 0.7, width: box.width - 4.8, height: 1.4), xRadius: 0.7, yRadius: 0.7)
        context.baseColor.withAlphaComponent(0.15).setFill()
        divider.fill()
    }

    private func drawTwinPills(in context: DrawingContext) {
        let leftRect = NSRect(x: context.rect.minX + 1.9, y: context.rect.minY + 1.9, width: 5.9, height: context.rect.height - 3.8)
        let rightRect = NSRect(x: context.rect.maxX - 7.8, y: context.rect.minY + 1.9, width: 5.9, height: context.rect.height - 3.8)

        drawVerticalPill(track: leftRect, progress: context.primaryProgress, fillColor: context.primaryColor, trackColor: context.trackColor)
        drawVerticalPill(track: rightRect, progress: context.secondaryProgress, fillColor: context.secondaryColor, trackColor: context.trackColor)

        let dividerRect = NSRect(x: context.rect.midX - 0.6, y: context.rect.minY + 2.8, width: 1.2, height: context.rect.height - 5.6)
        let divider = NSBezierPath(roundedRect: dividerRect, xRadius: 0.6, yRadius: 0.6)
        context.baseColor.withAlphaComponent(0.12).setFill()
        divider.fill()
    }

    private func drawVerticalPill(track rect: NSRect, progress: CGFloat, fillColor: NSColor, trackColor: NSColor) {
        let track = NSBezierPath(roundedRect: rect, xRadius: rect.width / 2, yRadius: rect.width / 2)
        trackColor.setFill()
        track.fill()

        let fillHeight = max(rect.width, rect.height * progress)
        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(rect.height, fillHeight))
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: rect.width / 2, yRadius: rect.width / 2)
        fillColor.setFill()
        fill.fill()
    }

    private func drawHorizontalBar(track rect: NSRect, progress: CGFloat, fillColor: NSColor, trackColor: NSColor) {
        let track = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        trackColor.setFill()
        track.fill()

        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: max(rect.height, rect.width * progress), height: rect.height)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        fillColor.setFill()
        fill.fill()
    }

    private func strokeArc(center: CGPoint, radius: CGFloat, start: CGFloat, end: CGFloat, clockwise: Bool, color: NSColor, lineWidth: CGFloat) {
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: clockwise)
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }
}

private struct DrawingContext {
    let rect: NSRect
    let primaryProgress: CGFloat
    let secondaryProgress: CGFloat
    let trackColor: NSColor
    let primaryColor: NSColor
    let secondaryColor: NSColor
    let baseColor: NSColor
}
