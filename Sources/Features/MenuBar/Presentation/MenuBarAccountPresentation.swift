import AppKit
import Foundation

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

func inactiveAccountTitle(for account: CodexAccount) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 1
    paragraph.paragraphSpacing = 2

    let title = NSMutableAttributedString(
        string: "\(account.name)\n",
        attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    )

    let secondary = detailLine(title: "Session", window: account.rateLimits?.primary) + "\n"
    title.append(NSAttributedString(
        string: secondary,
        attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
    ))

    let tertiary = detailLine(title: "Weekly", window: account.rateLimits?.secondary)
    title.append(NSAttributedString(
        string: tertiary,
        attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
    ))

    return title
}

private func detailLine(title: String, window: CodexRateLimitWindow?) -> String {
    let usedText = window.map { "\($0.displayedUsedPercent())%" } ?? "--"
    if let window, window.displayedUsedPercent() == 0 {
        return "\(title): \(usedText)"
    }
    guard let window, let resetStatus = resetStatusText(for: window) else {
        return "\(title): \(usedText)"
    }
    return "\(title): \(usedText) • \(resetStatus)"
}

func resetStatusText(for window: CodexRateLimitWindow) -> String? {
    resetStatusText(for: window, now: .now)
}

func resetStatusText(for window: CodexRateLimitWindow, now: Date) -> String? {
    guard let resetsAt = window.resetsAt else { return nil }
    if resetsAt <= now {
        return nil
    }

    return "Resets in \(relativeResetText(until: resetsAt, now: now))"
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
       let reset = resetStatusText(for: primary, now: now) {
        lines.append("Session \(reset.lowercased())")
    }

    if let secondary = account.rateLimits?.secondary,
       secondary.displayedUsedPercent(at: now) >= 100,
       let reset = resetStatusText(for: secondary, now: now) {
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
        return "\(prefix) \(countdownText(until: resetsAt, now: now))"
    }
    return "\(prefix) \(window.displayedUsedPercent(at: now))%"
}

private func countdownText(until futureDate: Date, now: Date) -> String {
    let remainingSeconds = max(0, Int(ceil(futureDate.timeIntervalSince(now))))
    let totalMinutes = max(1, Int(ceil(Double(remainingSeconds) / 60)))
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    return String(format: "%02d:%02d", hours, minutes)
}

private func relativeResetText(until futureDate: Date, now: Date) -> String {
    let remainingSeconds = max(0, Int(ceil(futureDate.timeIntervalSince(now))))
    let minute = 60
    let hour = 60 * minute
    let day = 24 * hour

    if remainingSeconds < hour {
        let minutes = max(1, Int(ceil(Double(remainingSeconds) / Double(minute))))
        return "\(minutes) min"
    }

    if remainingSeconds < day {
        let hours = max(1, remainingSeconds / hour)
        return "\(hours) hr"
    }

    let days = max(1, remainingSeconds / day)
    return "\(days) days"
}
