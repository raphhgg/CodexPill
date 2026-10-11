import Foundation

func displayedPercent(of window: UsageWindow, mode: UsagePercentMode, now: Date = .now) -> Int {
    mode.percent(forUsedPercent: window.displayedUsedPercent(at: now))
}

func usageMeterPercentText(for window: UsageWindow, mode: UsagePercentMode, now: Date = .now) -> String {
    "\(displayedPercent(of: window, mode: mode, now: now))% \(mode.label)"
}

func resetStatusText(
    for window: UsageWindow,
    now: Date,
    locale: Locale = .autoupdatingCurrent,
    timeZone: TimeZone = .autoupdatingCurrent
) -> String? {
    guard let resetsAt = window.resetsAt else { return nil }
    if resetsAt <= now {
        return nil
    }

    // A reset more than a week away reads better as a date than a countdown, and so does any billing cycle's.
    if window.kind == .billingCycle || resetsAt.timeIntervalSince(now) > 7 * 24 * 60 * 60 {
        return "Resets \(shortDate(resetsAt, locale: locale, timeZone: timeZone))"
    }
    return "Resets in \(cardResetText(until: resetsAt, now: now))"
}

func expectedRateLimitUsagePercent(for window: UsageWindow, now: Date = .now) -> Int? {
    guard let resetsAt = window.resetsAt,
          resetsAt > now,
          let durationMinutes = window.durationMinutes,
          durationMinutes > 0 else {
        return nil
    }

    let totalSeconds = Double(durationMinutes * 60)
    let remainingSeconds = min(max(resetsAt.timeIntervalSince(now), 0), totalSeconds)
    let elapsedPercent = ((totalSeconds - remainingSeconds) / totalSeconds) * 100
    return min(max(Int(elapsedPercent.rounded()), 0), 100)
}

func expectedPaceMarkerPercent(
    for window: UsageWindow?,
    showsPacingMarkers: Bool,
    percentMode: UsagePercentMode = .used,
    now: Date = .now
) -> Int? {
    guard showsPacingMarkers, let window else { return nil }
    return expectedRateLimitUsagePercent(for: window, now: now).map(percentMode.percent(forUsedPercent:))
}

/// What the menu bar icon follows: the first tool section, or nothing when no tool is set up.
enum StatusItemSource: Equatable {
    case nothingConnected
    case tool(ToolSection)

    var windows: [UsageWindow] {
        guard case let .tool(section) = self else { return [] }
        return section.card.windows
    }
}

/// Two windows fill both meters. A single window, such as Codex Pro's weekly limit, a free plan's monthly limit,
/// or Cursor's billing cycle, fills the lower meter and leaves the upper one missing.
func statusItemBarPercents(
    for windows: [UsageWindow],
    mode: UsagePercentMode,
    now: Date = .now
) -> (primary: Int?, secondary: Int?) {
    let percents = windows.prefix(2).map { displayedPercent(of: $0, mode: mode, now: now) }
    return switch percents.count {
    case 0: (nil, nil)
    case 1: (nil, percents[0])
    default: (percents[0], percents[1])
    }
}

/// "S 11% W 60%" or "M 4%", one segment per window. A full window shows its countdown instead.
/// A billing cycle alone reads "82%".
func statusItemTitle(for windows: [UsageWindow], percentMode: UsagePercentMode = .used, now: Date = .now) -> String {
    let segments = windows.map { window in
        let value = if window.displayedUsedPercent(at: now) >= 100, let resetsAt = window.resetsAt, resetsAt > now {
            relativeResetText(until: resetsAt, now: now)
        } else {
            "\(displayedPercent(of: window, mode: percentMode, now: now))%"
        }
        return windows.count == 1 && window.kind == .billingCycle ? value : "\(window.kind.shortTitle) \(value)"
    }
    return segments.isEmpty ? "--" : segments.joined(separator: " ")
}

func statusItemTooltipText(for source: StatusItemSource, now: Date = .now) -> String {
    guard case let .tool(section) = source else { return "Refill" }
    var lines = [[section.provider.copy.sectionTitle, section.planTag].compactMap(\.self).joined(separator: " · ")]
    if let account = section.activeAccount {
        lines.append(account.label)
    }
    for window in section.card.windows where window.displayedUsedPercent(at: now) >= 100 {
        if let reset = tooltipResetStatusText(for: window, now: now) {
            lines.append("\(window.kind.title) \(reset.lowercased())")
        }
    }
    return lines.joined(separator: "\n")
}

private func compactHourMinuteText(until futureDate: Date, now: Date) -> String {
    let remainingSeconds = max(0, Int(ceil(futureDate.timeIntervalSince(now))))
    let totalMinutes = max(1, Int(ceil(Double(remainingSeconds) / 60)))
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    return "\(hours)h\(String(format: "%02d", minutes))"
}

private func cardResetText(until futureDate: Date, now: Date) -> String {
    let remainingSeconds = max(0, Int(ceil(futureDate.timeIntervalSince(now))))
    let hour = 60 * 60
    let day = 24 * hour

    if remainingSeconds < hour {
        let minutes = max(1, Int(ceil(Double(remainingSeconds) / 60)))
        return "\(minutes)min"
    }

    if remainingSeconds < day {
        let totalMinutes = max(1, Int(ceil(Double(remainingSeconds) / 60)))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h\(String(format: "%02d", minutes))"
    }

    let days = max(1, remainingSeconds / day)
    return "\(days)d"
}

private func relativeResetText(until futureDate: Date, now: Date) -> String {
    let remainingSeconds = max(0, Int(ceil(futureDate.timeIntervalSince(now))))
    let hour = 60 * 60
    let day = 24 * hour

    if remainingSeconds < hour {
        let minutes = max(1, Int(ceil(Double(remainingSeconds) / 60)))
        return "\(minutes)min"
    }

    if remainingSeconds < day {
        return compactHourMinuteText(until: futureDate, now: now)
    }

    let days = max(1, remainingSeconds / day)
    return "\(days)d"
}

private func tooltipResetStatusText(for window: UsageWindow, now: Date) -> String? {
    guard let resetsAt = window.resetsAt, resetsAt > now else { return nil }
    return "Resets in \(relativeResetText(until: resetsAt, now: now))"
}
