import Foundation
import Testing

@testable import RUsage

struct CursorAccessTokenTests {
    private let now = CursorAccessTokenFixtures.referenceDate

    @Test
    func tokenIsUsableOnlyWhenMoreThanSixtySecondsRemain() throws {
        let usable = try #require(CursorAccessToken(jwt: CursorAccessTokenFixtures.jwt(expiresAt: now.addingTimeInterval(61))))
        let nearlyExpired = try #require(CursorAccessToken(jwt: CursorAccessTokenFixtures.jwt(expiresAt: now.addingTimeInterval(60))))

        #expect(usable.isUsable(at: now))
        #expect(!nearlyExpired.isUsable(at: now))
        #expect(usable.expiresAt == now.addingTimeInterval(61))
    }

    @Test
    func tokenWithoutExpirationIsRejected() {
        let jwt = CursorAccessTokenFixtures.jwt(claims: ["sub": "auth0|user_abc"])

        #expect(CursorAccessToken(jwt: jwt) == nil)
    }

    @Test
    func nonJWTValuesAreRejected() {
        #expect(CursorAccessToken(jwt: "") == nil)
        #expect(CursorAccessToken(jwt: "not-a-jwt") == nil)
        #expect(CursorAccessToken(jwt: "header.%%%.signature") == nil)
    }

    @Test
    func userIDWithCookieUnsafeCharactersIsRejected() {
        let jwt = CursorAccessTokenFixtures.jwt(subject: "auth0|user;abc", expiresAt: now)

        #expect(CursorAccessToken(jwt: jwt) == nil)
    }

    @Test
    func cookieHeaderUsesLastSubjectSegmentAndTrimmedJWT() throws {
        let jwt = CursorAccessTokenFixtures.jwt(subject: "auth0|user_abc", expiresAt: now)
        let token = try #require(CursorAccessToken(jwt: "  \(jwt)\n"))

        #expect(token.userID == "user_abc")
        #expect(token.cookieHeaderValue == "WorkosCursorSessionToken=user_abc%3A%3A" + jwt)
    }

    @Test
    func descriptionsAndReflectionRedactTheToken() throws {
        let jwt = CursorAccessTokenFixtures.jwt(expiresAt: now)
        let token = try #require(CursorAccessToken(jwt: jwt))
        var dumped = ""
        dump(token, to: &dumped)

        #expect("\(token)" == "CursorAccessToken(redacted)")
        #expect(String(reflecting: token) == "CursorAccessToken(redacted)")
        #expect(!dumped.contains(jwt))
        #expect(!dumped.contains("user_abc"))
    }
}
