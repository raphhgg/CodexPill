import Foundation

/// One tool's card in the main menu, and what its side menu offers. Codex, Claude and Cursor all use this shape.
struct ToolSection: Equatable {
    let provider: UsageProvider
    let planTag: String?
    let card: ToolCard
    /// An action row under the card while its state lasts, such as "Allow Keychain Access…".
    let followUp: ToolFollowUp?
    /// Where the sign-in comes from when rusage reads the tool's own, such as "From Claude Code". Nil for rusage's
    /// own sign-in and for Codex.
    var signInSourceCaption: String? = nil
    /// The account the tool is signed in to, by email, masked when Hide Emails is on.
    var signedInLabel: String? = nil
    /// Whether the tool reads with rusage's own sign-in, for a tool that has one.
    var ownSignIn: ProviderOwnSignIn = .unsupported

    /// What the side menu and the tooltip call the account in use.
    var activeLabel: String? {
        signedInLabel
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
    var credits: UsageCredits?
}

struct ToolFollowUp: Equatable {
    let title: String
    let systemImage: String
    let action: ProviderAction
}

extension MenuBarMenuState {
    /// One section per tool that is signed in or connected, in the user's order. Codex can be hidden.
    var toolSections: [ToolSection] {
        toolOrder.compactMap { provider in
            if provider == .codex {
                return codexSection
            }
            guard let usage = providerUsage.first(where: { $0.provider == provider }), usage.status != .notConnected, usage.isShown else {
                return nil
            }
            return section(for: usage)
        }
    }

    /// A Codex reading older than two refreshes, and at least 15 minutes old, is stale.
    var codexStaleAfter: TimeInterval {
        max(15 * 60, TimeInterval(2 * refreshIntervalMinutes * 60))
    }

    private var codexSection: ToolSection? {
        guard !hidesCodex, let activeAccount else { return nil }
        let card = if let usage = activeAccount.usage {
            usageCard(usage, isStale: usage.freshness(at: now, staleAfter: codexStaleAfter) == .stale)
        } else {
            ToolCard(title: "Waiting for Codex usage")
        }
        return ToolSection(
            provider: .codex,
            planTag: planTag(for: .codex, planName: activeAccount.effectivePlanType),
            card: card,
            followUp: nil,
            signedInLabel: codexAccountLabel(activeAccount)
        )
    }

    private func section(for usage: ProviderUsageState) -> ToolSection {
        let copy = usage.provider.copy
        var card: ToolCard
        var followUp: ToolFollowUp?
        var snapshot: UsageSnapshot?

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
            // The sign-in is still there, so the last numbers stay under their time instead of an error.
            if reason != .keychainAccessNeeded || lastSnapshot == nil {
                card.title = message.title
            }
            if reason == .keychainAccessNeeded {
                followUp = ToolFollowUp(title: "Allow Keychain Access…", systemImage: "key", action: .allowKeychainAccess)
            } else if usage.ownSignIn != .unsupported, [.signedOut, .signInExpired, .signInRequired].contains(reason) {
                followUp = ToolFollowUp(title: "Sign in with \(copy.sectionTitle)…", systemImage: "person.crop.circle", action: .signIn)
            }
        }
        return ToolSection(
            provider: usage.provider,
            planTag: snapshot.flatMap { planTag(for: usage.provider, planName: $0.planName) },
            card: card,
            followUp: followUp,
            signInSourceCaption: usage.ownSignIn != .signedIn && snapshot != nil ? copy.toolSignInCaption : nil,
            signedInLabel: snapshot?.accountEmail.map { displayedEmail($0, masked: masksEmails) },
            ownSignIn: usage.ownSignIn
        )
    }

    /// The Codex account reads as its email, else its workspace or plan. A workspace name with an @ in it is skipped.
    private func codexAccountLabel(_ account: CodexAccount) -> String {
        if let email = account.email { return displayedEmail(email, masked: masksEmails) }
        let planLabel = planTag(for: .codex, planName: account.effectivePlanType).map { "\($0) account" }
        let name = [account.identity.workspaceIdentity?.workspaceLabel, planLabel].compactMap(\.self).first { !$0.contains("@") }
        return name ?? "Codex account"
    }

    /// A reading that is not current keeps its meters, dimmed, under the time it was read.
    private func usageCard(_ snapshot: UsageSnapshot, isStale: Bool) -> ToolCard {
        ToolCard(
            detail: isStale ? "As of \(usageAsOfText(snapshot.fetchedAt, now: now))" : nil,
            windows: displayedWindows(snapshot),
            isDimmed: isStale,
            resetCredits: snapshot.resetCredits.flatMap { $0.availableCount > 0 ? $0 : nil },
            credits: snapshot.credits
        )
    }

    /// Claude's per-model limits show unless their toggle in the Claude side menu is off.
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
