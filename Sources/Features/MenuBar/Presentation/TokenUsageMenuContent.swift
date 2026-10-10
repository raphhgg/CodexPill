import AppKit
import SwiftUI

struct TokenUsageMenuContent: View {
    let card: TokenUsageMenuCard
    @State private var hoveredBucket: TokenUsageDayBucket?

    private var maximumTokenCount: Int {
        max(card.buckets.map(\.tokenCount).max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            content
        }
        .padding(.horizontal, 14)
        .padding(.top, 0)
        .padding(.bottom, 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilitySummary)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Token Usage")
                    .font(.system(size: 14, weight: .semibold))
                Text(card.periodTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let peakDaySummary = card.peakDaySummary {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(card.peakDayTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(peakDaySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch card.loadState {
        case .loading(let progress):
            TokenUsageLoadingContent(
                style: card.style,
                animationStyle: card.loadingAnimationStyle,
                progress: progress
            )
        case .unavailable:
            stateText("Token usage unavailable")
        case .loaded:
            if card.hasData {
                VStack(alignment: .leading, spacing: 0) {
                    chart
                        .frame(height: 38)
                    summary
                    if card.showsTools {
                        toolRows
                    }
                }
            } else {
                stateText("No token usage found yet")
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        switch card.style {
        case .dailyBars:
            MinimalDailyBarsChart(
                buckets: card.buckets,
                maximumTokenCount: maximumTokenCount,
                stacksTools: card.showsTools,
                hoveredBucket: $hoveredBucket
            )
        case .heatStrip:
            HeatStripChart(
                buckets: card.buckets,
                maximumTokenCount: maximumTokenCount,
                hoveredBucket: $hoveredBucket
            )
        case .sparkline:
            SparklineAreaChart(
                buckets: card.buckets,
                maximumTokenCount: maximumTokenCount,
                hoveredBucket: $hoveredBucket
            )
        }
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Today: \(formattedTokenCount(card.todayTokenCount)) tokens")
                .foregroundStyle(.primary)
            Spacer(minLength: 10)
            Text("\(card.periodTitle): \(formattedTokenCount(card.periodTotalTokenCount)) tokens")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .monospacedDigit()
        .padding(.top, 6)
    }

    private var toolRows: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(card.toolSummaries) { summary in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Circle()
                            .fill(summary.tool.chartColor)
                            .frame(width: 7, height: 7)
                        Text(summary.tool.displayName)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 10)
                        if summary.isUnavailable {
                            Text("Unavailable")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Today \(formattedTokenCount(summary.todayTokenCount))")
                                .foregroundStyle(.secondary)
                            Text(formattedTokenCount(summary.periodTokenCount))
                                .foregroundStyle(.primary)
                                .frame(minWidth: 44, alignment: .trailing)
                        }
                    }
                    .font(.caption)
                    if let models = summary.modelsSummary {
                        Text(models)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.leading, 13)
                    }
                }
            }
        }
        .monospacedDigit()
        .padding(.top, 12)
    }

    private func stateText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(height: 44, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TokenUsageLoadingContent: View {
    let style: TokenUsageChartStyle
    let animationStyle: TokenUsageLoadingAnimationStyle
    let progress: TokenUsageScanProgress?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: TokenUsageLoadingMotion {
        TokenUsageLoadingMotion(preset: animationStyle.motionPreset, speedMultiplier: 1.18)
    }

    private var baseMessage: String {
        progress?.message ?? "Scanning local sessions"
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.06, paused: reduceMotion)) { timeline in
            let itemCount = itemCount(for: style)
            let frame = TokenUsageLoadingFrame.make(
                at: timeline.date,
                itemCount: itemCount,
                reduceMotion: reduceMotion,
                baseMessage: baseMessage
            )

            VStack(alignment: .leading, spacing: 0) {
                loadingChart(frame: frame)
                    .frame(height: 38)
                Text(frame.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.top, 6)
            }
            .accessibilityLabel(frame.message)
        }
    }

    @ViewBuilder
    private func loadingChart(frame: TokenUsageLoadingFrame) -> some View {
        switch style {
        case .dailyBars:
            TokenUsageLoadingBarsChart(
                highlightedIndex: frame.highlightedIndex,
                phase: frame.phase,
                motion: motion
            )
        case .heatStrip:
            TokenUsageLoadingHeatStripChart(
                highlightedIndex: frame.highlightedIndex,
                phase: frame.phase,
                motion: motion
            )
        case .sparkline:
            TokenUsageLoadingSparklineChart(
                highlightedIndex: frame.highlightedIndex,
                phase: frame.phase,
                motion: motion
            )
        }
    }

    private func itemCount(for style: TokenUsageChartStyle) -> Int {
        switch style {
        case .dailyBars:
            return TokenUsageLoadingBarsChart.itemCount
        case .heatStrip:
            return TokenUsageLoadingHeatStripChart.itemCount
        case .sparkline:
            return TokenUsageLoadingSparklineChart.itemCount
        }
    }
}

private enum TokenUsageLoadingMotionPreset {
    case random
    case waves
}

private extension TokenUsageLoadingAnimationStyle {
    var motionPreset: TokenUsageLoadingMotionPreset {
        switch self {
        case .random:
            return .random
        case .waves:
            return .waves
        }
    }
}

private struct TokenUsageLoadingMotion {
    let preset: TokenUsageLoadingMotionPreset
    let speedMultiplier: Double

    func value(at index: Int, count: Int, phase: Double) -> CGFloat {
        switch preset {
        case .random:
            return randomValue(at: index, phase: phase)
        case .waves:
            return wavesValue(at: index, count: count, phase: phase)
        }
    }

    func sparklineValue(at index: Int, count: Int, phase: Double) -> CGFloat {
        switch preset {
        case .random:
            return randomSparklineValue(at: index, count: count, phase: phase)
        case .waves:
            return wavesValue(at: index, count: count, phase: phase)
        }
    }

    private func randomValue(at index: Int, phase: Double) -> CGFloat {
        let seed = Double((index * 37) % 17)
        let speed = (3.15 + (Double(index % 5) * 0.50)) * speedMultiplier
        let primary = sin((phase * speed) + seed)
        let secondary = sin((phase * (speed * 0.58)) + (seed * 1.9))
        let mixed = (primary * 0.62) + (secondary * 0.38)
        let normalized = (mixed + 1) / 2
        return 0.06 + (0.90 * CGFloat(normalized))
    }

    private func randomSparklineValue(at index: Int, count: Int, phase: Double) -> CGFloat {
        let safeCount = max(count - 1, 1)
        let position = Double(index) / Double(safeCount)
        let flow = sin((phase * 4.20 * speedMultiplier) - (position * .pi * 3.2))
        let jitter = sin((phase * 6.05 * speedMultiplier) + (Double(index) * 1.7))
        let mixed = (flow * 0.72) + (jitter * 0.28)
        let normalized = (mixed + 1) / 2
        return 0.08 + (0.84 * CGFloat(normalized))
    }

    private func wavesValue(at index: Int, count: Int, phase: Double) -> CGFloat {
        let safeCount = max(count - 1, 1)
        let position = Double(index) / Double(safeCount)
        let primarySpeed = 4.35 * speedMultiplier
        let secondarySpeed = 2.20 * speedMultiplier
        let wave = sin((phase * primarySpeed) - (position * .pi * 4.6))
        let ripple = sin((phase * secondarySpeed) - (position * .pi * 8.2))
        let mixed = (wave * 0.76) + (ripple * 0.24)
        let normalized = (mixed + 1) / 2
        return 0.05 + (0.91 * CGFloat(normalized))
    }
}

private struct TokenUsageLoadingBarsChart: View {
    static let itemCount = 30

    let highlightedIndex: Int
    let phase: Double
    let motion: TokenUsageLoadingMotion

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 2
            let itemWidth = max(
                1,
                (geometry.size.width - (spacing * CGFloat(Self.itemCount - 1))) / CGFloat(Self.itemCount)
            )

            ZStack(alignment: .bottomLeading) {
                ForEach(0..<Self.itemCount, id: \.self) { index in
                    let value = barValue(at: index)
                    let height = max(5, geometry.size.height * value)
                    Capsule()
                        .fill(Color.accentColor.opacity(opacity(for: value)))
                        .frame(width: itemWidth, height: height)
                        .position(
                            x: (itemWidth / 2) + (CGFloat(index) * (itemWidth + spacing)),
                            y: geometry.size.height - (height / 2)
                        )
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func barValue(at index: Int) -> CGFloat {
        motion.value(at: index, count: Self.itemCount, phase: phase)
    }

    private func opacity(for value: CGFloat) -> Double {
        0.22 + (0.48 * Double(value))
    }
}

private struct TokenUsageLoadingSparklineChart: View {
    static let itemCount = 9

    let highlightedIndex: Int
    let phase: Double
    let motion: TokenUsageLoadingMotion

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let points = (0..<Self.itemCount).map { index in
                let x = size.width * CGFloat(index) / 8
                let value = motion.sparklineValue(at: index, count: Self.itemCount, phase: phase)
                let y = size.height * (0.18 + (0.68 * (1 - value)))
                return CGPoint(x: x, y: y)
            }

            ZStack(alignment: .bottomLeading) {
                linePath(points: points)
                    .stroke(
                        Color.accentColor.opacity(0.44),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
            }
        }
        .accessibilityHidden(true)
    }

    private func linePath(points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)

            for index in 1..<points.count {
                let previous = points[index - 1]
                let current = points[index]
                let midpoint = CGPoint(
                    x: (previous.x + current.x) / 2,
                    y: (previous.y + current.y) / 2
                )
                path.addQuadCurve(to: midpoint, control: previous)

                if index == points.count - 1 {
                    path.addQuadCurve(to: current, control: midpoint)
                }
            }
        }
    }
}

private struct TokenUsageLoadingHeatStripChart: View {
    static let itemCount = 30

    let highlightedIndex: Int
    let phase: Double
    let motion: TokenUsageLoadingMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<10, id: \.self) { column in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.accentColor.opacity(opacity(row: row, column: column)))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func opacity(row: Int, column: Int) -> Double {
        let index = (row * 10) + column
        let value = motion.value(at: index, count: Self.itemCount, phase: phase)
        return 0.11 + (0.57 * Double(value))
    }
}

private struct MinimalDailyBarsChart: View {
    let buckets: [TokenUsageDayBucket]
    let maximumTokenCount: Int
    var stacksTools = false
    @Binding var hoveredBucket: TokenUsageDayBucket?

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(buckets) { bucket in
                    if stacksTools {
                        stackedBar(for: bucket, height: barHeight(for: bucket, in: geometry.size.height))
                    } else {
                        Capsule()
                            .fill(barColor(for: bucket))
                            .frame(maxWidth: .infinity)
                            .frame(height: barHeight(for: bucket, in: geometry.size.height))
                    }
                }
            }
            .overlay(
                TokenUsageTooltipOverlay(buckets: buckets, layout: .linear) { bucket in
                    hoveredBucket = bucket
                }
            )
        }
        .accessibilityHidden(true)
    }

    private func barColor(for bucket: TokenUsageDayBucket) -> Color {
        if hoveredBucket?.id == bucket.id {
            return .accentColor
        }
        return bucket.id == buckets.last?.id ? .accentColor : Color.accentColor.opacity(0.58)
    }

    private func barHeight(for bucket: TokenUsageDayBucket, in height: CGFloat) -> CGFloat {
        max(5, height * CGFloat(bucket.tokenCount) / CGFloat(maximumTokenCount))
    }

    /// The first tool sits at the bottom. Empty days keep a faint stub so the 30 slots stay visible.
    private func stackedBar(for bucket: TokenUsageDayBucket, height: CGFloat) -> some View {
        let isEmphasized = hoveredBucket.map { $0.id == bucket.id } ?? (bucket.id == buckets.last?.id)
        let visibleSegments = bucket.segments.filter { $0.tokenCount > 0 }
        return VStack(spacing: 0) {
            if visibleSegments.isEmpty {
                Rectangle().fill(Color.secondary.opacity(0.25))
            } else {
                ForEach(Array(visibleSegments.reversed().enumerated()), id: \.offset) { _, segment in
                    Rectangle()
                        .fill(segment.tool.chartColor.opacity(isEmphasized ? 1 : 0.72))
                        .frame(height: height * CGFloat(segment.tokenCount) / CGFloat(max(bucket.tokenCount, 1)))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
    }

}

private struct SparklineAreaChart: View {
    let buckets: [TokenUsageDayBucket]
    let maximumTokenCount: Int
    @Binding var hoveredBucket: TokenUsageDayBucket?

    var body: some View {
        GeometryReader { geometry in
            let points = chartPoints(in: geometry.size)

            ZStack(alignment: .bottomLeading) {
                areaPath(points: points, size: geometry.size)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.26), Color.accentColor.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                linePath(points: points)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if let last = points.last {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                        .position(last)
                }

                if let hoveredPoint = hoveredPoint(from: points) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.75), lineWidth: 1)
                        )
                        .position(hoveredPoint)
                }
            }
            .contentShape(Rectangle())
            .overlay(
                TokenUsageTooltipOverlay(buckets: buckets, layout: .linear) { bucket in
                    hoveredBucket = bucket
                }
            )
        }
        .accessibilityHidden(true)
    }

    private func hoveredPoint(from points: [CGPoint]) -> CGPoint? {
        guard let hoveredBucket,
              let index = buckets.firstIndex(where: { $0.id == hoveredBucket.id }),
              points.indices.contains(index) else {
            return nil
        }

        return points[index]
    }

    private func chartPoints(in size: CGSize) -> [CGPoint] {
        guard buckets.count > 1 else { return [] }
        let xStep = size.width / CGFloat(buckets.count - 1)
        return buckets.enumerated().map { index, bucket in
            let fraction = CGFloat(bucket.tokenCount) / CGFloat(maximumTokenCount)
            return CGPoint(
                x: CGFloat(index) * xStep,
                y: size.height - max(3, fraction * (size.height - 4))
            )
        }
    }

    private func linePath(points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    private func areaPath(points: [CGPoint], size: CGSize) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: first.x, y: size.height))
            path.addLine(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.closeSubpath()
        }
    }
}

private struct HeatStripChart: View {
    let buckets: [TokenUsageDayBucket]
    let maximumTokenCount: Int
    @Binding var hoveredBucket: TokenUsageDayBucket?

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 5) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(rowBuckets(row)) { bucket in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.accentColor.opacity(opacity(for: bucket)))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .stroke(
                                            hoveredBucket?.id == bucket.id
                                            ? Color.primary.opacity(0.75)
                                            : Color.secondary.opacity(0.12),
                                            lineWidth: hoveredBucket?.id == bucket.id ? 1 : 0.5
                                        )
                                )
                                .frame(maxWidth: .infinity, minHeight: 10, maxHeight: 10)
                        }
                    }
                }
            }
            .padding(.vertical, 3)
            .overlay(
                TokenUsageTooltipOverlay(buckets: buckets, layout: .heatStrip(rows: 3, columns: 10)) { bucket in
                    hoveredBucket = bucket
                }
            )
        }
        .accessibilityHidden(true)
    }

    private func rowBuckets(_ row: Int) -> [TokenUsageDayBucket] {
        let start = row * 10
        let end = min(start + 10, buckets.count)
        guard start < end else { return [] }
        return Array(buckets[start..<end])
    }

    private func opacity(for bucket: TokenUsageDayBucket) -> Double {
        0.14 + (0.76 * Double(bucket.tokenCount) / Double(maximumTokenCount))
    }

}

private enum TokenUsageTooltipLayout: Equatable {
    case linear
    case heatStrip(rows: Int, columns: Int)
}

private func tokenUsageLinearIndex(for value: CGFloat, width: CGFloat, count: Int) -> Int {
    guard count > 1, width > 0 else { return 0 }
    let fraction = min(max(value / width, 0), 0.999_999)
    return min(max(Int(floor(fraction * CGFloat(count))), 0), count - 1)
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension TokenUsageDayBucket {
    var tooltipDateLabel: String {
        shortLabel
    }

    var tooltipTokenCount: String {
        formattedTokenCount(tokenCount).replacingOccurrences(of: ".", with: ",")
    }

    var tooltipText: String {
        let total = "\(tooltipTokenCount) tokens (\(tooltipDateLabel))"
        let tools = segments
            .filter { $0.tokenCount > 0 }
            .map { "\($0.tool.displayName) \(formattedTokenCount($0.tokenCount))" }
        guard segments.count > 1, !tools.isEmpty else { return total }
        return total + "\n" + tools.joined(separator: " · ")
    }
}

extension TokenUsageTool {
    var chartColor: Color {
        switch self {
        case .codex:
            return Color(nsColor: .systemTeal)
        case .claudeCode:
            return Color(nsColor: .systemOrange)
        case .cursor:
            return Color(nsColor: .systemIndigo)
        }
    }
}

private struct TokenUsageTooltipOverlay: NSViewRepresentable {
    let buckets: [TokenUsageDayBucket]
    let layout: TokenUsageTooltipLayout
    var onBucketHover: (TokenUsageDayBucket?) -> Void = { _ in }

    func makeNSView(context: Context) -> TokenUsageTooltipView {
        let view = TokenUsageTooltipView()
        view.buckets = buckets
        view.tooltipLayout = layout
        view.onBucketHover = onBucketHover
        return view
    }

    func updateNSView(_ nsView: TokenUsageTooltipView, context: Context) {
        nsView.buckets = buckets
        nsView.tooltipLayout = layout
        nsView.onBucketHover = onBucketHover
    }
}

private final class TokenUsageTooltipView: NSView {
    var buckets: [TokenUsageDayBucket] = []
    var tooltipLayout: TokenUsageTooltipLayout = .linear
    var onBucketHover: (TokenUsageDayBucket?) -> Void = { _ in }

    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        clearToolTip()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshTrackingArea()
    }

    override func mouseEntered(with event: NSEvent) {
        updateHoveredBucket(for: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoveredBucket(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        toolTip = nil
        onBucketHover(nil)
    }

    func clearToolTip() {
        toolTip = nil
    }

    private func refreshTrackingArea() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }

        guard !bounds.isEmpty else { return }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    private func bucket(at point: NSPoint) -> TokenUsageDayBucket? {
        guard !buckets.isEmpty, bounds.width > 0, bounds.height > 0 else { return nil }

        switch tooltipLayout {
        case .linear:
            let index = clampedIndex(for: point.x, width: bounds.width, count: buckets.count)
            return buckets[index]

        case .heatStrip(let rows, let columns):
            guard rows > 0, columns > 0 else { return nil }
            let column = clampedIndex(for: point.x, width: bounds.width, count: columns)
            let bottomOriginRow = clampedIndex(for: point.y, width: bounds.height, count: rows)
            let topOriginRow = (rows - 1) - bottomOriginRow
            let index = topOriginRow * columns + column
            guard buckets.indices.contains(index) else { return nil }
            return buckets[index]
        }
    }

    private func updateHoveredBucket(for event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let bucket = bucket(at: point)
        toolTip = bucket.map { $0.tooltipText }
        onBucketHover(bucket)
    }

    private func clampedIndex(for value: CGFloat, width: CGFloat, count: Int) -> Int {
        tokenUsageLinearIndex(for: value, width: width, count: count)
    }
}
