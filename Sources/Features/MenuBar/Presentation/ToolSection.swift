import Foundation

/// One tool's card in the main menu, and what its side menu offers. Codex, Claude and Cursor all use this shape.
struct ToolSection: Equatable {
    let provider: UsageProvider
    let planTag: String?
    let card: ToolCard
    /// Saved Codex accounts, labeled by email, masked when Hide Emails is on. Claude and Cursor have none.
    let accounts: [ToolAccount]
    /// An action row under the card while its state lasts, such as "Allow Keychain access…".
    let followUp: ToolFollowUp?

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

    /// A Codex reading older than two refreshes, and at least 15 minutes old, is stale.
    var codexStaleAfter: TimeInterval {
        max(15 * 60, TimeInterval(2 * refreshIntervalMinutes * 60))
    }

    private var codexSection: ToolSection? {
        guard !allSavedAccounts.isEmpty else { return nil }
        let accounts = allSavedAccounts.map { account in
            ToolAccount(
                id: account.id,
                label: account.email.map { displayedEmail($0, masked: masksEmails) } ?? account.name,
                isActive: account.id == activeAccount?.id
            )
        }

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
            card = ToolCard(title: "Finish signing in in your browser")
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
                }
            }
        }

        return ToolSection(
            provider: usage.provider,
            planTag: snapshot.flatMap { planTag(for: usage.provider, planName: $0.planName) },
            card: card,
            accounts: [],
            followUp: followUp
        )
    }

    /// A reading that is not current keeps its meters, dimmed, under the time it was read.
    private func usageCard(_ snapshot: UsageSnapshot, isStale: Bool) -> ToolCard {
        ToolCard(
            detail: isStale ? "As of \(usageAsOfText(snapshot.fetchedAt, now: now))" : nil,
            windows: snapshot.displayedWindows,
            isDimmed: isStale,
            resetCredits: snapshot.resetCredits.flatMap { $0.availableCount > 0 ? $0 : nil },
            spend: snapshot.spend
        )
    }
}

extension UsageSnapshot {
    /// Windows in menu order. Codex Pro plans hide the 5-hour window, which they barely ever reach.
    var displayedWindows: [UsageWindow] {
        let hidesSession = provider == .codex && ["pro", "prolite"].contains(normalizedCodexPlanType(planName) ?? "")
        let kinds: [UsageWindowKind] = hidesSession ? [.weekly, .billingCycle] : [.session, .weekly, .billingCycle]
        return kinds.compactMap(window)
    }
}

extension UsageWindowKind {
    var title: String {
        switch self {
        case .session: "Session"
        case .weekly: "Weekly"
        case .billingCycle: "Billing cycle"
        }
    }
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
