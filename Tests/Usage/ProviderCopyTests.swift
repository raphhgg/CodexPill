import Testing

@testable import Refill

struct ProviderCopyTests {
    private let reasons: [UsageUnavailableReason] = [
        .signedOut, .signInExpired, .keychainAccessNeeded, .signInUnreadable, .signInBusy, .accessDenied,
        .rateLimited, .unreachable, .serviceError, .unexpectedResponse,
    ]

    @Test
    func everyClaudeFailureReadsDifferentlySoA403NeverSaysAnthropicIsUnreachable() {
        let titles = reasons.map { UsageProvider.claude.copy.unavailableMessage(for: $0).title }

        #expect(Set(titles).count == reasons.count)
        #expect(UsageProvider.claude.copy.unavailableMessage(for: .accessDenied).title.contains("reach") == false)
    }

    @Test
    func aBusyCursorDatabaseIsTransientNotASignInProblem() {
        let message = UsageProvider.cursor.copy.unavailableMessage(for: .signInBusy)

        #expect(message.title == "Cursor is busy")
        #expect(message.detail == "Retrying in a few minutes.")
    }

    @Test
    func menuCopyIsATitleAndAtMostOneShortLine() {
        for provider in [UsageProvider.claude, .cursor] {
            for reason in reasons {
                let message = provider.copy.unavailableMessage(for: reason)
                #expect(message.title.count <= 40)
                #expect((message.detail?.count ?? 0) <= 40)
                #expect(message.detail?.filter { $0 == "." }.count ?? 0 <= 1)
            }
        }
    }
}
