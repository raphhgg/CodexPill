import Foundation

/// One tool's card in the main menu, and what its side menu offers. Codex, Claude and Cursor all use this shape.
struct ToolSection: Equatable {
    let provider: UsageProvider
    let planTag: String?
    let card: ToolCard
    /// Saved accounts, the one in use first. Labels are emails, masked when Hide Emails is on.
    let accounts: [ToolAccount]
    /// An action row under the card while its state lasts, such as "Allow Keychain access…".
    let followUp: ToolFollowUp?
    /// Whether "Add <Tool> Account…" can run the tool's own sign-in.
    var signInAvailability: ProviderSignInAvailability = .available

    var activeAccount: ToolAccount? {
        accounts.first(where: \.isActive)
    }

    var otherAccounts: [ToolAccount] {
        accounts.filter { !$0.isActive }
    }
}

/// What a card shows under its header: a state message, then the meters it still has, then extra lines.
struct ToolCard: Equatable {
    var title: String?
    /// One short line under the title, or "As of 10:26" for a reading that is not current.
    var detail: String?
    /// The windows that get a meter. A window the tool did not report has none.
    var windows: [UsageWindow] = []
    var isDimmed = false
    /// Reset credits on the active Codex account. Nil when there are none to use.
    var resetCredits: UsageResetCredits?
    var spend: UsageSpend?
}

struct ToolAccount: Equatable {
    let id: UUID
    let label: String
    let isActive: Bool
    /// The account's last limits on one line, such as "Session 12% · Weekly 40% used". Nil before the first read.
    var usageLine: String? = nil
}

struct ToolFollowUp: Equatable {
    let title: String
    let systemImage: String
    let action: ProviderAction
}

enum ToolSectionMove: CaseIterable {
    case toTop
    case up
    case down

    var title: String {
        switch self {
        case .toTop: "Move to Top"
        case .up: "Move Up"
        case .down: "Move Down"
        }
    }
}

extension MenuBarMenuState {
    /// One section per tool with a saved account or a connection, in the user's order.
    var toolSections: [ToolSection] {
        toolOrder.compactMap { provider in
            if provider == .codex {
                return codexSection
            }
            guard let usage = providerUsage.first(where: { $0.provider == provider }), usage.status != .notConnected else {
                return nil
            }
            return section(for: usage)
        }
    }

    /// The full tool order after moving `provider` past its visible neighbor, or nil when it can't move that way.
    func toolOrder(moving provider: UsageProvider, _ move: ToolSectionMove) -> [UsageProvider]? {
        let visible = toolSections.map(\.provider)
        guard let position = visible.firstIndex(of: provider) else { return nil }
        let neighbor: UsageProvider? = switch move {
        case .toTop: position > 0 ? visible[0] : nil
        case .up: position > 0 ? visible[position - 1] : nil
        case .down: position < visible.count - 1 ? visible[position + 1] : nil
        }
        guard let neighbor else { return nil }
        var order = toolOrder.filter { $0 != provider }
        guard let neighborIndex = order.firstIndex(of: neighbor) else { return nil }
        order.insert(provider, at: move == .down ? neighborIndex + 1 : neighborIndex)
        return order
    }

    /// What the side menu calls a saved account, so alerts name it the same way, Hide Emails included.
    func accountLabel(_ id: UUID, of provider: UsageProvider) -> String? {
        toolSections.first { $0.provider == provider }?.accounts.first { $0.id == id }?.label
    }

    /// A Codex reading older than two refreshes, and at least 15 minutes old, is stale.
    var codexStaleAfter: TimeInterval {
        max(15 * 60, TimeInterval(2 * refreshIntervalMinutes * 60))
    }

    private var codexSection: ToolSection? {
        guard !allSavedAccounts.isEmpty else { return nil }
        let accounts = accountLabels(allSavedAccounts.map { account in
            let planLabel = planTag(for: .codex, planName: account.effectivePlanType).map { "\($0) account" }
            return ProviderAccount(
                id: account.id,
                email: account.email,
                name: [account.identity.workspaceIdentity?.workspaceLabel, planLabel].compactMap(\.self).first { !$0.contains("@") },
                isActive: account.id == activeAccount?.id,
                usage: account.usage
            )
        })

        let card = if let activeAccount, let usage = activeAccount.usage {
            usageCard(usage, isStale: usage.freshness(at: now, staleAfter: codexStaleAfter) == .stale)
        } else if activeAccount != nil {
            ToolCard(title: "Waiting for Codex usage")
        } else {
            ToolCard(title: "No saved account in use", detail: "Pick one in this menu.")
        }
        return ToolSection(
            provider: .codex,
            planTag: activeAccount.flatMap { planTag(for: .codex, planName: $0.effectivePlanType) },
            card: card,
            accounts: accounts,
            followUp: nil
        )
    }

    private func section(for usage: ProviderUsageState) -> ToolSection {
        let copy = usage.provider.copy
        var card: ToolCard
        var followUp: ToolFollowUp?
        var snapshot: UsageSnapshot?

        if usage.isSigningIn {
            card = ToolCard(title: copy.signingInTitle)
            followUp = ToolFollowUp(title: "Cancel Sign-In", systemImage: "xmark.circle", action: .cancelSignIn)
        } else {
            switch usage.status {
            case .notConnected, .awaitingUsage:
                card = ToolCard(title: "Waiting for \(copy.name) usage")
            case let .current(current):
                snapshot = current
                card = usageCard(current, isStale: false)
            case let .stale(stale):
                snapshot = stale
                card = usageCard(stale, isStale: true)
            case let .unavailable(reason, lastSnapshot):
                snapshot = lastSnapshot
                let message = copy.unavailableMessage(for: reason)
                card = lastSnapshot.map { usageCard($0, isStale: true) } ?? ToolCard(detail: message.detail)
                card.title = message.title
                if reason == .keychainAccessNeeded {
                    followUp = ToolFollowUp(title: "Allow Keychain access…", systemImage: "key", action: .allowKeychainAccess)
                } else if [.signedOut, .signInUnreadable].contains(reason), usage.signInAvailability == .available, copy.offersSignInWhenSignedOut {
                    followUp = ToolFollowUp(title: "Sign In…", systemImage: "person.crop.circle", action: .addAccount)
                }
            }
        }

        let accounts = accountLabels(usage.accounts)
        return ToolSection(
            provider: usage.provider,
            planTag: snapshot.flatMap { planTag(for: usage.provider, planName: $0.planName) },
            card: card,
            accounts: accounts.filter(\.isActive) + accounts.filter { !$0.isActive },
            followUp: followUp,
            signInAvailability: usage.signInAvailability
        )
    }

    /// An account reads as its email, else its organization (or Codex plan), else "Saved account". Labels that would
    /// repeat get a number in saved order, so it does not move when the user switches: "Saved account", "Saved account 2".
    /// An organization name with an @ in it is skipped, because Claude names personal organizations after the email.
    private func accountLabels(_ accounts: [ProviderAccount]) -> [ToolAccount] {
        let baseLabels = accounts.map { account in
            if let email = account.email { return displayedEmail(email, masked: masksEmails) }
            if let name = account.name, !name.contains("@") { return name }
            return "Saved account"
        }
        var seen: [String: Int] = [:]
        return zip(accounts, baseLabels).map { account, label in
            seen[label, default: 0] += 1
            let count = seen[label] ?? 1
            return ToolAccount(
                id: account.id,
                label: count > 1 ? "\(label) \(count)" : label,
                isActive: account.isActive,
                usageLine: accountUsageLine(account.usage)
            )
        }
    }

    /// A saved account's limits for its side-menu item, in the user's % used or % left. A reading older than two
    /// inactive refreshes says when it was read: "Session 12% · Weekly 40% used · as of 10:26".
    func accountUsageLine(_ snapshot: UsageSnapshot?) -> String? {
        let windows = snapshot.map(displayedWindows) ?? []
        guard let snapshot, !windows.isEmpty else { return nil }
        let percents = windows.map { window in
            let used = window.displayedUsedPercent(at: now)
            return "\(window.kind.title) \(usagePercentMode == .used ? used : 100 - used)%"
        }
        var line = percents.joined(separator: " · ") + (usagePercentMode == .used ? " used" : " left")
        if snapshot.freshness(at: now, staleAfter: 2 * ProviderUsageRuntime.inactiveRefreshInterval) == .stale {
            line += " · as of \(usageAsOfText(snapshot.fetchedAt, now: now))"
        }
        return line
    }

    /// A reading that is not current keeps its meters, dimmed, under the time it was read.
    private func usageCard(_ snapshot: UsageSnapshot, isStale: Bool) -> ToolCard {
        ToolCard(
            detail: isStale ? "As of \(usageAsOfText(snapshot.fetchedAt, now: now))" : nil,
            windows: displayedWindows(snapshot),
            isDimmed: isStale,
            resetCredits: snapshot.resetCredits.flatMap { $0.availableCount > 0 ? $0 : nil },
            spend: snapshot.spend
        )
    }

    /// Claude's per-model limits show unless Show Model Limits is off.
    private func displayedWindows(_ snapshot: UsageSnapshot) -> [UsageWindow] {
        snapshot.displayedWindows.filter { showsModelLimits || !$0.kind.isModelLimit }
    }
}

extension UsageSnapshot {
    /// The windows the tool reported, shortest first. Codex Pro plans hide the 5-hour window, which they barely
    /// ever reach.
    var displayedWindows: [UsageWindow] {
        let hidesSession = provider == .codex && ["pro", "prolite"].contains(normalizedCodexPlanType(planName) ?? "")
        return windows.filter { !(hidesSession && $0.kind == .session) }
    }
}

extension UsageWindowKind {
    var title: String {
        switch self {
        case .session: "Session"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .billingCycle: "Billing cycle"
        case .other(let durationMinutes): lengthTitle(durationMinutes)
        case .modelWeekly(let modelName): "\(modelName) this week"
        }
    }

    /// The status bar title's label: "S", "W", "M", "B", or "8d" for a length with no name.
    var shortTitle: String {
        switch self {
        case .session, .weekly, .monthly, .billingCycle, .modelWeekly: String(title.prefix(1))
        case .other(let durationMinutes): shortLengthTitle(durationMinutes)
        }
    }
}

/// "8 days", "36 hours", "90 minutes": rounded to days from two days up, to hours from two hours up.
private func lengthTitle(_ durationMinutes: Int) -> String {
    let (count, unit) = lengthParts(durationMinutes)
    return "\(count) \(unit)\(count == 1 ? "" : "s")"
}

private func shortLengthTitle(_ durationMinutes: Int) -> String {
    let (count, unit) = lengthParts(durationMinutes)
    return "\(count)\(unit.prefix(1))"
}

private func lengthParts(_ durationMinutes: Int) -> (count: Int, unit: String) {
    let minutes = Double(durationMinutes)
    if durationMinutes >= 2 * 1_440 { return (Int((minutes / 1_440).rounded()), "day") }
    if durationMinutes >= 2 * 60 { return (Int((minutes / 60).rounded()), "hour") }
    return (durationMinutes, "minute")
}

/// The plan tag on a card: "Pro x20" for Codex, "Max x20" for Claude, "Pro" for Cursor. Nil when the plan is unknown.
func planTag(for provider: UsageProvider, planName: String?) -> String? {
    guard let planName = planName?.trimmingCharacters(in: .whitespacesAndNewlines), !planName.isEmpty else { return nil }
    if provider == .codex {
        let name = displayNameForCodexPlanType(planName)
        return name == "Unknown" ? nil : name
    }
    let parts = planName.lowercased().split(separator: "_")
    let tier = parts.first { $0.hasSuffix("x") && Int($0.dropLast()) != nil }
    let name = parts.filter { $0 != tier }.map(\.capitalized).joined(separator: " ")
    return name + (tier.map { " x\($0.dropLast())" } ?? "")
}

/// Hidden emails keep the first and last characters before the @, and the domain, so similar accounts stay apart:
/// "alex.side@example.com" reads "al•••e@example.com", "alex@example.com" reads "a•••x@example.com".
func displayedEmail(_ email: String, masked: Bool) -> String {
    guard masked, let at = email.firstIndex(of: "@") else { return email }
    let local = email[..<at]
    let visible: Substring = switch local.count {
    case 0...2: local.prefix(1) + "•••"
    case 3...4: local.prefix(1) + "•••" + local.suffix(1)
    default: local.prefix(2) + "•••" + local.suffix(1)
    }
    return String(visible + email[at...])
}
