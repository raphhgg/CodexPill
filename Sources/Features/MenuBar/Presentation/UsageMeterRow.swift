import SwiftUI

struct UsageMeter: Identifiable {
    let title: String
    let window: UsageWindow?
    let tintColor: Color

    var id: String { title }
}

struct UsageMeters: View {
    let meters: [UsageMeter]
    let layout: UsageMeterLayout
    let percentMode: UsagePercentMode
    let showsPacingMarkers: Bool
    let now: Date

    var body: some View {
        switch layout {
        case .classic:
            VStack(alignment: .leading, spacing: 9) {
                ForEach(meters) { meter in
                    UsageMeterRow(
                        meter: meter,
                        percentMode: percentMode,
                        showsPacingMarkers: showsPacingMarkers,
                        now: now
                    )
                }
            }
        case .compact:
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                ForEach(meters) { meter in
                    GridRow(alignment: .center) {
                        Text(meter.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        UsageMeterBar(
                            percent: meter.window.map { displayedPercent(of: $0, mode: percentMode, now: now) } ?? 0,
                            expectedPercent: paceMarkerPercent(for: meter),
                            tintColor: meter.tintColor
                        )
                        .frame(height: 5)
                        .frame(maxWidth: .infinity)
                        Text(usageMeterPercentText(for: meter.window, mode: percentMode, now: now))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .gridColumnAlignment(.trailing)
                        Text(resetText(for: meter.window))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .lineLimit(1)
                }
            }
        }
    }

    private func paceMarkerPercent(for meter: UsageMeter) -> Int? {
        expectedPaceMarkerPercent(
            for: meter.window,
            showsPacingMarkers: showsPacingMarkers,
            percentMode: percentMode,
            now: now
        )
    }

    private func resetText(for window: UsageWindow?) -> String {
        guard let window else { return "Unavailable" }
        return resetStatusText(for: window, now: now) ?? ""
    }
}

struct UsageMeterRow: View {
    let meter: UsageMeter
    let percentMode: UsagePercentMode
    let showsPacingMarkers: Bool
    let now: Date

    var body: some View {
        let window = meter.window
        let expectedPercent = expectedPaceMarkerPercent(
            for: window,
            showsPacingMarkers: showsPacingMarkers,
            percentMode: percentMode,
            now: now
        )

        VStack(alignment: .leading, spacing: 5) {
            Text(meter.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            UsageMeterBar(
                percent: window.map { displayedPercent(of: $0, mode: percentMode, now: now) } ?? 0,
                expectedPercent: expectedPercent,
                tintColor: meter.tintColor
            )
            .frame(height: 5)
            HStack {
                Text(usageMeterPercentText(for: window, mode: percentMode, now: now))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Spacer()
                if let window, let resetStatus = resetStatusText(for: window, now: now) {
                    Text(resetStatus)
                        .foregroundStyle(.secondary)
                } else if window == nil {
                    Text("Unavailable")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
    }
}

private struct UsageMeterBar: View {
    let percent: Int
    let expectedPercent: Int?
    let tintColor: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let progressWidth = width * clampedFraction(percent)
            let markerX = expectedPercent.map { width * clampedFraction($0) }

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.16))
                Capsule()
                    .fill(tintColor)
                    .frame(width: progressWidth)

                if let markerX {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.72))
                        .frame(width: 2)
                        .offset(x: min(max(markerX - 1, 0), max(width - 2, 0)))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func clampedFraction(_ percent: Int) -> Double {
        min(max(Double(percent), 0), 100) / 100
    }
}
