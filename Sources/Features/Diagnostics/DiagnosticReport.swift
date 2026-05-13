import Foundation

struct DiagnosticAppMetadata: Codable, Equatable {
    let appVersion: String
    let buildNumber: String
    let bundleIdentifier: String

    static func current(bundle: Bundle = .main) -> Self {
        Self(
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            bundleIdentifier: bundle.bundleIdentifier ?? "unknown"
        )
    }
}

struct DiagnosticSystemMetadata: Codable, Equatable {
    let macOSVersion: String
    let exportTimestamp: Date
    let localeIdentifier: String
    let timeZoneIdentifier: String
    let architecture: String
    let isSandboxed: Bool

    static func current(
        now: Date = .now,
        processInfo: ProcessInfo = .processInfo,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Self {
        let version = processInfo.operatingSystemVersion
        return Self(
            macOSVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            exportTimestamp: now,
            localeIdentifier: Locale.current.identifier,
            timeZoneIdentifier: TimeZone.current.identifier,
            architecture: currentArchitecture(),
            isSandboxed: environment["APP_SANDBOX_CONTAINER_ID"] != nil
        )
    }

    private static func currentArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}

struct DiagnosticReport: Codable, Equatable {
    let schemaVersion: Int
    let app: DiagnosticAppMetadata
    let system: DiagnosticSystemMetadata
    let environment: DiagnosticEnvironmentMetadata
    let accounts: [DiagnosticAccount]
    let hosts: [DiagnosticHost]
    let freshness: [DiagnosticFreshnessState]
    let events: [DiagnosticEvent]
    let decisionTraces: [DiagnosticDecisionTrace]
    let redactionManifest: DiagnosticRedactionManifest
}

struct DiagnosticEnvironmentMetadata: Codable, Equatable {
    let refreshIntervalMinutes: Int
    let visibleInactiveAccountCount: Int
    let notificationsWhenBlockedEnabled: Bool
    let notificationsWhenOutEnabled: Bool
    let notificationAuthorizationState: String
    let statusBarDisplayMode: String
}

struct DiagnosticAccount: Codable, Equatable {
    let alias: String
    let roles: [String]
    let planCategory: String
    let hasRateLimitSnapshot: Bool
    let sessionUsageCategory: String
    let weeklyUsageCategory: String
}

struct DiagnosticHost: Codable, Equatable {
    let alias: String
    let connectionState: String
    let verificationStatus: String
    let desiredAccountAlias: String?
    let activeAccountAlias: String?
    let detectedAccountAlias: String?
    let deployedAccountAliases: [String]
}

struct DiagnosticFreshnessState: Codable, Equatable {
    let subjectAlias: String
    let subjectKind: String
    let state: String
    let ageSeconds: Int?
}

struct DiagnosticEvent: Codable, Equatable {
    let name: String
    let category: String
    let occurredAt: Date
    let fields: [String: String]
}

struct DiagnosticDecisionTrace: Codable, Equatable {
    let subjectAlias: String?
    let subjectKind: String
    let decision: String
    let reasonCode: String
}

struct DiagnosticRedactionManifest: Codable, Equatable {
    let policy: String
    let aliasScope: String
    let omittedFieldClasses: [String]
    let summarizedFieldClasses: [String]
    let rejectedFields: [String]
}

enum DiagnosticEventCategory: String, Codable, Equatable {
    case addAccount = "add_account"
    case switchAccount = "switch_account"
    case removeAccount = "remove_account"
    case addHost = "add_host"
    case refresh = "refresh"
    case notificationEvaluation = "notification_evaluation"
    case failure = "failure"
    case decision = "decision"
    case menuAction = "menu_action"
}

enum DiagnosticRedactionClass: String, Codable, Equatable {
    case accountAlias
    case hostAlias
    case reasonCode
    case resultCategory
    case boolean
}

struct DiagnosticWorkflowEvent: Equatable {
    let name: String
    let category: DiagnosticEventCategory
    let occurredAt: Date
    let fields: [DiagnosticEventField]

    init(
        name: String,
        category: DiagnosticEventCategory,
        occurredAt: Date = .now,
        fields: [DiagnosticEventField] = []
    ) {
        self.name = name
        self.category = category
        self.occurredAt = occurredAt
        self.fields = fields
    }
}

struct DiagnosticEventField: Equatable {
    enum Value: Equatable {
        case string(String)
        case account(UUID)
        case hostDestination(String)
        case boolean(Bool)
    }

    let name: String
    let value: Value
    let redaction: DiagnosticRedactionClass?

    static func string(name: String, value: String, redaction: DiagnosticRedactionClass?) -> Self {
        Self(name: name, value: .string(value), redaction: redaction)
    }

    static func account(_ id: UUID, redaction: DiagnosticRedactionClass?) -> Self {
        Self(name: "account", value: .account(id), redaction: redaction)
    }

    static func hostDestination(_ destination: String, redaction: DiagnosticRedactionClass?) -> Self {
        Self(name: "host", value: .hostDestination(destination), redaction: redaction)
    }

    static func boolean(name: String, value: Bool, redaction: DiagnosticRedactionClass?) -> Self {
        Self(name: name, value: .boolean(value), redaction: redaction)
    }
}

struct DiagnosticReportBuilder {
    let appMetadata: DiagnosticAppMetadata
    let systemMetadata: DiagnosticSystemMetadata
    var maximumEventCount = 50

    init(
        appMetadata: DiagnosticAppMetadata = .current(),
        systemMetadata: DiagnosticSystemMetadata = .current()
    ) {
        self.appMetadata = appMetadata
        self.systemMetadata = systemMetadata
    }

    func makeReport(
        state: MenuBarMenuState,
        events: [DiagnosticWorkflowEvent]
    ) -> DiagnosticReport {
        var aliases = DiagnosticAliasContext()
        let accounts = diagnosticAccounts(from: state, aliases: &aliases)
        let hosts = state.remoteHosts.map { diagnosticHost(from: $0, aliases: &aliases) }
        let rejectedFields = RejectedDiagnosticFields()
        let diagnosticEvents = events.suffix(maximumEventCount).map {
            diagnosticEvent(from: $0, aliases: &aliases, rejectedFields: rejectedFields)
        }

        return DiagnosticReport(
            schemaVersion: 1,
            app: appMetadata,
            system: systemMetadata,
            environment: DiagnosticEnvironmentMetadata(
                refreshIntervalMinutes: state.refreshIntervalMinutes,
                visibleInactiveAccountCount: state.visibleInactiveAccountCount,
                notificationsWhenBlockedEnabled: state.notificationsWhenBlockedEnabled,
                notificationsWhenOutEnabled: state.notificationsWhenOutEnabled,
                notificationAuthorizationState: String(describing: state.notificationAuthorizationState),
                statusBarDisplayMode: state.effectiveStatusBarDisplayMode.rawValue
            ),
            accounts: accounts,
            hosts: hosts,
            freshness: diagnosticFreshness(from: state, aliases: &aliases),
            events: diagnosticEvents,
            decisionTraces: diagnosticDecisionTraces(from: state, aliases: &aliases),
            redactionManifest: DiagnosticRedactionManifest(
                policy: "deny-by-default allowlisted diagnostic fields only",
                aliasScope: "per-export",
                omittedFieldClasses: [
                    "raw_logs",
                    "raw_auth_json",
                    "saved_auth_snapshots",
                    "raw_user_defaults",
                    "raw_ssh_output",
                    "stderr",
                    "emails",
                    "hostnames",
                    "local_paths",
                    "tokens",
                    "refresh_tokens",
                    "stable_account_ids",
                    "prompt_or_session_content"
                ],
                summarizedFieldClasses: [
                    "plan_type",
                    "rate_limit_usage",
                    "refresh_freshness",
                    "workflow_result",
                    "decision_reason"
                ],
                rejectedFields: rejectedFields.values
            )
        )
    }

    private func diagnosticAccounts(
        from state: MenuBarMenuState,
        aliases: inout DiagnosticAliasContext
    ) -> [DiagnosticAccount] {
        state.allSavedAccounts.map { account in
            var roles: [String] = []
            if state.activeAccount?.id == account.id {
                roles.append("active_local")
            }
            if roles.isEmpty {
                roles.append("saved")
            }

            return DiagnosticAccount(
                alias: aliases.accountAlias(for: account.id),
                roles: roles,
                planCategory: normalizedCodexPlanType(account.effectivePlanType) ?? "unknown",
                hasRateLimitSnapshot: account.rateLimits != nil,
                sessionUsageCategory: usageCategory(for: account.rateLimits?.sessionWindow),
                weeklyUsageCategory: usageCategory(for: account.rateLimits?.weeklyWindow)
            )
        }
    }

    private func diagnosticHost(
        from host: RemoteHostMenuState,
        aliases: inout DiagnosticAliasContext
    ) -> DiagnosticHost {
        DiagnosticHost(
            alias: aliases.hostAlias(for: host.destination),
            connectionState: host.connectionState.rawValue,
            verificationStatus: host.verificationStatus.rawValue,
            desiredAccountAlias: host.desiredAccount.map { aliases.accountAlias(for: $0.id) },
            activeAccountAlias: host.activeAccount.map { aliases.accountAlias(for: $0.id) },
            detectedAccountAlias: host.detectedAccount.map { aliases.accountAlias(for: $0.id) },
            deployedAccountAliases: host.deployedAccountIDs.map { aliases.accountAlias(for: $0) }
        )
    }

    private func diagnosticFreshness(
        from state: MenuBarMenuState,
        aliases: inout DiagnosticAliasContext
    ) -> [DiagnosticFreshnessState] {
        var freshness = state.allSavedAccounts.map { account in
            freshnessState(
                subjectAlias: aliases.accountAlias(for: account.id),
                subjectKind: "account",
                fetchedAt: account.rateLimits?.fetchedAt
            )
        }

        freshness.append(contentsOf: state.remoteHosts.map { host in
            DiagnosticFreshnessState(
                subjectAlias: aliases.hostAlias(for: host.destination),
                subjectKind: "host",
                state: host.connectionState == .syncing ? "refreshing" : "current_state_only",
                ageSeconds: nil
            )
        })
        return freshness
    }

    private func freshnessState(
        subjectAlias: String,
        subjectKind: String,
        fetchedAt: Date?
    ) -> DiagnosticFreshnessState {
        guard let fetchedAt else {
            return DiagnosticFreshnessState(
                subjectAlias: subjectAlias,
                subjectKind: subjectKind,
                state: "missing",
                ageSeconds: nil
            )
        }

        let age = max(0, Int(systemMetadata.exportTimestamp.timeIntervalSince(fetchedAt)))
        let state: String
        switch age {
        case 0..<300:
            state = "fresh"
        case 300..<1800:
            state = "aging"
        default:
            state = "stale"
        }
        return DiagnosticFreshnessState(
            subjectAlias: subjectAlias,
            subjectKind: subjectKind,
            state: state,
            ageSeconds: age
        )
    }

    private func diagnosticEvent(
        from event: DiagnosticWorkflowEvent,
        aliases: inout DiagnosticAliasContext,
        rejectedFields: RejectedDiagnosticFields
    ) -> DiagnosticEvent {
        var fields: [String: String] = [:]
        for field in event.fields {
            guard let redaction = field.redaction else {
                rejectedFields.append("events.\(event.name).\(field.name)")
                continue
            }

            switch (redaction, field.value) {
            case (.accountAlias, .account(let id)):
                fields[field.name] = aliases.accountAlias(for: id)
            case (.hostAlias, .hostDestination(let destination)):
                fields[field.name] = aliases.hostAlias(for: destination)
            case (.reasonCode, .string(let value)), (.resultCategory, .string(let value)):
                fields[field.name] = diagnosticCode(value)
            case (.boolean, .boolean(let value)):
                fields[field.name] = value ? "true" : "false"
            default:
                rejectedFields.append("events.\(event.name).\(field.name)")
            }
        }

        return DiagnosticEvent(
            name: diagnosticCode(event.name),
            category: event.category.rawValue,
            occurredAt: event.occurredAt,
            fields: fields
        )
    }

    private func diagnosticDecisionTraces(
        from state: MenuBarMenuState,
        aliases: inout DiagnosticAliasContext
    ) -> [DiagnosticDecisionTrace] {
        var traces: [DiagnosticDecisionTrace] = []
        if state.activeAccount == nil {
            traces.append(.init(
                subjectAlias: nil,
                subjectKind: "local_account",
                decision: "account_unavailable",
                reasonCode: "no_active_saved_account"
            ))
        }

        for account in state.allSavedAccounts where account.rateLimits == nil {
            traces.append(.init(
                subjectAlias: aliases.accountAlias(for: account.id),
                subjectKind: "account",
                decision: "limit_state_unavailable",
                reasonCode: "missing_rate_limit_snapshot"
            ))
        }

        for host in state.remoteHosts {
            let hostAlias = aliases.hostAlias(for: host.destination)
            if host.connectionState == .disconnected {
                traces.append(.init(
                    subjectAlias: hostAlias,
                    subjectKind: "host",
                    decision: "host_unavailable",
                    reasonCode: "host_disconnected"
                ))
            }
            if host.verificationStatus == .failed {
                traces.append(.init(
                    subjectAlias: hostAlias,
                    subjectKind: "host",
                    decision: "switch_blocked",
                    reasonCode: "host_verification_failed"
                ))
            }
        }
        return traces
    }

    private func usageCategory(for window: CodexRateLimitWindow?) -> String {
        guard let window else { return "unknown" }
        switch window.displayedUsedPercent(at: systemMetadata.exportTimestamp) {
        case 0..<50:
            return "available"
        case 50..<90:
            return "limited"
        default:
            return "exhausted"
        }
    }
}

private final class RejectedDiagnosticFields {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }
}

private struct DiagnosticAliasContext {
    private var accountAliases: [UUID: String] = [:]
    private var hostAliases: [String: String] = [:]

    mutating func accountAlias(for id: UUID) -> String {
        if let alias = accountAliases[id] {
            return alias
        }
        let alias = "account-\(accountAliases.count + 1)"
        accountAliases[id] = alias
        return alias
    }

    mutating func hostAlias(for destination: String) -> String {
        if let alias = hostAliases[destination] {
            return alias
        }
        let alias = "host-\(hostAliases.count + 1)"
        hostAliases[destination] = alias
        return alias
    }
}

private func diagnosticCode(_ value: String) -> String {
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
    let scalars = value.unicodeScalars.map { scalar in
        allowed.contains(scalar) ? Character(scalar) : "_"
    }
    let collapsed = String(scalars)
        .split(separator: "_", omittingEmptySubsequences: true)
        .joined(separator: "_")
        .lowercased()
    return collapsed.isEmpty ? "unknown" : collapsed
}
