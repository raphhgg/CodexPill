import AppKit
import SwiftUI

/// The Token Usage card: a chart and a split, each with its own toggle, in the theme's colors.
///
/// It reads a live model, so new data and toggle changes redraw it while the menu is open. Every state keeps
/// the same layout, so the menu item never needs to change height.
struct TokenUsageMenuContent: View {
    let model: TokenUsageCardModel
    @State private var hoveredDay: Int?

    private var card: TokenUsageMenuCard { model.card }
    private var preferences: TokenUsagePreferencesStore { model.preferences }
    private var palette: TokenUsagePalette { TokenUsagePalette(theme: model.theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            chartArea.frame(height: 44)
            breakdownPicker
                .opacity(card.showsSplits ? 1 : 0)
                .disabled(!card.showsSplits)
                .accessibilityHidden(!card.showsSplits)
            ZStack(alignment: .topLeading) {
                splits(for: card.layoutTemplate).hidden().accessibilityHidden(true)
                if card.showsSplits {
                    splits(for: card)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(card.accessibilitySummary)
    }

    @ViewBuilder
    private var chartArea: some View {
        switch card.phase {
        case .unavailable:
            stateText("Token usage unavailable")
        case .loaded where !card.hasData:
            stateText("No token usage found yet")
        case .loading where card.showsPlaceholderChart:
            TokenUsagePlaceholderBars(count: card.days.count)
        case .loading:
            chart.opacity(0.4)
        case .loaded:
            chart.overlay(TokenUsageTooltipOverlay(dayCount: card.days.count, text: card.tooltip(forDay:)) { hoveredDay = $0 })
        }
    }

    /// Both splits are laid out so the card keeps the taller height when the toggle switches.
    private func splits(for card: TokenUsageMenuCard) -> some View {
        ZStack(alignment: .topLeading) {
            TokenUsageByToolSplit(card: card, palette: palette)
                .opacity(preferences.breakdown == .byTool ? 1 : 0)
                .accessibilityHidden(preferences.breakdown != .byTool)
            TokenUsageTopModelsSplit(card: card, palette: palette)
                .opacity(preferences.breakdown == .topModels ? 1 : 0)
                .accessibilityHidden(preferences.breakdown != .topModels)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center) {
                Text("Token Usage").font(.system(size: 14, weight: .semibold))
                Spacer()
                TokenUsageSegmented(
                    items: TokenUsageChartStyle.allCases,
                    selection: preferences.chartStyle,
                    select: { preferences.chartStyle = $0 },
                    accessibilityName: \.accessibilityName
                ) { Image(systemName: $0.symbolName).font(.system(size: 10, weight: .semibold)) }
            }
            Text(card.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var breakdownPicker: some View {
        TokenUsageSegmented(
            items: TokenUsageBreakdown.allCases,
            selection: preferences.breakdown,
            select: { preferences.breakdown = $0 },
            accessibilityName: \.title
        ) { Text($0.title).font(.system(size: 11, weight: .medium)) }
    }

    @ViewBuilder
    private var chart: some View {
        switch preferences.chartStyle {
        case .bars:
            TokenUsageBarsChart(card: card, palette: palette, hoveredDay: card.isLoading ? nil : hoveredDay)
        case .area:
            TokenUsageAreaChart(card: card, palette: palette)
        case .lines:
            TokenUsageLinesChart(card: card, palette: palette)
        }
    }

    private func stateText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(height: 44, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension TokenUsageChartStyle {
    var symbolName: String {
        switch self {
        case .bars: "chart.bar.fill"
        case .area: "mountain.2.fill"
        case .lines: "chart.xyaxis.line"
        }
    }

    var accessibilityName: String {
        switch self {
        case .bars: "Bars"
        case .area: "Area"
        case .lines: "Lines"
        }
    }
}

extension TokenUsageBreakdown {
    var title: String {
        switch self {
        case .byTool: "By tool"
        case .topModels: "Top models"
        }
    }
}

/// The theme's tool colors, plus a dash and a marker shape per tool so the tools never rely on color alone.
struct TokenUsagePalette {
    let theme: AppTheme

    /// Hue themes and Monochrome draw all three tools from one color.
    var isSingleHue: Bool { theme != .toolColors }

    func color(_ tool: TokenUsageTool) -> Color {
        Color(nsColor: ThemePalette(theme: theme).toolColor(tool))
    }

    /// Models within one tool: the tool's color, fading.
    func modelColor(_ tool: TokenUsageTool, index: Int) -> Color {
        color(tool).opacity([1, 0.6, 0.32][min(index, 2)])
    }

    func dash(_ tool: TokenUsageTool) -> [CGFloat] {
        switch tool {
        case .codex: return []
        case .claudeCode: return [4, 2.5]
        case .cursor: return [1, 2.5]
        }
    }

    /// Stacked bars and areas leave a gap between tools so neighbouring shades never merge.
    var segmentGap: CGFloat { 1 }
}

struct TokenUsageToolMarker: View {
    let tool: TokenUsageTool
    let palette: TokenUsagePalette

    var body: some View {
        Group {
            switch tool {
            case .codex: Circle().fill(palette.color(tool))
            case .claudeCode: RoundedRectangle(cornerRadius: 1).fill(palette.color(tool))
            case .cursor: Triangle().fill(palette.color(tool))
            }
        }
        .frame(width: 7, height: 7)
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.closeSubpath()
            }
        }
    }
}

private struct TokenUsageSegmented<Item: Hashable, Label: View>: View {
    let items: [Item]
    let selection: Item
    let select: (Item) -> Void
    let accessibilityName: KeyPath<Item, String>
    @ViewBuilder let label: (Item) -> Label

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                Button { select(item) } label: {
                    label(item)
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .foregroundStyle(item == selection ? Color.primary : Color.secondary)
                        .background(item == selection ? Color.primary.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 4.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item[keyPath: accessibilityName])
                .accessibilityAddTraits(item == selection ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Charts

/// Neutral bars of a fixed shape, shown while the first reading loads.
private struct TokenUsagePlaceholderBars: View {
    let count: Int

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.16))
                        .frame(height: geometry.size.height * (0.3 + 0.25 * (1 + sin(Double(index) * 0.7)) / 2))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}

private struct TokenUsageBarsChart: View {
    let card: TokenUsageMenuCard
    let palette: TokenUsagePalette
    let hoveredDay: Int?

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.height / CGFloat(card.maximumDayTokenCount)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(card.days.indices, id: \.self) { index in
                    let emphasized = hoveredDay.map { $0 == index } ?? (index == card.days.count - 1)
                    VStack(spacing: palette.segmentGap) {
                        ForEach(card.tools.reversed(), id: \.tool) { series in
                            let value = card.tokenCount(for: series.tool, onDay: index)
                            if value > 0 {
                                Rectangle()
                                    .fill(palette.color(series.tool).opacity(emphasized ? 1 : 0.78))
                                    .frame(height: max(1, CGFloat(value) * scale))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .background(alignment: .bottom) {
                        if card.tokenCount(onDay: index) == 0 {
                            Rectangle().fill(Color.secondary.opacity(0.18)).frame(height: 3).clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct TokenUsageAreaChart: View {
    let card: TokenUsageMenuCard
    let palette: TokenUsagePalette

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .bottomLeading) {
                ForEach(Array(card.tools.indices.reversed()), id: \.self) { layer in
                    let tool = card.tools[layer].tool
                    let tops = layerTops(through: layer, in: size)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: size.height))
                        addSmoothCurve(through: tops, to: &path)
                        path.addLine(to: CGPoint(x: size.width, y: size.height))
                        path.closeSubpath()
                    }
                    .fill(palette.color(tool).opacity(palette.isSingleHue ? 1 : 0.85))
                    if palette.isSingleHue {
                        // The top edge of each layer keeps neighbouring shades apart.
                        Path { path in
                            path.move(to: tops[0])
                            addSmoothCurve(through: tops, to: &path)
                        }
                        .stroke(Color(nsColor: .windowBackgroundColor), style: StrokeStyle(lineWidth: 1, dash: palette.dash(tool)))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func layerTops(through layer: Int, in size: CGSize) -> [CGPoint] {
        let count = card.days.count
        let step = size.width / CGFloat(max(count - 1, 1))
        return card.days.indices.map { index in
            let cumulative = card.tools[...layer].reduce(0) { $0 + card.tokenCount(for: $1.tool, onDay: index) }
            return CGPoint(x: CGFloat(index) * step, y: size.height - size.height * CGFloat(cumulative) / CGFloat(card.maximumDayTokenCount))
        }
    }
}

/// One line per tool, each against its own busiest day, so a small tool keeps its shape.
private struct TokenUsageLinesChart: View {
    let card: TokenUsageMenuCard
    let palette: TokenUsagePalette

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                ForEach(card.tools.reversed(), id: \.tool) { series in
                    let points = linePoints(for: series.tool, in: size)
                    if points.count > 1 {
                        Path { path in
                            path.move(to: points[0])
                            addSmoothCurve(through: points, to: &path)
                        }
                        .stroke(palette.color(series.tool), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round, dash: palette.dash(series.tool)))
                    }
                    if let last = points.last {
                        TokenUsageToolMarker(tool: series.tool, palette: palette).position(last)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func linePoints(for tool: TokenUsageTool, in size: CGSize) -> [CGPoint] {
        let peak = CGFloat(card.maximumDayTokenCount(for: tool))
        let step = size.width / CGFloat(max(card.days.count - 1, 1))
        return card.days.indices.map { index in
            let value = CGFloat(card.tokenCount(for: tool, onDay: index))
            return CGPoint(x: CGFloat(index) * step, y: size.height - 4 - (size.height - 8) * value / peak)
        }
    }
}

private func addSmoothCurve(through points: [CGPoint], to path: inout Path) {
    guard let first = points.first else { return }
    path.addLine(to: first)
    for index in points.indices.dropFirst() {
        let previous = points[index - 1]
        let current = points[index]
        let midpoint = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
        path.addQuadCurve(to: midpoint, control: previous)
        if index == points.count - 1 {
            path.addQuadCurve(to: current, control: midpoint)
        }
    }
}

// MARK: - Splits

private struct TokenUsageShareBar: View {
    let parts: [(color: Color, share: Double)]
    let gap: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let gaps = gap * CGFloat(max(parts.count - 1, 0))
            HStack(spacing: gap) {
                ForEach(parts.indices, id: \.self) { index in
                    Rectangle()
                        .fill(parts[index].color)
                        .frame(width: max(2, (geometry.size.width - gaps) * parts[index].share))
                }
            }
        }
        .frame(height: 5)
        .clipShape(Capsule())
    }
}

private struct TokenUsageByToolSplit: View {
    let card: TokenUsageMenuCard
    let palette: TokenUsagePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(card.toolSummaries) { summary in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        TokenUsageToolMarker(tool: summary.tool, palette: palette)
                        Text(summary.tool.displayName).font(.system(size: 12, weight: .medium))
                        Spacer(minLength: 8)
                        trailing(for: summary)
                    }
                    .monospacedDigit()
                    if !summary.models.isEmpty {
                        TokenUsageShareBar(
                            parts: summary.models.enumerated().map { (palette.modelColor(summary.tool, index: $0.offset), $0.element.share) },
                            gap: 1.5
                        )
                        HStack(spacing: 10) {
                            ForEach(Array(summary.models.enumerated()), id: \.offset) { index, model in
                                HStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 1.5).fill(palette.modelColor(summary.tool, index: index)).frame(width: 7, height: 7)
                                    Text("\(model.name) \(TokenUsageMenuCard.percent(model.share))").lineLimit(1)
                                }
                            }
                        }
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func trailing(for summary: TokenUsageMenuCard.ToolSummary) -> some View {
        if summary.isUnavailable {
            Text("Unavailable").font(.system(size: 11)).foregroundStyle(.secondary)
        } else {
            Text("\(formattedShortTokenCount(summary.todayTokenCount)) today").font(.system(size: 11)).foregroundStyle(.secondary)
            Text(formattedShortTokenCount(summary.periodTokenCount))
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 44, alignment: .trailing)
        }
    }
}

private struct TokenUsageTopModelsSplit: View {
    let card: TokenUsageMenuCard
    let palette: TokenUsagePalette

    var body: some View {
        let models = card.topModels
        let largest = max(models.first?.tokenCount ?? 1, 1)
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                ForEach(card.toolSummaries) { summary in
                    HStack(spacing: 5) {
                        TokenUsageToolMarker(tool: summary.tool, palette: palette)
                        Text(summary.tool.displayName)
                        Text(shareText(for: summary)).foregroundStyle(.secondary)
                    }
                }
            }
            .font(.system(size: 11.5))
            .monospacedDigit()
            ForEach(Array(models.enumerated()), id: \.offset) { _, model in
                row(tool: model.tool, name: model.name, fraction: Double(model.tokenCount) / Double(largest), value: formattedShortTokenCount(model.tokenCount))
            }
        }
    }

    private func shareText(for summary: TokenUsageMenuCard.ToolSummary) -> String {
        if summary.isUnavailable { return "Unavailable" }
        return card.share(of: summary.tool).map(TokenUsageMenuCard.percent) ?? "…"
    }

    private func row(tool: TokenUsageTool, name: String, fraction: Double, value: String) -> some View {
        let marker = palette.color(tool)
        let dash = palette.dash(tool)
        return HStack(spacing: 8) {
            TokenUsageToolMarker(tool: tool, palette: palette).frame(width: 7)
            Text(name).font(.system(size: 12)).lineLimit(1).frame(width: 96, alignment: .leading)
            GeometryReader { geometry in
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geometry.size.height / 2))
                    path.addLine(to: CGPoint(x: max(3, geometry.size.width * fraction), y: geometry.size.height / 2))
                }
                .stroke(marker.opacity(palette.isSingleHue ? 0.9 : 0.5), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: dash.map { $0 * 1.5 }))
            }
            Text(value).font(.system(size: 12, weight: .medium)).monospacedDigit().lineLimit(1).fixedSize().frame(width: 54, alignment: .trailing)
        }
        .frame(height: 16)
    }
}

// MARK: - Tooltip

/// Shows the hovered day's tokens per tool as a native tooltip, and reports which day is hovered.
private struct TokenUsageTooltipOverlay: NSViewRepresentable {
    let dayCount: Int
    let text: (Int) -> String
    var onHover: (Int?) -> Void = { _ in }

    func makeNSView(context: Context) -> TokenUsageTooltipView {
        let view = TokenUsageTooltipView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: TokenUsageTooltipView, context: Context) {
        view.dayCount = dayCount
        view.text = text
        view.onHover = onHover
    }
}

private final class TokenUsageTooltipView: NSView {
    var dayCount = 0
    var text: (Int) -> String = { _ in "" }
    var onHover: (Int?) -> Void = { _ in }
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        guard !bounds.isEmpty else { return }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { update(for: event) }
    override func mouseMoved(with event: NSEvent) { update(for: event) }

    override func mouseExited(with event: NSEvent) {
        toolTip = nil
        onHover(nil)
    }

    private func update(for event: NSEvent) {
        guard dayCount > 0, bounds.width > 0 else { return }
        let x = convert(event.locationInWindow, from: nil).x
        let index = min(max(Int(floor(x / bounds.width * CGFloat(dayCount))), 0), dayCount - 1)
        toolTip = text(index)
        onHover(index)
    }
}
