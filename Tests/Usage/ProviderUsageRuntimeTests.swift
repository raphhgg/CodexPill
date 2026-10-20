import Foundation
import Testing

@testable import RUsage

@MainActor
struct ProviderUsageRuntimeTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func refreshesEachProviderAgainOnlyAfterFiveMinutes() async {
        let claude = ProviderConnectionProbe(provider: .claude, reading: .awaitingUsage)
        var now = start
        let runtime = ProviderUsageRuntime(connections: [claude], now: { now }, onChange: {})

        await runtime.refreshIfDue()
        now = start.addingTimeInterval(4 * 60 + 59)
        await runtime.refreshIfDue()

        #expect(claude.readCount == 1)

        now = start.addingTimeInterval(5 * 60)
        await runtime.refreshIfDue()

        #expect(claude.readCount == 2)
    }

    @Test
    func snapshotTurnsStaleOnceOlderThanTheProviderThreshold() async {
        let snapshot = UsageSnapshot(
            provider: .claude,
            planName: nil,
            windows: [UsageWindow(kind: .session, usedPercent: 40, resetsAt: nil, durationMinutes: 300)],
            fetchedAt: start
        )
        let claude = ProviderConnectionProbe(provider: .claude, staleAfter: 3_600, reading: .snapshot(snapshot))
        var now = start
        let runtime = ProviderUsageRuntime(connections: [claude], now: { now }, onChange: {})

        await runtime.refreshIfDue()
        now = start.addingTimeInterval(3_600)

        #expect(runtime.states == [ProviderUsageState(provider: .claude, status: .current(snapshot))])

        now = start.addingTimeInterval(3_601)

        #expect(runtime.states == [ProviderUsageState(provider: .claude, status: .stale(snapshot))])
    }

    @Test
    func connectedToolWaitsForItsFirstReadThenEachToolReportsItsState() async {
        let claude = ProviderConnectionProbe(provider: .claude, reading: .notConnected)
        let cursor = ProviderConnectionProbe(provider: .cursor, reading: .unavailable(.signInExpired))
        var changeCount = 0
        let runtime = ProviderUsageRuntime(connections: [claude, cursor], now: { start }, onChange: { changeCount += 1 })

        #expect(runtime.states == [ProviderUsageState(provider: .cursor, status: .awaitingUsage)])
        #expect(runtime.hasConnectedTool)

        await runtime.refreshIfDue()

        #expect(changeCount == 1)
        #expect(runtime.states == [
            ProviderUsageState(provider: .claude, status: .notConnected),
            ProviderUsageState(provider: .cursor, status: .unavailable(.signInExpired, lastSnapshot: nil))
        ])
    }

    @Test
    func refreshThatIsNotDueKeepsTheLastReadingAndDoesNotNotify() async {
        let claude = ProviderConnectionProbe(provider: .claude, reading: .awaitingUsage)
        var changeCount = 0
        let runtime = ProviderUsageRuntime(connections: [claude], now: { start }, onChange: { changeCount += 1 })

        await runtime.refreshIfDue()
        claude.reading = .unavailable(.unreachable)
        await runtime.refreshIfDue()

        #expect(changeCount == 1)
        #expect(runtime.states == [ProviderUsageState(provider: .claude, status: .awaitingUsage)])
    }

    @Test
    func failedReadKeepsTheLastGoodSnapshotUntilTheAccountMayHaveChanged() async {
        let snapshot = UsageSnapshot(
            provider: .claude,
            planName: nil,
            windows: [UsageWindow(kind: .weekly, usedPercent: 30, resetsAt: nil, durationMinutes: 10_080)],
            fetchedAt: start
        )
        let claude = ProviderConnectionProbe(provider: .claude, reading: .snapshot(snapshot))
        let runtime = ProviderUsageRuntime(connections: [claude], now: { start }, onChange: {})
        await runtime.refreshIfDue()

        claude.reading = .unavailable(.unreachable)
        await runtime.refreshIfDue(forcing: .claude)

        #expect(runtime.states == [ProviderUsageState(provider: .claude, status: .unavailable(.unreachable, lastSnapshot: snapshot))])

        claude.reading = .unavailable(.signInExpired)
        await runtime.refreshIfDue(forcing: .claude)

        #expect(runtime.states == [ProviderUsageState(provider: .claude, status: .unavailable(.signInExpired, lastSnapshot: snapshot))])

        claude.reading = .unavailable(.signedOut)
        await runtime.refreshIfDue(forcing: .claude)
        claude.reading = .unavailable(.unreachable)
        await runtime.refreshIfDue(forcing: .claude)

        #expect(runtime.states == [ProviderUsageState(provider: .claude, status: .unavailable(.unreachable, lastSnapshot: nil))])
    }

    @Test
    func uninstallingTheProviderAppDropsTheLastGoodSnapshot() async {
        let snapshot = UsageSnapshot(
            provider: .cursor,
            planName: "pro",
            windows: [UsageWindow(kind: .billingCycle, usedPercent: 82, resetsAt: nil, durationMinutes: 43_200)],
            fetchedAt: start
        )
        let cursor = ProviderConnectionProbe(provider: .cursor, reading: .snapshot(snapshot))
        let runtime = ProviderUsageRuntime(connections: [cursor], now: { start }, onChange: {})
        await runtime.refreshIfDue()

        cursor.reading = .unavailable(.notInstalled)
        await runtime.refreshIfDue(forcing: .cursor)

        #expect(runtime.states == [ProviderUsageState(provider: .cursor, status: .unavailable(.notInstalled, lastSnapshot: nil))])
    }

    @Test
    func signingInOrOutDropsTheLastSnapshotBecauseTheAccountMayHaveChanged() async {
        let claude = ProviderConnectionProbe(provider: .claude, reading: .snapshot(claudeSnapshot(sessionPercent: 40)))
        let runtime = ProviderUsageRuntime(connections: [claude], now: { start }, onChange: {})
        await runtime.refreshIfDue()
        claude.reading = .unavailable(.unreachable)
        let notice = ProviderNotice(title: "Claude sign-in timed out", detail: "Start it again from the menu.")
        claude.update { $0.notice = notice }

        #expect(await runtime.perform(.signIn, on: .claude) == notice)
        #expect(runtime.states == [ProviderUsageState(provider: .claude, status: .unavailable(.unreachable, lastSnapshot: nil))])
    }

    private func claudeSnapshot(sessionPercent: Int) -> UsageSnapshot {
        UsageSnapshot(
            provider: .claude,
            planName: "max",
            windows: [UsageWindow(kind: .session, usedPercent: sessionPercent, resetsAt: nil, durationMinutes: 300)],
            fetchedAt: start
        )
    }
}

