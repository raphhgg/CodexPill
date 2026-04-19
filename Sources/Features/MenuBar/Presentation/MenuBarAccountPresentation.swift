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
    switch planType?.lowercased() {
    case "plus":
        return "Plus"
    case "pro":
        return "Pro"
    case "team":
        return "Team"
    case .some(let value) where !value.isEmpty:
        return value.capitalized
    default:
        return "Unknown"
    }
}

func inactiveAccountTitle(
    for account: CodexAccount,
    displayName: String? = nil,
    placement: MenuBarAccountPlacement? = nil,
    menuContentWidth: CGFloat = 340,
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
        string: "  \(compactMenuRowUsageSummary(for: account, now: now))",
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
    now: Date = .now
) -> CGFloat {
    let title = inactiveAccountTitle(
        for: account,
        displayName: displayName,
        placement: placement,
        menuContentWidth: menuContentWidth,
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

func compactAccountUsageSummary(for account: CodexAccount, now: Date = .now) -> String {
    let session = compactLimitDetail(prefix: "S", window: account.rateLimits?.primary, now: now)
    let weekly = compactLimitDetail(prefix: "W", window: account.rateLimits?.secondary, now: now)
    return "\(session) • \(weekly)"
}

func compactMenuRowUsageSummary(for account: CodexAccount, now: Date = .now) -> String {
    let session = compactLimitDetail(prefix: "S", window: account.rateLimits?.primary, now: now)
    let weekly = compactLimitDetail(prefix: "W", window: account.rateLimits?.secondary, now: now)
    return "\(session)  \(weekly)"
}

private func compactLimitDetail(prefix: String, window: CodexRateLimitWindow?, now: Date) -> String {
    let usedText = window.map { "\($0.displayedUsedPercent(at: now))%" } ?? "--"
    guard let window, let resetText = compactResetText(for: window, now: now) else {
        return "\(prefix) \(usedText)"
    }
    return "\(prefix) \(usedText) (\(resetText))"
}

func resetStatusText(for window: CodexRateLimitWindow) -> String? {
    resetStatusText(for: window, now: .now)
}

func resetStatusText(for window: CodexRateLimitWindow, now: Date) -> String? {
    guard let resetsAt = window.resetsAt else { return nil }
    if resetsAt <= now {
        return nil
    }

    return "Resets in \(cardResetText(until: resetsAt, now: now))"
}

func statusItemTooltipText(for account: CodexAccount?, now: Date = .now) -> String? {
    guard let account else { return nil }

    var lines = [account.name]

    if let email = account.email, !email.isEmpty {
        lines.append(email)
    }

    lines.append(menuPlanDisplayName(account.planType))

    if let primary = account.rateLimits?.primary,
       primary.displayedUsedPercent(at: now) >= 100,
       let reset = tooltipResetStatusText(for: primary, now: now) {
        lines.append("Session \(reset.lowercased())")
    }

    if let secondary = account.rateLimits?.secondary,
       secondary.displayedUsedPercent(at: now) >= 100,
       let reset = tooltipResetStatusText(for: secondary, now: now) {
        lines.append("Weekly \(reset.lowercased())")
    }

    return lines.joined(separator: "\n")
}

func statusItemHoverTitle(for account: CodexAccount?, now: Date = .now) -> String {
    let session = hoverStatusSegment(prefix: "S", window: account?.rateLimits?.primary, now: now)
    let weekly = hoverStatusSegment(prefix: "W", window: account?.rateLimits?.secondary, now: now)
    return "\(session) \(weekly)"
}

private func hoverStatusSegment(prefix: String, window: CodexRateLimitWindow?, now: Date) -> String {
    guard let window else { return "\(prefix) --" }
    if window.displayedUsedPercent(at: now) >= 100, let resetsAt = window.resetsAt, resetsAt > now {
        return "\(prefix) \(relativeResetText(until: resetsAt, now: now))"
    }
    return "\(prefix) \(window.displayedUsedPercent(at: now))%"
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

private func tooltipResetStatusText(for window: CodexRateLimitWindow, now: Date) -> String? {
    guard let resetsAt = window.resetsAt, resetsAt > now else { return nil }
    return "Resets in \(relativeResetText(until: resetsAt, now: now))"
}

func compactResetText(for window: CodexRateLimitWindow, now: Date = .now) -> String? {
    guard let resetsAt = window.resetsAt, resetsAt > now else { return nil }
    return relativeResetText(until: resetsAt, now: now)
}
