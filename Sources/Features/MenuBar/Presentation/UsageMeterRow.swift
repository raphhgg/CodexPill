import SwiftUI

struct UsageMeterRow: View {
    let title: String
    let window: UsageWindow?
    let tintColor: Color
    let showsPacingMarkers: Bool
    let now: Date

    var body: some View {
        let displayedUsedPercent = window?.displayedUsedPercent(at: now) ?? 0
        let usageText = window.map { "\($0.displayedUsedPercent(at: now))% used" } ?? "--"
        let expectedPercent = expectedPaceMarkerPercent(
            for: window,
            showsPacingMarkers: showsPacingMarkers,
            now: now
        )

        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            UsageMeterBar(
                usedPercent: displayedUsedPercent,
                expectedPercent: expectedPercent,
                tintColor: tintColor
            )
            .frame(height: 5)
            HStack {
                Text(usageText)
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
    let usedPercent: Int
    let expectedPercent: Int?
    let tintColor: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let progressWidth = width * clampedFraction(usedPercent)
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
