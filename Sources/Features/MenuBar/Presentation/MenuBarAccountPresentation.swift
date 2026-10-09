import AppKit
import Foundation

enum MenuBarAccountPlacement: Equatable {
    case local
    case remote
    case localAndRemote

    var badgeText: String {
        switch self {
        case .local:
            return "Local"
        case .remote:
            return "Remote"
        case .localAndRemote:
            return "Local • Remote"
        }
    }
}

func menuPlanDisplayName(_ planType: String?) -> String {
    displayNameForCodexPlanType(planType)
}

func inactiveAccountTitle(
    for account: CodexAccount,
    displayName: String? = nil,
    placement: MenuBarAccountPlacement? = nil,
    menuContentWidth: CGFloat = 340,
    percentMode: UsagePercentMode = .used,
    now: Date = .now
) -> NSAttributedString {
    let paragraphStyle = NSMutableParagraphStyle()
    let badgeColumnLocation = max(220, menuContentWidth - 28)
    paragraphStyle.tabStops = [
        NSTextTab(textAlignment: .right, location: badgeColumnLocation)
    ]

    let title = NSMutableAttributedString()
    title.append(NSAttributedString(
        string: displayName ?? account.name,
        attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
    ))

    title.append(NSAttributedString(
        string: "  \(compactMenuRowUsageSummary(for: account, percentMode: percentMode, now: now))",
        attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]
    ))

    if let placement {
        title.append(NSAttributedString(
            string: "\t\(placement.badgeText)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .paragraphStyle: paragraphStyle
            ]
        ))
    }

    return title
}

func inactiveAccountTitleWidth(
    for account: CodexAccount,
    displayName: String? = nil,
    placement: MenuBarAccountPlacement? = nil,
    menuContentWidth: CGFloat = 340,
    percentMode: UsagePercentMode = .used,
    now: Date = .now
) -> CGFloat {
    let title = inactiveAccountTitle(
        for: account,
        displayName: displayName,
        placement: placement,
        menuContentWidth: menuContentWidth,
        percentMode: percentMode,
        now: now
    )
    let bounds = title.boundingRect(
        with: NSSize(width: 10_000, height: 1_000),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    return ceil(bounds.width)
}

func compactMenuRowDisplayName(for accountName: String, maxLength: Int = 20) -> String {
    let trimmed = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > maxLength, maxLength > 1 else {
        return trimmed
    }

    return "\(trimmed.prefix(maxLength - 1))…"
}

func compactMenuRowUsageSummary(
    for account: CodexAccount,
    percentMode: UsagePercentMode = .used,
    now: Date = .now
) -> String {
    let session = compactLimitDetail(prefix: "S", window: account.usage?.window(.session), percentMode: percentMode, now: now)
    let weekly = compactLimitDetail(prefix: "W", window: account.usage?.window(.weekly), percentMode: percentMode, now: now)
    return "\(session)  \(weekly)"
}

func compactElapsedTime(since date: Date, now: Date = .now) -> String {
    let elapsedSeconds = max(0, Int(now.timeIntervalSince(date).rounded(.down)))
    if elapsedSeconds < 60 {
        return "\(elapsedSeconds)sec"
    }

    let elapsedMinutes = elapsedSeconds / 60
    if elapsedMinutes < 60 {
        return "\(elapsedMinutes)min"
    }

    let elapsedHours = elapsedMinutes / 60
    if elapsedHours < 24 {
        return "\(elapsedHours)h"
    }

    return "\(elapsedHours / 24)d"
}

private func compactLimitDetail(
    prefix: String,
    window: UsageWindow?,
    percentMode: UsagePercentMode,
    now: Date
) -> String {
    let percentText = window.map { "\(displayedPercent(of: $0, mode: percentMode, now: now))%" } ?? "--"
    if window?.displayedUsedPercent(at: now) == 0 {
        return "\(prefix) \(percentText)"
    }
    guard let window, let resetText = compactResetText(for: window, now: now) else {
        return "\(prefix) \(percentText)"
    }
    return "\(prefix) \(percentText) (\(resetText))"
}

func displayedPercent(of window: UsageWindow, mode: UsagePercentMode, now: Date = .now) -> Int {
    mode.percent(forUsedPercent: window.displayedUsedPercent(at: now))
}

func usageMeterPercentText(for window: UsageWindow?, mode: UsagePercentMode, now: Date = .now) -> String {
    guard let window else { return "--" }
    return "\(displayedPercent(of: window, mode: mode, now: now))% \(mode.label)"
}

func statusItemBarPercents(
    for account: CodexAccount?,
    mode: UsagePercentMode,
    now: Date = .now
) -> (session: Int?, weekly: Int?) {
    (
        session: account?.usage?.window(.session).map { displayedPercent(of: $0, mode: mode, now: now) },
        weekly: account?.usage?.window(.weekly).map { displayedPercent(of: $0, mode: mode, now: now) }
    )
}

func resetStatusText(for window: UsageWindow) -> String? {
    resetStatusText(for: window, now: .now)
}

func resetStatusText(for window: UsageWindow, now: Date) -> String? {
    guard let resetsAt = window.resetsAt else { return nil }
    if resetsAt <= now {
        return nil
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

func statusItemTooltipText(for account: CodexAccount?, now: Date = .now) -> String? {
    guard let account else { return nil }

    var lines = [account.name]

    if let email = account.email, !email.isEmpty {
        lines.append(email)
    }

    lines.append(menuPlanDisplayName(account.effectivePlanType))

    if let session = account.usage?.window(.session),
       session.displayedUsedPercent(at: now) >= 100,
       let reset = tooltipResetStatusText(for: session, now: now) {
        lines.append("Session \(reset.lowercased())")
    }

    if let weekly = account.usage?.window(.weekly),
       weekly.displayedUsedPercent(at: now) >= 100,
       let reset = tooltipResetStatusText(for: weekly, now: now) {
        lines.append("Weekly \(reset.lowercased())")
    }

    return lines.joined(separator: "\n")
}

func statusItemHoverTitle(
    for account: CodexAccount?,
    percentMode: UsagePercentMode = .used,
    now: Date = .now
) -> String {
    let session = hoverStatusSegment(prefix: "S", window: account?.usage?.window(.session), percentMode: percentMode, now: now)
    let weekly = hoverStatusSegment(prefix: "W", window: account?.usage?.window(.weekly), percentMode: percentMode, now: now)
    return "\(session) \(weekly)"
}

private func hoverStatusSegment(
    prefix: String,
    window: UsageWindow?,
    percentMode: UsagePercentMode,
    now: Date
) -> String {
    guard let window else { return "\(prefix) --" }
    if window.displayedUsedPercent(at: now) >= 100, let resetsAt = window.resetsAt, resetsAt > now {
        return "\(prefix) \(relativeResetText(until: resetsAt, now: now))"
    }
    return "\(prefix) \(displayedPercent(of: window, mode: percentMode, now: now))%"
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

func compactResetText(for window: UsageWindow, now: Date = .now) -> String? {
    guard let resetsAt = window.resetsAt, resetsAt > now else { return nil }
    return relativeResetText(until: resetsAt, now: now)
}
