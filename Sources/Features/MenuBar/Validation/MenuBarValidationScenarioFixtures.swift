import Foundation

@MainActor
enum MenuBarValidationScenarioFixtures {
    static func makeState(for scenario: String, now: Date) -> MenuBarMenuState {
        switch scenario {
        case "hosted-menu-default", "menu-account-overflow", "token-usage-off-hidden":
            let active = makeAccount(
                name: "Primary",
                email: "primary@example.com",
                planType: "pro",
                sessionUsedPercent: 42,
                weeklyUsedPercent: 68,
                now: now
            )

            let others = [
                makeAccount(name: "Research", email: "research@example.com", planType: "pro", sessionUsedPercent: 8, weeklyUsedPercent: 35, now: now),
                makeAccount(name: "Sandbox", email: "sandbox@example.com", planType: "plus", sessionUsedPercent: 19, weeklyUsedPercent: 50, now: now),
                makeAccount(name: "Overflow", email: "overflow@example.com", planType: "plus", sessionUsedPercent: 74, weeklyUsedPercent: 88, now: now)
            ]

            return MenuBarMenuState(
                activeAccount: active,
                inactiveAccounts: others,
                remoteHosts: [],
                visibleInactiveAccountCount: 2,
                visibleInactiveAccountCountOptions: [2, 3, 5, 0],
                refreshIntervalMinutes: 5,
                refreshIntervalOptions: [1, 2, 5, 10, 15, 30],
                statusBarMonochrome: false,
                statusBarIndicatorStyle: .dualArcBadge,
                statusBarDisplayMode: .textOnHover,
                isBusy: false,
                statusMessage: "Ready"
            )

        case "launch-at-login-menu-states":
            return makeLaunchAtLoginState(loginItemState: .requiresApproval, now: now)

        case "status-bar-icon-text-visible":
            return makeStatusBarIconTextState(now: now)

        case "token-usage-ready-card":
            let active = makeAccount(
                name: "Primary",
                email: "primary@example.com",
                planType: "pro",
                sessionUsedPercent: 42,
                weeklyUsedPercent: 68,
                now: now
            )

            let others = [
                makeAccount(name: "Research", email: "research@example.com", planType: "pro", sessionUsedPercent: 8, weeklyUsedPercent: 35, now: now),
                makeAccount(name: "Sandbox", email: "sandbox@example.com", planType: "plus", sessionUsedPercent: 19, weeklyUsedPercent: 50, now: now),
                makeAccount(name: "Overflow", email: "overflow@example.com", planType: "plus", sessionUsedPercent: 74, weeklyUsedPercent: 88, now: now)
            ]

            return MenuBarMenuState(
                activeAccount: active,
                inactiveAccounts: others,
                remoteHosts: [],
                visibleInactiveAccountCount: 2,
                visibleInactiveAccountCountOptions: [2, 3, 5, 0],
                refreshIntervalMinutes: 5,
                refreshIntervalOptions: [1, 2, 5, 10, 15, 30],
                statusBarMonochrome: false,
                statusBarIndicatorStyle: .dualArcBadge,
                statusBarDisplayMode: .textOnHover,
                isBusy: false,
                statusMessage: "Ready",
                tokenUsageEnabled: true,
                tokenUsagePeriod: .last30Days,
                tokenUsageChartStyle: .heatStrip,
                tokenUsageCard: makeTokenUsageCard(
                    period: .last30Days,
                    style: .heatStrip,
                    loadState: loadedTokenUsageData([
                        dailyTokenUsage(daysAgo: 1, totalTokens: 1_200),
                        dailyTokenUsage(daysAgo: 0, totalTokens: 3_400)
                    ])
                )
            )

        case "token-usage-loading-progress":
            let active = makeAccount(
                name: "Primary",
                email: "primary@example.com",
                planType: "pro",
                sessionUsedPercent: 42,
                weeklyUsedPercent: 68,
                now: now
            )

            let others = [
                makeAccount(name: "Research", email: "research@example.com", planType: "pro", sessionUsedPercent: 8, weeklyUsedPercent: 35, now: now),
                makeAccount(name: "Sandbox", email: "sandbox@example.com", planType: "plus", sessionUsedPercent: 19, weeklyUsedPercent: 50, now: now),
                makeAccount(name: "Overflow", email: "overflow@example.com", planType: "plus", sessionUsedPercent: 74, weeklyUsedPercent: 88, now: now)
            ]

            return MenuBarMenuState(
                activeAccount: active,
                inactiveAccounts: others,
                remoteHosts: [],
                visibleInactiveAccountCount: 2,
                visibleInactiveAccountCountOptions: [2, 3, 5, 0],
                refreshIntervalMinutes: 5,
                refreshIntervalOptions: [1, 2, 5, 10, 15, 30],
                statusBarMonochrome: false,
                statusBarIndicatorStyle: .dualArcBadge,
                statusBarDisplayMode: .textOnHover,
                isBusy: false,
                statusMessage: "Ready",
                tokenUsageEnabled: true,
                tokenUsagePeriod: .last30Days,
                tokenUsageChartStyle: .sparkline,
                tokenUsageCard: makeTokenUsageCard(
                    period: .last30Days,
                    style: .sparkline,
                    loadState: .loading(TokenUsageScanProgress(scannedFiles: 42, totalFiles: 310))
                )
            )

        case "hosted-menu-with-host":
            let active = makeAccount(
                name: "Primary",
                email: "primary@example.com",
                planType: "pro",
                sessionUsedPercent: 42,
                weeklyUsedPercent: 68,
                now: now
            )

            let others = [
                makeAccount(name: "Research", email: "research@example.com", planType: "pro", sessionUsedPercent: 8, weeklyUsedPercent: 35, now: now),
                makeAccount(name: "Sandbox", email: "sandbox@example.com", planType: "plus", sessionUsedPercent: 19, weeklyUsedPercent: 50, now: now),
                makeAccount(name: "Overflow", email: "overflow@example.com", planType: "plus", sessionUsedPercent: 74, weeklyUsedPercent: 88, now: now)
            ]
            let remoteActive = makeAccount(
                name: "Remote Active",
                email: "remote-active@example.com",
                planType: "team",
                sessionUsedPercent: 11,
                weeklyUsedPercent: 27,
                now: now
            )

            return MenuBarMenuState(
                activeAccount: active,
                inactiveAccounts: others,
                remoteHosts: [RemoteHostMenuState(
                    name: "buildbox",
                    connectionState: .connected,
                    activeAccount: remoteActive,
                    deployedAccountIDs: others.map(\.id)
                )],
                visibleInactiveAccountCount: 2,
                visibleInactiveAccountCountOptions: [2, 3, 5, 0],
                refreshIntervalMinutes: 5,
                refreshIntervalOptions: [1, 2, 5, 10, 15, 30],
                statusBarMonochrome: false,
                statusBarIndicatorStyle: .dualArcBadge,
                statusBarDisplayMode: .textOnHover,
                isBusy: false,
                statusMessage: "Ready"
            )

        case "hosted-menu-local-and-remote-same-account":
            let active = makeAccount(
                name: "Primary",
                email: "primary@example.com",
                planType: "pro",
                sessionUsedPercent: 42,
                weeklyUsedPercent: 68,
                now: now
            )
            let research = makeAccount(name: "Research", email: "research@example.com", planType: "pro", sessionUsedPercent: 8, weeklyUsedPercent: 35, now: now)
            var remoteActive = active
            remoteActive.updatedAt = active.updatedAt.addingTimeInterval(60)

            return MenuBarMenuState(
                activeAccount: active,
                inactiveAccounts: [research],
                remoteHosts: [RemoteHostMenuState(
                    name: "debian-vm",
                    destination: "user@debian-vm",
                    connectionState: .connected,
                    desiredAccount: active,
                    activeAccount: remoteActive,
                    verificationStatus: .verified,
                    deployedAccountIDs: [active.id, research.id]
                )],
                visibleInactiveAccountCount: 2,
                visibleInactiveAccountCountOptions: [2, 3, 5, 0],
                refreshIntervalMinutes: 5,
                refreshIntervalOptions: [1, 2, 5, 10, 15, 30],
                statusBarMonochrome: false,
                statusBarIndicatorStyle: .dualArcBadge,
                statusBarDisplayMode: .textOnHover,
                isBusy: false,
                statusMessage: "Ready"
            )

        case "hosted-menu-multiple-hosts":
            let active = makeAccount(
                name: "Primary",
                email: "primary@example.com",
                planType: "pro",
                sessionUsedPercent: 42,
                weeklyUsedPercent: 68,
                now: now
            )

            let others = [
                makeAccount(name: "Research", email: "research@example.com", planType: "pro", sessionUsedPercent: 8, weeklyUsedPercent: 35, now: now),
                makeAccount(name: "Sandbox", email: "sandbox@example.com", planType: "plus", sessionUsedPercent: 19, weeklyUsedPercent: 50, now: now),
                makeAccount(name: "Overflow", email: "overflow@example.com", planType: "plus", sessionUsedPercent: 74, weeklyUsedPercent: 88, now: now),
                makeAccount(name: "Archive", email: "archive@example.com", planType: "team", sessionUsedPercent: 4, weeklyUsedPercent: 11, now: now)
            ]
            let buildboxActive = makeAccount(
                name: "Buildbox Active",
                email: "buildbox-active@example.com",
                planType: "team",
                sessionUsedPercent: 11,
                weeklyUsedPercent: 27,
                now: now
            )
            let debianActive = makeAccount(
                name: "Debian Active",
                email: "debian-active@example.com",
                planType: "plus",
                sessionUsedPercent: 33,
                weeklyUsedPercent: 45,
                now: now
            )

            return MenuBarMenuState(
                activeAccount: active,
                inactiveAccounts: others,
                remoteHosts: [
                    RemoteHostMenuState(
                        name: "buildbox",
                        destination: "user@buildbox",
                        connectionState: .connected,
                        activeAccount: buildboxActive,
                        deployedAccountIDs: others.map(\.id)
                    ),
                    RemoteHostMenuState(
                        name: "debian-vm",
                        destination: "user@debian-vm",
                        connectionState: .connected,
                        activeAccount: debianActive,
                        deployedAccountIDs: [others[0].id, others[2].id]
                    )
                ],
                visibleInactiveAccountCount: 2,
                visibleInactiveAccountCountOptions: [2, 3, 5, 0],
                refreshIntervalMinutes: 5,
                refreshIntervalOptions: [1, 2, 5, 10, 15, 30],
                statusBarMonochrome: false,
                statusBarIndicatorStyle: .dualArcBadge,
                statusBarDisplayMode: .textOnHover,
                isBusy: false,
                statusMessage: "Ready"
            )

        case "host-account-missing-on-host":
            let active = makeAccount(
                name: "Primary",
                email: "primary@example.com",
                planType: "pro",
                sessionUsedPercent: 42,
                weeklyUsedPercent: 68,
                now: now
            )

            let research = makeAccount(name: "Research", email: "research@example.com", planType: "pro", sessionUsedPercent: 8, weeklyUsedPercent: 35, now: now)
            let sandbox = makeAccount(name: "Sandbox", email: "sandbox@example.com", planType: "plus", sessionUsedPercent: 19, weeklyUsedPercent: 50, now: now)
            let overflow = makeAccount(name: "Overflow", email: "overflow@example.com", planType: "plus", sessionUsedPercent: 74, weeklyUsedPercent: 88, now: now)

            return MenuBarMenuState(
                activeAccount: active,
                inactiveAccounts: [research, sandbox, overflow],
                remoteHosts: [RemoteHostMenuState(
                    name: "buildbox",
                    connectionState: .connected,
                    activeAccount: nil,
                    deployedAccountIDs: [sandbox.id]
                )],
                visibleInactiveAccountCount: 2,
                visibleInactiveAccountCountOptions: [2, 3, 5, 0],
                refreshIntervalMinutes: 5,
                refreshIntervalOptions: [1, 2, 5, 10, 15, 30],
                statusBarMonochrome: false,
                statusBarIndicatorStyle: .dualArcBadge,
                statusBarDisplayMode: .textOnHover,
                isBusy: false,
                statusMessage: "Ready"
            )

        case "hosted-menu-disconnected-host":
            let active = makeAccount(
                name: "Primary",
                email: "primary@example.com",
                planType: "pro",
                sessionUsedPercent: 42,
                weeklyUsedPercent: 68,
                now: now
            )

            let research = makeAccount(name: "Research", email: "research@example.com", planType: "pro", sessionUsedPercent: 8, weeklyUsedPercent: 35, now: now)
            let sandbox = makeAccount(name: "Sandbox", email: "sandbox@example.com", planType: "plus", sessionUsedPercent: 19, weeklyUsedPercent: 50, now: now)
            let overflow = makeAccount(name: "Overflow", email: "overflow@example.com", planType: "plus", sessionUsedPercent: 74, weeklyUsedPercent: 88, now: now)

            return MenuBarMenuState(
                activeAccount: active,
                inactiveAccounts: [research, sandbox, overflow],
                remoteHosts: [RemoteHostMenuState(
                    name: "buildbox",
                    destination: "user@buildbox",
                    connectionState: .disconnected,
                    activeAccount: makeAccount(
                        name: "Stale Remote",
                        email: "stale-remote@example.com",
                        planType: "team",
                        sessionUsedPercent: 52,
                        weeklyUsedPercent: 61,
                        now: now
                    ),
                    deployedAccountIDs: [research.id]
                )],
                visibleInactiveAccountCount: 2,
                visibleInactiveAccountCountOptions: [2, 3, 5, 0],
                refreshIntervalMinutes: 5,
                refreshIntervalOptions: [1, 2, 5, 10, 15, 30],
                statusBarMonochrome: false,
                statusBarIndicatorStyle: .dualArcBadge,
                statusBarDisplayMode: .textOnHover,
                isBusy: false,
                statusMessage: "Ready"
            )

        case "menu-busy-status", "hosted-menu-busy":
            let active = makeAccount(
                name: "Primary",
                email: "primary@example.com",
                planType: "pro",
                sessionUsedPercent: 57,
                weeklyUsedPercent: 73,
                now: now
            )

            return MenuBarMenuState(
                activeAccount: active,
                inactiveAccounts: [],
                remoteHosts: [],
                visibleInactiveAccountCount: 2,
                visibleInactiveAccountCountOptions: [2, 3, 5, 0],
                refreshIntervalMinutes: 5,
                refreshIntervalOptions: [1, 2, 5, 10, 15, 30],
                statusBarMonochrome: true,
                statusBarIndicatorStyle: .twinPills,
                statusBarDisplayMode: .textOnHover,
                isBusy: true,
                statusMessage: "Refreshing account data..."
            )

        case "menu-empty-catalog":
            return MenuBarMenuState(
                activeAccount: nil,
                inactiveAccounts: [],
                remoteHosts: [],
                visibleInactiveAccountCount: 2,
                visibleInactiveAccountCountOptions: [2, 3, 5, 0],
                refreshIntervalMinutes: 10,
                refreshIntervalOptions: [1, 2, 5, 10, 15, 30],
                statusBarMonochrome: false,
                statusBarIndicatorStyle: .stackedBars,
                statusBarDisplayMode: .textOnHover,
                isBusy: false,
                statusMessage: "Ready"
            )

        case "menu-unmatched-active-account":
            let accounts = [
                makeAccount(name: "Research", email: "research@example.com", planType: "pro", sessionUsedPercent: 8, weeklyUsedPercent: 35, now: now),
                makeAccount(name: "Sandbox", email: "sandbox@example.com", planType: "plus", sessionUsedPercent: 19, weeklyUsedPercent: 50, now: now),
                makeAccount(name: "Overflow", email: "overflow@example.com", planType: "plus", sessionUsedPercent: 74, weeklyUsedPercent: 88, now: now)
            ]

            return MenuBarMenuState(
                activeAccount: nil,
                inactiveAccounts: accounts,
                remoteHosts: [],
                visibleInactiveAccountCount: 2,
                visibleInactiveAccountCountOptions: [2, 3, 5, 0],
                refreshIntervalMinutes: 5,
                refreshIntervalOptions: [1, 2, 5, 10, 15, 30],
                statusBarMonochrome: false,
                statusBarIndicatorStyle: .dualArcBadge,
                statusBarDisplayMode: .textOnHover,
                isBusy: false,
                statusMessage: "Ready"
            )

        default:
            return makeState(for: "hosted-menu-default", now: now)
        }
    }

    static func makeLaunchAtLoginState(
        loginItemState: LoginItemState,
        now: Date
    ) -> MenuBarMenuState {
        makeStateVariant(now: now, loginItemState: loginItemState)
    }

    static func makeStatusBarIconTextState(now: Date) -> MenuBarMenuState {
        makeStateVariant(now: now, statusBarDisplayMode: .iconAndText)
    }

    private static func makeStateVariant(
        now: Date,
        loginItemState: LoginItemState? = nil,
        statusBarDisplayMode: StatusBarDisplayMode? = nil
    ) -> MenuBarMenuState {
        let base = makeState(for: "hosted-menu-default", now: now)
        return MenuBarMenuState(
            activeAccount: base.activeAccount,
            inactiveAccounts: base.inactiveAccounts,
            remoteHosts: base.remoteHosts,
            visibleInactiveAccountCount: base.visibleInactiveAccountCount,
            visibleInactiveAccountCountOptions: base.visibleInactiveAccountCountOptions,
            refreshIntervalMinutes: base.refreshIntervalMinutes,
            refreshIntervalOptions: base.refreshIntervalOptions,
            statusBarMonochrome: base.statusBarMonochrome,
            statusBarIndicatorStyle: base.statusBarIndicatorStyle,
            statusBarDisplayMode: statusBarDisplayMode ?? base.statusBarDisplayMode,
            revealStatusItemTitleShortcut: base.revealStatusItemTitleShortcut,
            progressAccentColor: base.progressAccentColor,
            pacingMarkersEnabled: base.pacingMarkersEnabled,
            hasCustomProgressAccentColor: base.hasCustomProgressAccentColor,
            isBusy: base.isBusy,
            statusMessage: base.statusMessage,
            notificationsWhenBlockedEnabled: base.notificationsWhenBlockedEnabled,
            notificationsWhenOutEnabled: base.notificationsWhenOutEnabled,
            notificationAuthorizationState: base.notificationAuthorizationState,
            loginItemState: loginItemState ?? base.loginItemState,
            tokenUsageEnabled: base.tokenUsageEnabled,
            tokenUsagePeriod: base.tokenUsagePeriod,
            tokenUsageChartStyle: base.tokenUsageChartStyle,
            tokenUsageLoadingAnimationStyle: base.tokenUsageLoadingAnimationStyle,
            tokenUsagePeakScope: base.tokenUsagePeakScope,
            tokenUsageCard: base.tokenUsageCard,
            tokenUsagePrototypeCards: base.tokenUsagePrototypeCards
        )
    }

    private static func makeTokenUsageCard(
        period: CodexTokenUsagePeriod = .last30Days,
        style: TokenUsageChartStyle = .dailyBars,
        peakScope: TokenUsagePeakScope = .currentPeriod,
        loadState: TokenUsageMenuLoadState
    ) -> TokenUsageMenuCard {
        TokenUsageMenuCard.make(
            style: style,
            peakScope: peakScope,
            period: period,
            loadState: loadState,
            calendar: Calendar(identifier: .gregorian)
        )
    }

    private static func loadedTokenUsageData(
        _ buckets: [CodexDailyTokenUsage],
        allTimePeak: CodexDailyTokenUsage? = nil
    ) -> TokenUsageMenuLoadState {
        .loaded(TokenUsageMenuLoadedData(buckets: buckets, allTimePeak: allTimePeak))
    }

    private static func dailyTokenUsage(daysAgo: Int, totalTokens: Int) -> CodexDailyTokenUsage {
        let calendar = Calendar(identifier: .gregorian)
        let base = calendar.date(from: DateComponents(year: 2026, month: 5, day: 20)) ?? .now
        return CodexDailyTokenUsage(
            day: calendar.date(byAdding: .day, value: -daysAgo, to: base) ?? base,
            usage: CodexTokenUsageTotals(
                inputTokens: 0,
                cachedInputTokens: 0,
                outputTokens: 0,
                reasoningOutputTokens: 0,
                totalTokens: totalTokens
            )
        )
    }

    private static func makeAccount(
        name: String,
        email: String,
        planType: String,
        sessionUsedPercent: Int,
        weeklyUsedPercent: Int,
        now: Date
    ) -> CodexAccount {
        CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: now.addingTimeInterval(-3_600),
            updatedAt: now.addingTimeInterval(-600),
            email: email,
            planType: planType,
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: planType,
                primary: CodexRateLimitWindow(
                    usedPercent: sessionUsedPercent,
                    resetsAt: now.addingTimeInterval(3_600),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: weeklyUsedPercent,
                    resetsAt: now.addingTimeInterval(86_400),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: now.addingTimeInterval(-300)
            ),
            identity: CodexAccountIdentity(
                stableAccountID: nil,
                snapshotFingerprint: UUID().uuidString,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: email)
            )
        )
    }
}
