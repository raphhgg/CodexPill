import Testing

@testable import CodexPill

struct ProviderUsageMenuCopyTests {
    private let reasons: [UsageUnavailableReason] = [
        .signedOut, .signInExpired, .keychainAccessNeeded, .signInUnreadable, .accessDenied,
        .rateLimited, .unreachable, .serviceError, .unexpectedResponse,
    ]

    @Test
    func everyClaudeFailureReadsDifferentlySoA403NeverSaysAnthropicIsUnreachable() {
        let titles = reasons.map { UsageProvider.claude.unavailableMessage(for: $0).title }

        #expect(Set(titles).count == reasons.count)
        #expect(UsageProvider.claude.unavailableMessage(for: .accessDenied).title.contains("reach") == false)
    }

    @Test
    func menuCopyIsATitleAndAtMostOneShortLine() {
        for reason in reasons {
            let message = UsageProvider.claude.unavailableMessage(for: reason)
            #expect(message.title.count <= 40)
            #expect((message.detail?.count ?? 0) <= 40)
            #expect(message.detail?.filter { $0 == "." }.count ?? 0 <= 1)
        }
    }
}
