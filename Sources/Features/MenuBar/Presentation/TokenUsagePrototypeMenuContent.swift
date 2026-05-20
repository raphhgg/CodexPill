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
            MinimalDailyBarsChart(buckets: card.buckets, maximumTokenCount: maximumTokenCount)
        case .sparklineArea:
            SparklineAreaChart(buckets: card.buckets, maximumTokenCount: maximumTokenCount)
        case .heatStrip:
            HeatStripChart(buckets: card.buckets, maximumTokenCount: maximumTokenCount)
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
        VStack(alignment: .leading, spacing: 7) {
            header
            content
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 11)
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
                    .frame(height: 44)
                    .padding(.top, 1)
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
            MinimalDailyBarsChart(buckets: card.buckets, maximumTokenCount: maximumTokenCount)
        case .heatStrip:
            HeatStripChart(buckets: card.buckets, maximumTokenCount: maximumTokenCount)
        case .sparkline:
            SparklineAreaChart(buckets: card.buckets, maximumTokenCount: maximumTokenCount)
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
                    .frame(maxWidth: 8)
                    .frame(height: barHeight(for: bucket))
                    .help(helpText(for: bucket))
            }
        }
        .padding(.top, 2)
        .accessibilityHidden(true)
    }

    private func barColor(for bucket: TokenUsageDayBucket) -> Color {
        bucket.id == buckets.last?.id ? .accentColor : Color.accentColor.opacity(0.58)
    }

    private func barHeight(for bucket: TokenUsageDayBucket) -> CGFloat {
        max(5, 42 * CGFloat(bucket.tokenCount) / CGFloat(maximumTokenCount))
    }

    private func helpText(for bucket: TokenUsageDayBucket) -> String {
        "\(bucket.shortLabel): \(formattedTokenCount(bucket.tokenCount)) tokens"
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
        }
        .help(helpText)
        .accessibilityHidden(true)
    }

    private var helpText: String {
        buckets.map { "\($0.shortLabel): \(formattedTokenCount($0.tokenCount)) tokens" }
            .joined(separator: "\n")
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
                            .help(helpText(for: bucket))
                    }
                }
            }
        }
        .padding(.vertical, 3)
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

    private func helpText(for bucket: TokenUsageDayBucket) -> String {
        "\(bucket.shortLabel): \(formattedTokenCount(bucket.tokenCount)) tokens"
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
