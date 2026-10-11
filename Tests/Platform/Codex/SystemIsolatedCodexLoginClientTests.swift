import Testing

@testable import Refill

struct SystemIsolatedCodexLoginClientTests {
    @Test
    func loginFailureReasonRedactsDeviceCodeAndPromptURLQuery() {
        let reason = CodexLoginOutputSanitizer.sanitizedFailureReason(
            from: """
            \u{001B}[94mhttps://auth.openai.com/codex/device?user_code=ABCD-EFGH\u{001B}[0m
            Error logging in with device code: error sending request
            Enter this code ABCD-EFGH
            """
        )

        #expect(reason?.contains("[device code]") == true)
        #expect(reason?.contains("https://auth.openai.com/codex/device") == true)
        #expect(reason?.contains("ABCD-EFGH") == false)
        #expect(reason?.contains("\u{001B}") == false)
    }

    @Test
    func emptyLoginFailureReasonReturnsNil() {
        #expect(CodexLoginOutputSanitizer.sanitizedFailureReason(from: "\n \t") == nil)
    }
}
