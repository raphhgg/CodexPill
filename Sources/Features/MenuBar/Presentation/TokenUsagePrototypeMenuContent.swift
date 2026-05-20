import AppKit
import SwiftUI

struct TokenUsagePrototypeMenuContent: View {
    let card: TokenUsagePrototypeCard

    private var maximumTokenCount: Int {
        max(card.buckets.map(\.tokenCount).max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            chart
                .frame(height: 44)
            summary
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilitySummary)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Token Usage")
                    .font(.system(size: 14, weight: .semibold))
                Text("This Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(card.variant.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.11))
                )
        }
    }

    @ViewBuilder
    private var chart: some View {
        switch card.variant {
        case .minimalDailyBars:
            MinimalDailyBarsChart(
                buckets: card.buckets,
                maximumTokenCount: maximumTokenCount
            )
        case .sparklineArea:
            SparklineAreaChart(
                buckets: card.buckets,
                maximumTokenCount: maximumTokenCount
            )
        case .heatStrip:
            HeatStripChart(
                buckets: card.buckets,
                maximumTokenCount: maximumTokenCount
            )
        case .nativeCompact:
            NativeCompactUsageChart(card: card, maximumTokenCount: maximumTokenCount)
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
    }
}

struct TokenUsageMenuContent: View {
    let card: TokenUsageMenuCard

    private var maximumTokenCount: Int {
        max(card.buckets.map(\.tokenCount).max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            content
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilitySummary)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Token Usage")
                    .font(.system(size: 14, weight: .semibold))
                Text(card.periodTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Daily values")
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(card.hasData ? 1 : 0)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch card.loadState {
        case .loading:
            stateText("Scanning local sessions...")
        case .unavailable:
            stateText("Token usage unavailable")
        case .loaded:
            if card.hasData {
                chart
                    .frame(height: 38)
                summary
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
                maximumTokenCount: maximumTokenCount
            )
        case .heatStrip:
            HeatStripChart(
                buckets: card.buckets,
                maximumTokenCount: maximumTokenCount
            )
        case .sparkline:
            SparklineAreaChart(
                buckets: card.buckets,
                maximumTokenCount: maximumTokenCount
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
    }

    private func stateText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(height: 44, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MinimalDailyBarsChart: View {
    let buckets: [TokenUsageDayBucket]
    let maximumTokenCount: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(buckets) { bucket in
                Capsule()
                    .fill(barColor(for: bucket))
                    .frame(maxWidth: .infinity)
                    .frame(height: barHeight(for: bucket))
            }
        }
        .overlay(TokenUsageTooltipOverlay(buckets: buckets, layout: .linear))
        .accessibilityHidden(true)
    }

    private func barColor(for bucket: TokenUsageDayBucket) -> Color {
        bucket.id == buckets.last?.id ? .accentColor : Color.accentColor.opacity(0.58)
    }

    private func barHeight(for bucket: TokenUsageDayBucket) -> CGFloat {
        max(5, 38 * CGFloat(bucket.tokenCount) / CGFloat(maximumTokenCount))
    }
}

private struct SparklineAreaChart: View {
    let buckets: [TokenUsageDayBucket]
    let maximumTokenCount: Int

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
            }
            .contentShape(Rectangle())
        }
        .overlay(TokenUsageTooltipOverlay(buckets: buckets, layout: .linear))
        .accessibilityHidden(true)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(rowBuckets(row)) { bucket in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.accentColor.opacity(opacity(for: bucket)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
                            )
                            .frame(maxWidth: .infinity, minHeight: 10, maxHeight: 10)
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .overlay(TokenUsageTooltipOverlay(buckets: buckets, layout: .heatStrip(rows: 3, columns: 10)))
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

private struct TokenUsageTooltipOverlay: NSViewRepresentable {
    let buckets: [TokenUsageDayBucket]
    let layout: TokenUsageTooltipLayout

    func makeNSView(context: Context) -> TokenUsageTooltipView {
        let view = TokenUsageTooltipView()
        view.buckets = buckets
        view.tooltipLayout = layout
        return view
    }

    func updateNSView(_ nsView: TokenUsageTooltipView, context: Context) {
        nsView.buckets = buckets
        nsView.tooltipLayout = layout
        nsView.refreshToolTip()
    }
}

private final class TokenUsageTooltipView: NSView {
    var buckets: [TokenUsageDayBucket] = []
    var tooltipLayout: TokenUsageTooltipLayout = .linear

    private var tooltipTag: NSView.ToolTipTag?

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
        refreshToolTip()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshToolTip()
    }

    func refreshToolTip() {
        if let tooltipTag {
            removeToolTip(tooltipTag)
            self.tooltipTag = nil
        }

        guard !buckets.isEmpty, !bounds.isEmpty else { return }
        tooltipTag = addToolTip(bounds, owner: self, userData: nil)
    }

    func view(
        _ view: NSView,
        stringForToolTip tag: NSView.ToolTipTag,
        point: NSPoint,
        userData data: UnsafeMutableRawPointer?
    ) -> String {
        guard let bucket = bucket(at: point) else { return "" }
        return "\(bucket.shortLabel): \(formattedTokenCount(bucket.tokenCount)) tokens"
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

    private func clampedIndex(for value: CGFloat, width: CGFloat, count: Int) -> Int {
        guard count > 1, width > 0 else { return 0 }
        let fraction = min(max(value / width, 0), 0.999_999)
        return min(max(Int(floor(fraction * CGFloat(count))), 0), count - 1)
    }
}

private struct NativeCompactUsageChart: View {
    let card: TokenUsagePrototypeCard
    let maximumTokenCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(formattedTokenCount(card.periodTotalTokenCount))
                    .font(.system(size: 20, weight: .semibold))
                    .monospacedDigit()
                Text("tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                trendPill
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.14))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * todayFraction)
                }
            }
            .frame(height: 6)

            HStack {
                Text("Light")
                Spacer()
                Text("Heavy")
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
        .accessibilityHidden(true)
    }

    private var todayFraction: CGFloat {
        CGFloat(card.todayTokenCount) / CGFloat(maximumTokenCount)
    }

    private var trendPill: some View {
        let recentAverage = average(Array(card.buckets.suffix(7)))
        let priorAverage = average(Array(card.buckets.dropLast(7).suffix(7)))
        let percent = priorAverage == 0 ? 0 : Int(round(((recentAverage - priorAverage) / priorAverage) * 100))
        let prefix = percent >= 0 ? "+" : ""

        return Text("\(prefix)\(percent)% week")
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }

    private func average(_ buckets: [TokenUsageDayBucket]) -> Double {
        guard !buckets.isEmpty else { return 0 }
        return Double(buckets.reduce(0) { $0 + $1.tokenCount }) / Double(buckets.count)
    }
}
