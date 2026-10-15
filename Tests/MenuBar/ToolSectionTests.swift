import Foundation
import Testing

@testable import Refill

struct ToolSectionTests {
    private let now = Date(timeIntervalSince1970: 1_791_000_000)

    @Test
    func sectionsFollowTheUserOrderAndSkipToolsWithNoAccountOrConnection() {
        let codex = makeAccount(name: "Work", usage: makeUsage(fetchedAt: now))
        let claude = ProviderUsageState(provider: .claude, status: .current(claudeSnapshot()))
        let cursor = ProviderUsageState(provider: .cursor, status: .notConnected)

        let defaultOrder = state(activeAccount: codex, providerUsage: [claude, cursor])
        let reordered = state(activeAccount: codex, providerUsage: [claude, cursor], toolOrder: [.cursor, .codex, .claude])
        let codexOnly = state(activeAccount: codex)
        let nothing = state()

        #expect(defaultOrder.toolSections.map(\.provider) == [.claude, .codex])
        #expect(reordered.toolSections.map(\.provider) == [.codex, .claude])
        #expect(codexOnly.toolSections.map(\.provider) == [.codex])
        #expect(nothing.toolSections.isEmpty)
        #expect(nothing.statusItemSource == .nothingConnected)
        #expect(reordered.statusItemSource == .tool(reordered.toolSections[0]))
    }

    @Test
    func aMissingWindowGetsNoMeterAndCodexProHidesTheSessionWindow() throws {
        let plus = makeAccount(name: "Plus", planType: "plus", usage: UsageSnapshot.codex(
            planName: "plus",
            primary: nil,
            secondary: (usedPercent: 17, resetsAt: now.addingTimeInterval(3 * 86_400), durationMinutes: 10_080),
            fetchedAt: now
        ))
        let pro = makeAccount(name: "Pro", planType: "pro", usage: makeUsage(planType: "pro", fetchedAt: now))

        let plusCard = try #require(state(activeAccount: plus).toolSections.first).card
        let proSection = try #require(state(activeAccount: pro).toolSections.first)

        #expect(plusCard.windows.map(\.kind) == [.weekly])
        #expect(proSection.card.windows.map(\.kind) == [.weekly])
        #expect(proSection.planTag == "Pro x20")
        #expect(state(activeAccount: pro).hasStatusItemContentData)
    }

    @Test
    func codexResetCreditsShowOnlyWhenOneIsAvailable() throws {
        func card(credits: UsageResetCredits) throws -> ToolCard {
            var usage = makeUsage(fetchedAt: now)
            usage.resetCredits = credits
            return try #require(state(activeAccount: makeAccount(name: "Work", usage: usage)).toolSections.first).card
        }
        let nov5 = Date(timeIntervalSince1970: 1_793_880_000)
        let nov20 = nov5.addingTimeInterval(15 * 86_400)
        let two = UsageResetCredits(availableCount: 2, credits: [UsageResetCredit(expiresAt: nov20), UsageResetCredit(expiresAt: nov5)])
        let one = UsageResetCredits(availableCount: 1, credits: [UsageResetCredit(expiresAt: nov5)])
        let countOnly = UsageResetCredits(availableCount: 3, credits: nil)
        let gb = Locale(identifier: "en_GB")
        let gmt = TimeZone(identifier: "GMT")!

        #expect(try card(credits: two).resetCredits == two)
        #expect(try card(credits: UsageResetCredits(availableCount: 0, credits: [])).resetCredits == nil)
        #expect(resetCreditsCountText(two) == "2 resets available")
        #expect(resetCreditsExpiryText(two, locale: gb, timeZone: gmt) == "Next expires 5 Nov")
        #expect(resetCreditsCountText(one) == "1 reset available")
        #expect(resetCreditsExpiryText(one, locale: gb, timeZone: gmt) == "Expires 5 Nov")
        #expect(resetCreditsExpiryText(countOnly, locale: gb, timeZone: gmt) == nil)
    }

    @Test
    func codexStatesReadAsATitleAndAtMostOneLine() throws {
        let waiting = try #require(state(activeAccount: makeAccount(name: "Work")).toolSections.first).card
        let noneInUse = try #require(state(inactiveAccounts: [makeAccount(name: "Work")]).toolSections.first).card
        let staleUsage = makeUsage(fetchedAt: now.addingTimeInterval(-20 * 60))
        let stale = try #require(state(activeAccount: makeAccount(name: "Work", usage: staleUsage)).toolSections.first).card
        let fresh = try #require(state(activeAccount: makeAccount(name: "Work", usage: makeUsage(fetchedAt: now))).toolSections.first).card

        #expect(waiting == ToolCard(title: "Waiting for Codex usage"))
        #expect(noneInUse == ToolCard(title: "No saved account in use", detail: "Pick one in this menu."))
        #expect(stale.title == nil)
        #expect(stale.detail?.hasPrefix("As of ") == true)
        #expect(stale.isDimmed)
        #expect(stale.windows.count == 2)
        #expect(fresh.title == nil && fresh.detail == nil && !fresh.isDimmed)
    }

    @Test(arguments: [
        (UsageProvider.claude, UsageUnavailableReason.unreachable, "Can't reach Anthropic", "Retrying in a few minutes."),
        (.claude, .rateLimited, "Anthropic asked to wait", "Retrying in a few minutes."),
        (.claude, .signInExpired, "Sign-in expired", "Sign in to keep your limits current."),
        (.claude, .signedOut, "Not signed in", "Sign in to see your limits."),
        (.claude, .keychainAccessNeeded, "Allow Keychain access", nil),
        (.claude, .signInRequired, "Sign in again", nil),
        (.cursor, .signedOut, "Not signed in to Cursor", "Sign in to Cursor to see usage."),
        (.cursor, .signInBusy, "Cursor is busy", "Retrying in a few minutes."),
        (.cursor, .notInstalled, "Cursor isn't installed", nil),
        (.cursor, .unreachable, "Can't reach Cursor", "Retrying in a few minutes."),
    ] as [(UsageProvider, UsageUnavailableReason, String, String?)])
    func aToolWithNoReadingShowsItsReasonInATitleAndOneLine(
        provider: UsageProvider,
        reason: UsageUnavailableReason,
        title: String,
        detail: String?
    ) throws {
        let usage = ProviderUsageState(provider: provider, status: .unavailable(reason, lastSnapshot: nil))
        let section = try #require(state(providerUsage: [usage]).toolSections.first)

        #expect(section.card == ToolCard(title: title, detail: detail))
        #expect(section.followUp?.action == (reason == .keychainAccessNeeded ? .allowKeychainAccess : nil))
    }

    @Test(arguments: [
        (UsageUnavailableReason.signedOut, ProviderOwnSignIn.signedOut, ProviderAction?.some(.signIn)),
        (.signInExpired, .signedOut, .signIn),
        (.signInRequired, .signedIn, .signIn),
        (.unreachable, .signedIn, nil),
        (.keychainAccessNeeded, .signedOut, .allowKeychainAccess),
        (.signInExpired, .unsupported, nil),
    ] as [(UsageUnavailableReason, ProviderOwnSignIn, ProviderAction?)])
    func aLostClaudeSignInOffersRefillsOwnSignInUnderTheCard(reason: UsageUnavailableReason, ownSignIn: ProviderOwnSignIn, action: ProviderAction?) throws {
        let usage = ProviderUsageState(provider: .claude, status: .unavailable(reason, lastSnapshot: nil), ownSignIn: ownSignIn)

        let section = try #require(state(providerUsage: [usage]).toolSections.first)

        #expect(section.followUp?.action == action)
        if action == .signIn {
            #expect(section.followUp == ToolFollowUp(title: "Sign in with Claude…", systemImage: "person.crop.circle", action: .signIn))
        }
    }

    @Test
    func theClaudeSideMenuSignsInOrOutOfRefillsOwnSignIn() throws {
        func signInItem(_ ownSignIn: ProviderOwnSignIn) throws -> ToolMenuItem? {
            let usage = ProviderUsageState(provider: .claude, status: .current(claudeSnapshot()), ownSignIn: ownSignIn)
            return try #require(state(providerUsage: [usage]).toolSections.first).signInItem
        }

        #expect(try signInItem(.signedOut) == ToolMenuItem(title: "Sign in with Claude…", action: .signIn))
        #expect(try signInItem(.signedIn) == ToolMenuItem(title: "Sign Out of Claude", action: .signOut))
        #expect(try signInItem(.unsupported) == nil)
    }

    @Test
    func aFailedReadKeepsTheLastMetersDimmedUnderTheTimeTheyWereRead() throws {
        let lastSnapshot = claudeSnapshot(fetchedAt: now.addingTimeInterval(-30 * 60))
        let unreachable = ProviderUsageState(provider: .claude, status: .unavailable(.unreachable, lastSnapshot: lastSnapshot))
        let stale = ProviderUsageState(provider: .claude, status: .stale(lastSnapshot))

        let failedCard = try #require(state(providerUsage: [unreachable]).toolSections.first).card
        let staleSection = try #require(state(providerUsage: [stale]).toolSections.first)

        #expect(failedCard.title == "Can't reach Anthropic")
        #expect(failedCard.detail?.hasPrefix("As of ") == true)
        #expect(failedCard.isDimmed)
        #expect(failedCard.windows.map(\.kind) == [.session, .weekly])
        #expect(staleSection.card.title == nil)
        #expect(staleSection.card.isDimmed)
        #expect(staleSection.planTag == "Max x20")
    }

    @Test
    func lostKeychainAccessKeepsTheLastMetersAsOfTheirTimeAndOffersAccessInsteadOfSignIn() throws {
        let lastSnapshot = claudeSnapshot(fetchedAt: now.addingTimeInterval(-30 * 60))
        let usage = ProviderUsageState(provider: .claude, status: .unavailable(.keychainAccessNeeded, lastSnapshot: lastSnapshot))

        let section = try #require(state(providerUsage: [usage]).toolSections.first)

        #expect(section.card.title == nil)
        #expect(section.card.detail?.hasPrefix("As of ") == true)
        #expect(section.card.isDimmed)
        #expect(section.card.windows.map(\.kind) == [.session, .weekly])
        #expect(section.followUp == ToolFollowUp(title: "Allow Keychain Access…", systemImage: "key", action: .allowKeychainAccess))
    }

    @Test
    func waitingHasNoMeters() throws {
        let waiting = ProviderUsageState(provider: .claude, status: .awaitingUsage)

        let waitingSection = try #require(state(providerUsage: [waiting]).toolSections.first)

        #expect(waitingSection.card == ToolCard(title: "Waiting for Claude Code usage"))
        #expect(waitingSection.planTag == nil)
    }

    @Test
    func cursorShowsItsBillingCycleAndCreditsAndAnUnlimitedPlanHasNoMeter() throws {
        let credits = UsageCredits.extraUsage(spent: 12.5, limit: 50, currencyCode: "USD")
        let limited = UsageSnapshot(
            provider: .cursor,
            planName: "pro",
            windows: [UsageWindow(kind: .billingCycle, usedPercent: 82, resetsAt: now.addingTimeInterval(20 * 86_400), durationMinutes: nil)],
            fetchedAt: now,
            credits: credits
        )
        let unlimited = UsageSnapshot(provider: .cursor, planName: "pro", windows: [], fetchedAt: now)

        let limitedSection = try #require(state(providerUsage: [ProviderUsageState(provider: .cursor, status: .current(limited))]).toolSections.first)
        let unlimitedCard = try #require(state(providerUsage: [ProviderUsageState(provider: .cursor, status: .current(unlimited))]).toolSections.first).card

        #expect(limitedSection.planTag == "Pro")
        #expect(limitedSection.card.windows.map(\.kind) == [.billingCycle])
        #expect(limitedSection.card.credits == credits)
        #expect(unlimitedCard.windows.isEmpty)
        #expect(unlimitedCard.title == nil)
        #expect(unlimitedCard.credits == nil)
    }

    @Test
    func creditsReadAsWholeCreditsOrMoney() {
        let locale = Locale(identifier: "en_US")

        #expect(creditsText(.balance(Decimal(string: "62498.0761312500")!), locale: locale) == "62,498 credits")
        #expect(creditsText(.balance(Decimal(string: "1.9")!), locale: locale) == "1 credit")
        #expect(creditsText(.balance(0), locale: locale) == "0 credits")
        #expect(creditsText(.unlimited, locale: locale) == "Unlimited credits")
        #expect(creditsText(.extraUsage(spent: Decimal(string: "12.4")!, limit: 50, currencyCode: "USD"), locale: locale) == "$12.40 of $50.00 extra usage")
        #expect(creditsText(.extraUsage(spent: Decimal(string: "12.4")!, limit: nil, currencyCode: "USD"), locale: locale) == "$12.40 extra usage")
    }

    @Test
    func accountsListTheOneInUseFirstWithEmailsMaskedWhenHidden() throws {
        let active = makeAccount(email: "alex@example.com", usage: makeUsage(fetchedAt: now))
        let other = makeAccount(email: "alex.side@example.com")
        var claudeUsage = claudeSnapshot()
        claudeUsage.accountEmail = "sam@acme.dev"
        let claude = ProviderUsageState(provider: .claude, status: .current(claudeUsage))

        let shown = state(activeAccount: active, inactiveAccounts: [other], providerUsage: [claude])
        let hidden = state(activeAccount: active, inactiveAccounts: [other], providerUsage: [claude], masksEmails: true)

        let codex = try #require(shown.toolSections.first { $0.provider == .codex })
        let maskedCodex = try #require(hidden.toolSections.first { $0.provider == .codex })
        let claudeSection = try #require(shown.toolSections.first { $0.provider == .claude })
        let maskedClaude = try #require(hidden.toolSections.first { $0.provider == .claude })

        #expect(codex.activeLabel == "alex@example.com")
        #expect(codex.otherAccounts.map(\.label) == ["alex.side@example.com"])
        #expect(maskedCodex.accounts.map(\.label) == ["a•••x@example.com", "al•••e@example.com"])
        #expect(claudeSection.activeLabel == "sam@acme.dev")
        #expect(maskedClaude.activeLabel == "s•••m@acme.dev")
        #expect(maskedClaude.accounts.isEmpty)
    }

    @Test
    func savedCodexAccountsShowTheirLastLimitsOnOneLineAndSayWhenTheyAreOld() throws {
        let active = makeAccount(email: "alex@example.com", usage: makeUsage(fetchedAt: now))
        let pro = makeAccount(email: "pro@example.com", planType: "pro", usage: makeUsage(planType: "pro", fetchedAt: now))
        let old = makeAccount(email: "old@example.com", usage: makeUsage(fetchedAt: now.addingTimeInterval(-31 * 60)))
        let new = makeAccount(email: "new@example.com")

        let used = state(activeAccount: active, inactiveAccounts: [pro, old, new])
        let left = state(activeAccount: active, inactiveAccounts: [pro], usagePercentMode: .left)
        let codexOthers = try #require(used.toolSections.first { $0.provider == .codex }).otherAccounts
        let codexLeft = try #require(left.toolSections.first { $0.provider == .codex }).otherAccounts

        #expect(codexOthers[0].usageLine == "Weekly 68% used")
        #expect(codexOthers[1].usageLine?.hasPrefix("Session 42% · Weekly 68% used · as of ") == true)
        #expect(codexOthers[2].usageLine == nil)
        #expect(codexLeft.map(\.usageLine) == ["Weekly 32% left"])
    }

    @Test
    func codexAccountsWithoutEmailReadAsTheirWorkspaceThenTheirPlan() throws {
        let workspace = makeAccount(
            email: nil,
            workspaceIdentity: CodexWorkspaceIdentity(workspaceAccountID: "org-1", workspaceLabel: "Acme"),
            planType: "team"
        )
        let plus = makeAccount(email: nil, planType: "plus")
        let otherPlus = makeAccount(email: nil, planType: "plus")
        let unknown = makeAccount(email: nil)

        let section = try #require(
            state(activeAccount: workspace, inactiveAccounts: [plus, otherPlus, unknown]).toolSections.first { $0.provider == .codex }
        )

        #expect(section.accounts.map(\.label) == ["Acme", "Plus account", "Plus account 2", "Saved account"])
        #expect(state(activeAccount: workspace, inactiveAccounts: [plus]).accountLabel(plus.id, of: .codex) == "Plus account")
    }

    @Test
    func displayedEmailKeepsTheDomainAndTheEndsOfTheName() {
        #expect(displayedEmail("alex.side@example.com", masked: true) == "al•••e@example.com")
        #expect(displayedEmail("alex@example.com", masked: true) == "a•••x@example.com")
        #expect(displayedEmail("al@example.com", masked: true) == "a•••@example.com")
        #expect(displayedEmail("alex@example.com", masked: false) == "alex@example.com")
    }

    @Test
    func planTagsReadLikeEachToolsOwnPlanNames() {
        #expect(planTag(for: .codex, planName: "prolite") == "Pro x5")
        #expect(planTag(for: .codex, planName: "unknown") == nil)
        #expect(planTag(for: .codex, planName: nil) == nil)
        #expect(planTag(for: .claude, planName: "max_20x") == "Max x20")
        #expect(planTag(for: .claude, planName: "max") == "Max")
        #expect(planTag(for: .cursor, planName: "pro") == "Pro")
        #expect(planTag(for: .cursor, planName: "pro_plus") == "Pro Plus")
    }

    @Test
    func movingASectionStepsPastItsVisibleNeighborOnly() {
        let codex = makeAccount(name: "Work", usage: makeUsage(fetchedAt: now))
        let claude = ProviderUsageState(provider: .claude, status: .current(claudeSnapshot()))
        let menu = state(activeAccount: codex, providerUsage: [claude], toolOrder: [.claude, .cursor, .codex])

        #expect(menu.toolOrder(moving: .codex, .up) == [.codex, .claude, .cursor])
        #expect(menu.toolOrder(moving: .codex, .toTop) == [.codex, .claude, .cursor])
        #expect(menu.toolOrder(moving: .claude, .down) == [.cursor, .codex, .claude])
        #expect(menu.toolOrder(moving: .claude, .up) == nil)
        #expect(menu.toolOrder(moving: .codex, .down) == nil)
        #expect(menu.toolOrder(moving: .cursor, .up) == nil)
    }

    private func claudeSnapshot(fetchedAt: Date? = nil) -> UsageSnapshot {
        UsageSnapshot(
            provider: .claude,
            planName: "max_20x",
            windows: [
                UsageWindow(kind: .session, usedPercent: 11, resetsAt: now.addingTimeInterval(3 * 3_600), durationMinutes: 300),
                UsageWindow(kind: .weekly, usedPercent: 60, resetsAt: now.addingTimeInterval(16 * 3_600), durationMinutes: 10_080),
            ],
            fetchedAt: fetchedAt ?? now
        )
    }

    @Test
    func claudeModelLimitsShowAfterWeeklyInTheCardButNotTheMenuBarIcon() throws {
        let limits = #"[{"kind":"weekly_scoped","group":"weekly","percent":37,"resets_at":"2026-10-18T01:00:00+00:00","is_active":true,"scope":{"model":{"display_name":"Fable"}}}]"#
        let shown = try claudeState(limits: limits, showsModelLimits: true)
        let hidden = try claudeState(limits: limits, showsModelLimits: false)
        let shownSection = try #require(shown.toolSections.first)
        let hiddenSection = try #require(hidden.toolSections.first)

        #expect(shownSection.card.windows.map(\.kind.title) == ["Session", "Weekly", "Fable this week"])
        #expect(shown.statusItemSource.windows.map(\.kind.title) == ["Session", "Weekly"])
        #expect(hiddenSection.card.windows.map(\.kind.title) == ["Session", "Weekly"])
    }

    @Test
    func everyNamedClaudeModelLimitGetsAMeterAndOneWithoutANameIsSkipped() throws {
        let limits = #"""
        [{"kind":"weekly_scoped","percent":37,"resets_at":"2026-10-18T01:00:00+00:00","scope":{"model":{"display_name":"Fable"}}},
         {"kind":"weekly_scoped","percent":12,"resets_at":null,"scope":{"model":{}}},
         {"kind":"weekly","percent":21,"resets_at":"2026-10-14T09:00:00+00:00"},
         {"kind":"weekly_scoped","percent":"high","scope":{"model":{"display_name":"Odd"}}},
         "unexpected",
         {"kind":"weekly_scoped","percent":5,"resets_at":"2026-10-18T01:00:00+00:00","scope":{"model":{"display_name":"Sonnet"}}}]
        """#
        let noName = #"[{"kind":"weekly_scoped","percent":12,"resets_at":null,"scope":{"model":{"display_name":null}}}]"#

        let card = try #require(try claudeState(limits: limits, showsModelLimits: true).toolSections.first).card
        let noNameCard = try #require(try claudeState(limits: noName, showsModelLimits: true).toolSections.first).card

        #expect(card.windows.map(\.kind.title) == ["Session", "Weekly", "Fable this week", "Sonnet this week"])
        #expect(card.windows.last == UsageWindow(
            kind: .modelWeekly(modelName: "Sonnet"),
            usedPercent: 5,
            resetsAt: Date(timeIntervalSince1970: 1_792_285_200),
            durationMinutes: 10_080
        ))
        #expect(noNameCard.windows.map(\.kind.title) == ["Session", "Weekly"])
    }

    /// The Claude card, read from a synthetic usage response with these `limits`.
    private func claudeState(limits: String, showsModelLimits: Bool) throws -> MenuBarMenuState {
        let response = #"{"five_hour":{"utilization":64,"resets_at":null},"seven_day":{"utilization":21,"resets_at":null},"limits":\#(limits)}"#
        let report = try ClaudeUsageAPI.parseUsage(Data(response.utf8))
        guard case let .snapshot(snapshot) = ClaudeCodeUsage.reading(from: .available(report, planName: "max", email: nil), fetchedAt: now) else {
            throw CancellationError()
        }
        return MenuBarMenuState(
            activeAccount: nil,
            inactiveAccounts: [],
            providerUsage: [ProviderUsageState(provider: .claude, status: .current(snapshot))],
            showsModelLimits: showsModelLimits,
            now: now
        )
    }

    private func state(
        activeAccount: CodexAccount? = nil,
        inactiveAccounts: [CodexAccount] = [],
        providerUsage: [ProviderUsageState] = [],
        toolOrder: [UsageProvider] = [.claude, .codex, .cursor],
        masksEmails: Bool = false,
        usagePercentMode: UsagePercentMode = .used
    ) -> MenuBarMenuState {
        MenuBarMenuState(
            activeAccount: activeAccount,
            inactiveAccounts: inactiveAccounts,
            usagePercentMode: usagePercentMode,
            providerUsage: providerUsage,
            toolOrder: toolOrder,
            masksEmails: masksEmails,
            now: now
        )
    }
}
