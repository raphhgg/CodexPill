import Foundation

/// Cursor plan usage for the menu, read from Cursor's live sign-in once the user connects it, or from rusage's own
/// Cursor sign-in, kept apart from Cursor's.
struct CursorUsage: ProviderConnection {
    let provider = UsageProvider.cursor
    let staleAfter: TimeInterval = 15 * 60
    let refreshInterval: TimeInterval

    let settings: SettingsCell<CursorSettings>
    let client: CursorUsageClient
    /// Daily tokens for the Token Usage card, read from the same sign-in.
    let tokenUsageClient: CursorTokenUsageClient?
    /// rusage's own sign-in and the source that picks it or Cursor's. Nil where it isn't offered.
    let ownSignInClient: CursorOwnSignIn?
    let tokenSource: CursorSignInTokenSource?

    init(
        settings: SettingsCell<CursorSettings>,
        client: CursorUsageClient,
        tokenUsageClient: CursorTokenUsageClient? = nil,
        ownSignInClient: CursorOwnSignIn? = nil,
        tokenSource: CursorSignInTokenSource? = nil,
        refreshInterval: TimeInterval = ProviderUsageRuntime.refreshInterval
    ) {
        self.settings = settings
        self.client = client
        self.tokenUsageClient = tokenUsageClient
        self.ownSignInClient = ownSignInClient
        self.tokenSource = tokenSource
        self.refreshInterval = refreshInterval
    }

    func connect() async {
        settings.update { $0.isConnected = true }
        tokenSource?.allowPromptOnce()
    }

    var ownSignIn: ProviderOwnSignIn {
        guard ownSignInClient != nil else { return .unsupported }
        return settings.value.usesOwnSignIn ? .signedIn : .signedOut
    }

    /// Replaces an earlier own sign-in. Cursor's own sign-in is untouched.
    func signIn() async throws(ProviderNotice) {
        guard let ownSignInClient else { return }
        do {
            try await ownSignInClient.signIn()
        } catch {
            switch error {
            case .timedOut: throw ProviderNotice(title: "Cursor sign-in didn't finish", detail: "Try again.")
            case .unreachable: throw ProviderNotice(title: "Can't reach Cursor", detail: "Try again in a moment.")
            case .notSaved: throw ProviderNotice(title: "Cursor sign-in not saved", detail: "Allow rusage to use the Keychain, then try again.")
            }
        }
        settings.update {
            $0.isConnected = true
            $0.usesOwnSignIn = true
        }
    }

    /// Reads go back to the Cursor app's sign-in.
    func signOut() async throws(ProviderNotice) {
        guard let ownSignInClient else { return }
        settings.update { $0.usesOwnSignIn = false }
        guard await ownSignInClient.signOut() else {
            throw ProviderNotice(title: "Cursor sign-in not removed", detail: "Remove it in Keychain Access.")
        }
    }

    var isConnected: Bool {
        settings.value.isConnected
    }

    /// Also drops rusage's own sign-in, so nothing is kept for a tool the user turned off.
    func disconnect() async {
        let usedOwnSignIn = settings.value.usesOwnSignIn
        settings.update {
            $0.isConnected = false
            $0.usesOwnSignIn = false
        }
        if usedOwnSignIn {
            _ = await ownSignInClient?.signOut()
        }
    }

    func readUsage(now _: Date) async -> UsageProviderReading {
        let current = settings.value
        guard current.isConnected else { return .notConnected }
        if current.usesOwnSignIn {
            await ownSignInClient?.refreshIfNeeded()
        }
        return Self.reading(from: await client.refresh())
    }

    static func reading(from status: CursorUsageStatus) -> UsageProviderReading {
        switch status {
        case .cursorNotInstalled: .unavailable(.notInstalled)
        case .signedOut: .unavailable(.signedOut)
        case .tokenExpired, .unauthorized: .unavailable(.signInExpired)
        case .unavailable(.localStateUnreadable): .unavailable(.signInUnreadable)
        case .unavailable(.keychainAccessNeeded): .unavailable(.keychainAccessNeeded)
        case .unavailable(.localStateBusy): .unavailable(.signInBusy)
        case .unavailable(.network): .unavailable(.unreachable)
        case .unavailable(.forbidden): .unavailable(.accessDenied)
        case .unavailable(.rateLimited): .unavailable(.rateLimited)
        case .unavailable(.serviceError): .unavailable(.serviceError)
        case .unavailable(.unexpectedResponse): .unavailable(.unexpectedResponse)
        case let .available(snapshot): .snapshot(usage(from: snapshot))
        }
    }

    static func usage(from snapshot: CursorUsageSnapshot) -> UsageSnapshot {
        let windows = snapshot.includedUsagePercent.map { percent in
            [UsageWindow(
                kind: .billingCycle,
                usedPercent: Int(percent.rounded()),
                resetsAt: snapshot.billingCycle?.end,
                durationMinutes: snapshot.billingCycle.map { Int($0.duration / 60) }
            )]
        } ?? []
        return UsageSnapshot(
            provider: .cursor,
            planName: snapshot.planName,
            windows: windows,
            fetchedAt: snapshot.fetchedAt,
            credits: snapshot.onDemand.map { .extraUsage(spent: $0.usedUSD, limit: $0.limitUSD, currencyCode: "USD") },
            accountEmail: snapshot.accountEmail
        )
    }
}
