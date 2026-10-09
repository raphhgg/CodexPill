import Testing

@testable import CodexPill

struct RemoteHostTests {
    @Test
    func blankDisplayNameFallsBackToHostname() {
        let host = RemoteHost(destination: "user@buildbox", displayName: "   ")

        #expect(host.displayName == "buildbox")
    }
}
