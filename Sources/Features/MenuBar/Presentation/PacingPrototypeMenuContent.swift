import SwiftUI

enum PacingPrototypeVariant: String, CaseIterable, Identifiable {
    case currentBaseline
    case textBesideUsage
    case textUnderUsage
    case textUnderReset
    case markerOnly
    case twoToneOverrun

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentBaseline:
            return "Current Baseline"
        case .textBesideUsage:
            return "Text Beside Usage"
        case .textUnderUsage:
            return "Text Under Usage"
        case .textUnderReset:
            return "Text Under Reset"
        case .markerOnly:
            return "Marker Only"
        case .twoToneOverrun:
            return "Two-Tone Overrun"
        }
    }

    var summary: String {
        switch self {
        case .currentBaseline:
            return "Existing card with no pacing copy or marker"
        case .textBesideUsage:
            return "Pacing copy stays next to the used percentage on the left"
        case .textUnderUsage:
            return "Pacing copy sits below the used percentage on the left"
        case .textUnderReset:
            return "Pacing copy sits below reset timing on the right"
        case .markerOnly:
            return "Only the bar shows expected pace"
        case .twoToneOverrun:
            return "The bar highlights only the over-pace segment"
        }
    }
}

private struct PacingPrototypeWindow: Identifiable {
    enum Pace {
        case under
        case onTrack
        case over

        var label: String {
            switch self {
            case .under:
                return "Room left"
            case .onTrack:
                return "On track"
            case .over:
                return "Fast pace"
            }
        }

        var color: Color {
            switch self {
            case .under:
                return .secondary
            case .onTrack:
                return .secondary
            case .over:
                return .orange
            }
        }
    }

    let id = UUID()
    let title: String
    let usedPercent: Int
    let expectedPercent: Int
    let resetText: String

    var deltaPoints: Int {
        usedPercent - expectedPercent
    }

    var pace: Pace {
        if deltaPoints >= 12 { return .over }
        if deltaPoints <= -12 { return .under }
        return .onTrack
    }

    var usageText: String {
        "\(usedPercent)% used"
    }

    var pacingText: String {
        switch pace {
        case .under:
            return "\(abs(deltaPoints)) pts below pace"
        case .onTrack:
            return "On track"
        case .over:
            return "\(deltaPoints) pts over pace"
        }
    }
}

struct PacingPrototypeMenuContent: View {
    let variant: PacingPrototypeVariant
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(variant.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            PacingPrototypeCard(variant: variant, accentColor: accentColor)

            Text(variant.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    fileprivate static let windows: [PacingPrototypeWindow] = [
        .init(title: "Session", usedPercent: 70, expectedPercent: 50, resetText: "Resets in 2h30"),
        .init(title: "Weekly", usedPercent: 42, expectedPercent: 57, resetText: "Resets in 3d")
    ]
}

private struct PacingPrototypeCard: View {
    let variant: PacingPrototypeVariant
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("Personal")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("Pro")
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Updated 59 seconds ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: "user@example.com")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .multilineTextAlignment(.trailing)
            }
            .padding(.top, -2)

            ForEach(PacingPrototypeMenuContent.windows) { window in
                PacingPrototypeLimitRow(
                    window: window,
                    variant: variant,
                    accentColor: accentColor
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct PacingPrototypeLimitRow: View {
    let window: PacingPrototypeWindow
    let variant: PacingPrototypeVariant
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(window.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            PacingPrototypeProgressBar(
                window: window,
                variant: variant,
                accentColor: accentColor
            )
            .frame(height: 5)

            switch variant {
            case .textUnderUsage:
                usageWithPaceUnderUsage
            case .textUnderReset:
                usageWithPaceUnderReset
            case .textBesideUsage:
                usageWithInlinePace
            case .currentBaseline, .markerOnly, .twoToneOverrun:
                baselineUsage
            }
        }
    }

    private var baselineUsage: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(window.usageText)
                .monospacedDigit()
                .foregroundStyle(.primary)
            Spacer()
            Text(window.resetText)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private var usageWithInlinePace: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(window.usageText)
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(window.pace.label)
                .foregroundStyle(window.pace.color)
            Spacer()
            Text(window.resetText)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private var usageWithPaceUnderUsage: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text(window.usageText)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(window.pacingText)
                    .foregroundStyle(window.pace.color)
            }
            Spacer()
            Text(window.resetText)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private var usageWithPaceUnderReset: some View {
        HStack(alignment: .top) {
            Text(window.usageText)
                .monospacedDigit()
                .foregroundStyle(.primary)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(window.resetText)
                    .foregroundStyle(.secondary)
                Text(window.pacingText)
                    .foregroundStyle(window.pace.color)
            }
        }
        .font(.caption)
    }
}

private struct PacingPrototypeProgressBar: View {
    let window: PacingPrototypeWindow
    let variant: PacingPrototypeVariant
    let accentColor: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let usedWidth = width * fraction(window.usedPercent)
            let expectedWidth = width * fraction(window.expectedPercent)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.16))

                if variant == .textUnderReset {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: min(width, expectedWidth + 12))
                }

                Capsule()
                    .fill(accentColor)
                    .frame(width: usedWidth)

                if variant == .twoToneOverrun, window.usedPercent > window.expectedPercent {
                    Capsule()
                        .fill(window.pace.color.opacity(0.78))
                        .frame(width: max(0, usedWidth - expectedWidth))
                        .offset(x: expectedWidth)
                }

                if variant != .currentBaseline && variant != .twoToneOverrun {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.72))
                        .frame(width: 2)
                        .offset(x: min(max(expectedWidth - 1, 0), max(width - 2, 0)))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func fraction(_ percent: Int) -> Double {
        min(max(Double(percent), 0), 100) / 100
    }
}
