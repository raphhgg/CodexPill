import AppKit

/// One status-bar meter. A window Codex did not report is `.missing` and draws as an
/// outline-only track, so it never looks like 0%.
enum StatusBarMeter: Equatable {
    case missing
    case level(CGFloat)

    init(percent: Int?) {
        guard let percent else {
            self = .missing
            return
        }
        self = .level(max(0, min(CGFloat(percent) / 100, 1)))
    }

    var progress: CGFloat {
        guard case .level(let progress) = self else { return 0 }
        return progress
    }
}

struct StatusBarIconRenderer {
    func makeImage(
        style: StatusBarIndicatorStyle,
        primaryPercent: Int?,
        secondaryPercent: Int?,
        monochrome: Bool,
        primaryColor: NSColor,
        secondaryColor: NSColor
    ) -> NSImage {
        let size = NSSize(width: 19, height: 19)
        let image = NSImage(size: size)
        image.lockFocus()

        let palette = palette(monochrome: monochrome, primaryColor: primaryColor, secondaryColor: secondaryColor)
        let drawing = DrawingContext(
            rect: NSRect(origin: .zero, size: size).insetBy(dx: 0.8, dy: 0.8),
            primary: StatusBarMeter(percent: primaryPercent),
            secondary: StatusBarMeter(percent: secondaryPercent),
            trackColor: NSColor.tertiaryLabelColor.withAlphaComponent(0.45),
            outlineColor: NSColor.secondaryLabelColor,
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

    private func palette(
        monochrome: Bool,
        primaryColor: NSColor,
        secondaryColor: NSColor
    ) -> (primary: NSColor, secondary: NSColor) {
        guard !monochrome else {
            return (
                primary: NSColor.labelColor,
                secondary: NSColor.labelColor.withAlphaComponent(0.62)
            )
        }
        return (primary: primaryColor, secondary: secondaryColor)
    }

    private func drawDualArcBadge(in context: DrawingContext) {
        let center = CGPoint(x: context.rect.midX, y: context.rect.midY)
        let radius = min(context.rect.width, context.rect.height) / 2 - 2.2
        let lineWidth: CGFloat = 3.0

        let halves: [(meter: StatusBarMeter, clockwise: Bool, color: NSColor)] = [
            (context.primary, true, context.primaryColor),
            (context.secondary, false, context.secondaryColor),
        ]
        for half in halves {
            let track = arcPath(center: center, radius: radius, start: 270, end: 90, clockwise: half.clockwise)
            guard half.meter != .missing else {
                strokeOutline(of: track, lineWidth: lineWidth, color: context.outlineColor)
                continue
            }
            stroke(track, lineWidth: lineWidth, color: context.trackColor)
            if half.meter.progress > 0 {
                let end = half.clockwise ? 270 - (180 * half.meter.progress) : 270 + (180 * half.meter.progress)
                stroke(
                    arcPath(center: center, radius: radius, start: 270, end: end, clockwise: half.clockwise),
                    lineWidth: lineWidth,
                    color: half.color
                )
            }
        }
    }

    private func drawStackedBars(in context: DrawingContext) {
        let box = context.rect.insetBy(dx: 1.1, dy: 2.1)
        let topTrack = NSRect(x: box.minX, y: box.midY + 1.4, width: box.width, height: 4.8)
        let bottomTrack = NSRect(x: box.minX, y: box.midY - 6.2, width: box.width, height: 4.8)

        drawHorizontalBar(track: topTrack, meter: context.primary, fillColor: context.primaryColor, context: context)
        drawHorizontalBar(track: bottomTrack, meter: context.secondary, fillColor: context.secondaryColor, context: context)

        let divider = NSBezierPath(roundedRect: NSRect(x: box.minX + 2.4, y: box.midY - 0.7, width: box.width - 4.8, height: 1.4), xRadius: 0.7, yRadius: 0.7)
        context.baseColor.withAlphaComponent(0.15).setFill()
        divider.fill()
    }

    private func drawTwinPills(in context: DrawingContext) {
        let leftRect = NSRect(x: context.rect.minX + 1.9, y: context.rect.minY + 1.9, width: 5.9, height: context.rect.height - 3.8)
        let rightRect = NSRect(x: context.rect.maxX - 7.8, y: context.rect.minY + 1.9, width: 5.9, height: context.rect.height - 3.8)

        drawVerticalPill(track: leftRect, meter: context.primary, fillColor: context.primaryColor, context: context)
        drawVerticalPill(track: rightRect, meter: context.secondary, fillColor: context.secondaryColor, context: context)

        let dividerRect = NSRect(x: context.rect.midX - 0.6, y: context.rect.minY + 2.8, width: 1.2, height: context.rect.height - 5.6)
        let divider = NSBezierPath(roundedRect: dividerRect, xRadius: 0.6, yRadius: 0.6)
        context.baseColor.withAlphaComponent(0.12).setFill()
        divider.fill()
    }

    private func drawVerticalPill(track rect: NSRect, meter: StatusBarMeter, fillColor: NSColor, context: DrawingContext) {
        guard meter != .missing else {
            strokeOutline(ofRoundedRect: rect, color: context.outlineColor)
            return
        }
        let track = NSBezierPath(roundedRect: rect, xRadius: rect.width / 2, yRadius: rect.width / 2)
        context.trackColor.setFill()
        track.fill()

        let progress = meter.progress
        let fillHeight = progress > 0 ? rect.height * (0.12 + 0.88 * progress) : 0
        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(rect.height, fillHeight))
        let fillRadius = min(fillRect.width, fillRect.height) / 2
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: fillRadius, yRadius: fillRadius)
        fillColor.setFill()
        fill.fill()
    }

    private func drawHorizontalBar(track rect: NSRect, meter: StatusBarMeter, fillColor: NSColor, context: DrawingContext) {
        guard meter != .missing else {
            strokeOutline(ofRoundedRect: rect, color: context.outlineColor)
            return
        }
        let track = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        context.trackColor.setFill()
        track.fill()

        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: max(rect.height, rect.width * meter.progress), height: rect.height)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        fillColor.setFill()
        fill.fill()
    }

    private func arcPath(center: CGPoint, radius: CGFloat, start: CGFloat, end: CGFloat, clockwise: Bool) -> NSBezierPath {
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: clockwise)
        return path
    }

    private func stroke(_ path: NSBezierPath, lineWidth: CGFloat, color: NSColor) {
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    /// Strokes the edge of the band `path` would paint at `lineWidth`, leaving its inside empty.
    private func strokeOutline(of path: NSBezierPath, lineWidth: CGFloat, color: NSColor) {
        guard let cgContext = NSGraphicsContext.current?.cgContext else { return }
        cgContext.saveGState()
        cgContext.addPath(path.cgPath)
        cgContext.setLineWidth(lineWidth)
        cgContext.setLineCap(.round)
        cgContext.replacePathWithStrokedPath()
        cgContext.setLineWidth(Self.outlineWidth)
        cgContext.setStrokeColor(color.cgColor)
        cgContext.strokePath()
        cgContext.restoreGState()
    }

    private func strokeOutline(ofRoundedRect rect: NSRect, color: NSColor) {
        let inset = rect.insetBy(dx: Self.outlineWidth / 2, dy: Self.outlineWidth / 2)
        let radius = min(inset.width, inset.height) / 2
        let path = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)
        path.lineWidth = Self.outlineWidth
        color.setStroke()
        path.stroke()
    }

    private static let outlineWidth: CGFloat = 1
}

private struct DrawingContext {
    let rect: NSRect
    let primary: StatusBarMeter
    let secondary: StatusBarMeter
    let trackColor: NSColor
    let outlineColor: NSColor
    let primaryColor: NSColor
    let secondaryColor: NSColor
    let baseColor: NSColor
}
