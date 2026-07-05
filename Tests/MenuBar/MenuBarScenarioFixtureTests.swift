import Foundation
import Testing

@testable import CodexPill

@MainActor
struct MenuBarScenarioFixtureTests {
    @Test
    func emptyCatalogFixtureCreatesIdleEmptyMenuState() {
        let state = MenuBarValidationScenarioFixtures.makeState(
            for: "menu-empty-catalog",
            now: Date(timeIntervalSince1970: 1_744_195_200)
        )

        #expect(state.activeAccount == nil)
        #expect(state.inactiveAccounts.isEmpty)
        #expect(state.remoteHosts.isEmpty)
        #expect(state.refreshIntervalMinutes == 10)
        #expect(state.statusBarIndicatorStyle == .stackedBars)
        #expect(state.statusMessage == "Ready")
    }

    @Test
    func tokenUsageReadyFixtureUsesSyntheticLocalAggregateState() throws {
        let state = MenuBarValidationScenarioFixtures.makeState(
            for: "token-usage-ready-card",
            now: Date(timeIntervalSince1970: 1_744_195_200)
        )

        #expect(state.tokenUsageEnabled)
        #expect(state.tokenUsagePeriod == .last30Days)
        #expect(state.tokenUsageChartStyle == .heatStrip)
        #expect(state.tokenUsageCard != nil)
        #expect(state.activeAccount?.email == "primary@example.com")
        #expect(state.inactiveAccounts.map(\.email) == [
            "research@example.com",
            "sandbox@example.com",
            "overflow@example.com"
        ])
    }

    @Test
    func launchAtLoginFixtureCanOverrideLoginItemState() {
        let state = MenuBarValidationScenarioFixtures.makeLaunchAtLoginState(
            loginItemState: .requiresApproval,
            now: Date(timeIntervalSince1970: 1_744_195_200)
        )

        #expect(state.loginItemState == .requiresApproval)
        #expect(state.activeAccount?.name == "Primary")
    }
}
