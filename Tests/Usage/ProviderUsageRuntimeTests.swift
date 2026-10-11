import Foundation
import Testing

@testable import CodexPill

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
    func aReadThatStartedBeforeASwitchIsDroppedWhenItFinishesAfterIt() async {
        let snapshot = UsageSnapshot(
            provider: .cursor,
            planName: "pro",
            windows: [UsageWindow(kind: .billingCycle, usedPercent: 82, resetsAt: nil, durationMinutes: nil)],
            fetchedAt: start
        )
        let gate = TestGate()
        let cursor = ProviderConnectionProbe(provider: .cursor, reading: .snapshot(snapshot))
        cursor.update { $0.readGate = gate }
        let runtime = ProviderUsageRuntime(connections: [cursor], now: { [start] in start }, onChange: {})

        let slowRead = Task { await runtime.refreshIfDue() }
        await gate.waitUntilReached()
        cursor.update {
            $0.readGate = nil
            $0.reading = .unavailable(.unreachable)
        }
        let notice = await runtime.perform(.switchAccount(UUID()), on: .cursor)
        await gate.open()
        await slowRead.value

        #expect(notice == nil)
        #expect(cursor.readCount == 2)
        #expect(runtime.states == [ProviderUsageState(provider: .cursor, status: .unavailable(.unreachable, lastSnapshot: nil))])
    }

    @Test
    func signingInIsShownUntilTheSignInEndsThenTheNewAccountsLimitsAreRead() async throws {
        let gate = TestGate()
        let personal = ProviderAccount(id: UUID(), email: "personal@example.com", isActive: true)
        let team = ProviderAccount(id: UUID(), email: "team@example.com", isActive: false)
        let claude = ProviderConnectionProbe(provider: .claude, reading: .awaitingUsage, signInAvailability: .available)
        let usage = claudeSnapshot(sessionPercent: 12)
        claude.update {
            $0.accounts = [personal]
            $0.signInGate = gate
            $0.accountAddedBySignIn = team
            $0.usageAfterInactiveRead = usage
        }
        let runtime = ProviderUsageRuntime(connections: [claude], now: { [start] in start }, onChange: {})
        await runtime.refreshIfDue()

        let signIn = Task { await runtime.perform(.addAccount, on: .claude) }
        await gate.waitUntilReached()
        #expect(runtime.states.map(\.isSigningIn) == [true])

        await gate.open()
        #expect(await signIn.value == nil)
        let state = try #require(runtime.states.first)
        #expect(state.isSigningIn == false)
        #expect(state.accounts.map(\.email) == ["personal@example.com", "team@example.com"])
        #expect(state.accounts.last?.usage?.window(.session)?.usedPercent == 12)
        #expect(claude.events == ["read \(team.id.uuidString.prefix(4))", "saved \(team.id.uuidString.prefix(4))"])
    }

    @Test
    func cancellingTheSignInEndsItWithoutAnAlertOrANewAccount() async throws {
        let gate = TestGate()
        let personal = ProviderAccount(id: UUID(), email: "personal@example.com", isActive: true)
        let claude = ProviderConnectionProbe(provider: .claude, reading: .awaitingUsage, signInAvailability: .available)
        claude.update {
            $0.accounts = [personal]
            $0.signInGate = gate
            $0.accountAddedBySignIn = ProviderAccount(id: UUID(), email: "team@example.com", isActive: false)
        }
        let runtime = ProviderUsageRuntime(connections: [claude], now: { [start] in start }, onChange: {})
        await runtime.refreshIfDue()

        let signIn = Task { await runtime.perform(.addAccount, on: .claude) }
        await gate.waitUntilReached()
        #expect(await runtime.perform(.cancelSignIn, on: .claude) == nil)

        #expect(await signIn.value == nil)
        let state = try #require(runtime.states.first)
        #expect(state.isSigningIn == false)
        #expect(state.accounts.map(\.email) == ["personal@example.com"])
    }

    @Test
    func aFailedSignInIsReported() async {
        let claude = ProviderConnectionProbe(provider: .claude, reading: .awaitingUsage, signInAvailability: .available)
        let failure = ProviderNotice(title: "Claude sign-in didn't finish", detail: "Nothing was saved.")
        claude.update { $0.signInError = failure }
        let runtime = ProviderUsageRuntime(connections: [claude], now: { [start] in start }, onChange: {})

        #expect(await runtime.perform(.addAccount, on: .claude) == failure)
        #expect(runtime.states.map(\.isSigningIn) == [false])
    }

    @Test
    func inactiveAccountsAreReadEveryFifteenMinutesAndTheActiveOneNever() async {
        let active = ProviderAccount(id: UUID(), email: "personal@example.com", isActive: true)
        let team = ProviderAccount(id: UUID(), email: "team@example.com", isActive: false)
        let claude = ProviderConnectionProbe(provider: .claude, reading: .awaitingUsage)
        claude.update { $0.accounts = [active, team] }
        var now = start
        let runtime = ProviderUsageRuntime(connections: [claude], now: { now }, onChange: {})
        let read = ["read \(team.id.uuidString.prefix(4))", "saved \(team.id.uuidString.prefix(4))"]

        await runtime.refreshInactiveAccountsIfDue()
        now = start.addingTimeInterval(15 * 60 - 1)
        await runtime.refreshInactiveAccountsIfDue()
        #expect(claude.events == read)

        now = start.addingTimeInterval(15 * 60)
        await runtime.refreshInactiveAccountsIfDue()
        #expect(claude.events == read + read)
    }

    @Test
    func aSwitchWaitsForTheInactiveReadInFlightAndStopsTheRest() async {
        let gate = TestGate()
        let active = ProviderAccount(id: UUID(), email: "personal@example.com", isActive: true)
        let team = ProviderAccount(id: UUID(), email: "team@example.com", isActive: false)
        let side = ProviderAccount(id: UUID(), email: "side@example.com", isActive: false)
        let claude = ProviderConnectionProbe(provider: .claude, reading: .awaitingUsage)
        claude.update {
            $0.accounts = [active, team, side]
            $0.inactiveReadGate = gate
        }
        let runtime = ProviderUsageRuntime(connections: [claude], now: { [start] in start }, onChange: {})

        let inactiveRefresh = Task { await runtime.refreshInactiveAccountsIfDue() }
        await gate.waitUntilReached()
        let switchStarted = Flag()
        let switchToTeam = Task {
            switchStarted.isSet = true
            return await runtime.perform(.switchAccount(team.id), on: .claude)
        }
        while !switchStarted.isSet {
            await Task.yield()
        }
        await gate.open()
        #expect(await switchToTeam.value == nil)
        await inactiveRefresh.value

        let teamID = team.id.uuidString.prefix(4)
        #expect(claude.events == ["read \(teamID)", "saved \(teamID)", "switch \(teamID)"])
    }

    @Test
    func noInactiveReadStartsWhileASwitchRuns() async {
        let gate = TestGate()
        let active = ProviderAccount(id: UUID(), email: "personal@example.com", isActive: true)
        let team = ProviderAccount(id: UUID(), email: "team@example.com", isActive: false)
        let cursor = ProviderConnectionProbe(provider: .cursor, reading: .awaitingUsage)
        cursor.update {
            $0.accounts = [active, team]
            $0.switchGate = gate
        }
        let runtime = ProviderUsageRuntime(connections: [cursor], now: { [start] in start }, onChange: {})

        let switchToTeam = Task { await runtime.perform(.switchAccount(team.id), on: .cursor) }
        await gate.waitUntilReached()
        await runtime.refreshInactiveAccountsIfDue()
        await gate.open()
        #expect(await switchToTeam.value == nil)

        let teamID = team.id.uuidString.prefix(4)
        #expect(cursor.events == ["switch \(teamID)"])
    }

    @Test
    func aSwitchIsRefusedWhileTheToolsSignInRuns() async {
        let gate = TestGate()
        let active = ProviderAccount(id: UUID(), email: "personal@example.com", isActive: true)
        let team = ProviderAccount(id: UUID(), email: "team@example.com", isActive: false)
        let cursor = ProviderConnectionProbe(provider: .cursor, reading: .awaitingUsage, signInAvailability: .available)
        cursor.update {
            $0.accounts = [active, team]
            $0.signInGate = gate
        }
        let runtime = ProviderUsageRuntime(connections: [cursor], now: { [start] in start }, onChange: {})

        let signIn = Task { await runtime.perform(.addAccount, on: .cursor) }
        await gate.waitUntilReached()

        #expect(await runtime.perform(.switchAccount(team.id), on: .cursor) == ProviderNotice(title: "Finish signing in first", detail: "Or cancel the sign-in."))
        #expect(cursor.switchedTo == [])
        await gate.open()
        _ = await signIn.value
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

@MainActor
private final class Flag {
    var isSet = false
}
