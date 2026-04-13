import AppKit

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
    guard let resetsAt = window.resetsAt else { return nil }

    let now = Date()
    if resetsAt <= now {
        return nil
    }

    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return "Resets \(formatter.localizedString(for: resetsAt, relativeTo: now))"
}
