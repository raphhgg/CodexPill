import Foundation
import Testing

@testable import rusage

struct CursorStateDatabaseTokenSourceTests {
    private let jwt = CursorAccessTokenFixtures.jwt(
        subject: "github|user_db",
        expiresAt: CursorAccessTokenFixtures.referenceDate
    )

    @Test
    func missingDatabaseMeansCursorIsNotInstalled() throws {
        let harness = try CursorStateDatabaseHarness()

        let lookup = try source(for: harness).lookup()

        guard case .cursorNotInstalled = lookup else {
            Issue.record("Expected cursorNotInstalled, got \(lookup)")
            return
        }
    }

    @Test
    func missingKeyMeansSignedOut() throws {
        let harness = try CursorStateDatabaseHarness()
        try harness.create()
        try harness.insertText("other", key: "cursorAuth/cachedEmail")
        harness.close()

        let lookup = try source(for: harness).lookup()

        guard case .signedOut = lookup else {
            Issue.record("Expected signedOut, got \(lookup)")
            return
        }
    }

    @Test
    func emptyOrInvalidValueMeansSignedOut() throws {
        for value in ["", "not-a-jwt"] {
            let harness = try CursorStateDatabaseHarness()
            try harness.create()
            try harness.insertText(value)
            harness.close()

            let lookup = try source(for: harness).lookup()

            guard case .signedOut = lookup else {
                Issue.record("Expected signedOut, got \(lookup)")
                return
            }
        }
    }

    @Test
    func utf16LittleEndianBlobYieldsToken() throws {
        let harness = try CursorStateDatabaseHarness()
        try harness.create()
        try harness.insertBlob(jwt.data(using: .utf16LittleEndian)!)
        harness.close()

        #expect(try userID(from: source(for: harness).lookup()) == "user_db")
    }

    @Test
    func utf8BlobYieldsToken() throws {
        let harness = try CursorStateDatabaseHarness()
        try harness.create()
        try harness.insertBlob(Data(jwt.utf8))
        harness.close()

        #expect(try userID(from: source(for: harness).lookup()) == "user_db")
    }

    @Test
    func textValueYieldsToken() throws {
        let harness = try CursorStateDatabaseHarness()
        try harness.create()
        try harness.insertText(jwt)
        harness.close()

        #expect(try userID(from: source(for: harness).lookup()) == "user_db")
    }

    @Test
    func decodeTokenValueHandlesKnownEncodings() {
        #expect(CursorStateDatabaseTokenSource.decodeTokenValue(Data([0x61, 0x00, 0x62, 0x00])) == "ab")
        #expect(CursorStateDatabaseTokenSource.decodeTokenValue(Data("ab".utf8)) == "ab")
        #expect(CursorStateDatabaseTokenSource.decodeTokenValue(Data("é".utf8)) == "é")
        #expect(CursorStateDatabaseTokenSource.decodeTokenValue(Data([0x3D, 0xD8, 0x00, 0xDE])) == "😀")
        #expect(CursorStateDatabaseTokenSource.decodeTokenValue(Data([0x00, 0xD8])) == nil)
    }

    @Test
    func rollbackJournalDatabaseIsReadWithoutAddingFiles() throws {
        let harness = try CursorStateDatabaseHarness()
        try harness.create()
        try harness.insertText(jwt)
        harness.close()
        let before = try harness.directoryListing()

        let lookup = try source(for: harness).lookup()

        #expect(userID(from: lookup) == "user_db")
        #expect(try harness.directoryListing() == before)
        #expect(before == ["state.vscdb"])
    }

    @Test
    func hotRollbackJournalIsNeverReadPastAsIfTheDatabaseWereIdle() throws {
        let harness = try CursorStateDatabaseHarness()
        try harness.create()
        try harness.insertText(jwt)
        let uncommitted = CursorAccessTokenFixtures.jwt(subject: "github|user_uncommitted", expiresAt: CursorAccessTokenFixtures.referenceDate)
        let crashCopy = try harness.copyWithHotJournal(replacingAccessTokenWith: uncommitted)

        #expect(throws: CursorStateDatabaseError.busy) {
            try CursorStateDatabaseTokenSource(databaseURL: crashCopy).lookup()
        }
    }

    @Test
    func idleWALDatabaseIsReadImmutablyWithoutCreatingSidecars() throws {
        let harness = try CursorStateDatabaseHarness()
        try harness.create(walMode: true)
        try harness.insertText(jwt)
        try harness.closeAndRemoveWALSidecars()
        let before = try harness.directoryListing()

        let lookup = try source(for: harness).lookup()

        #expect(userID(from: lookup) == "user_db")
        #expect(before == ["state.vscdb"])
        #expect(try harness.directoryListing() == before)
    }

    @Test
    func liveWALDatabaseIsReadWhileWriterIsOpen() throws {
        let harness = try CursorStateDatabaseHarness()
        try harness.create(walMode: true)
        try harness.insertText(jwt)
        let before = try harness.directoryListing()

        let lookup = try source(for: harness).lookup()

        #expect(userID(from: lookup) == "user_db")
        #expect(before == ["state.vscdb", "state.vscdb-shm", "state.vscdb-wal"])
        #expect(try harness.directoryListing() == before)
    }

    @Test
    func theCachedEmailComesWithTheTokenWithoutItsJSONQuotes() throws {
        let harness = try CursorStateDatabaseHarness()
        try harness.create()
        try harness.insertText(jwt)
        try harness.insertText(#""person@example.com""#, key: "cursorAuth/cachedEmail")
        harness.close()
        let withoutEmail = try CursorStateDatabaseHarness()
        try withoutEmail.create()
        try withoutEmail.insertText(jwt)
        withoutEmail.close()

        guard case let .token(_, email) = try source(for: harness).lookup(),
              case let .token(_, missingEmail) = try source(for: withoutEmail).lookup()
        else {
            Issue.record("Expected a token")
            return
        }
        #expect(email == "person@example.com")
        #expect(missingEmail == nil)
    }

    private func source(for harness: CursorStateDatabaseHarness) -> CursorStateDatabaseTokenSource {
        CursorStateDatabaseTokenSource(databaseURL: harness.databaseURL)
    }

    private func userID(from lookup: CursorAccessTokenLookup) -> String? {
        guard case .token(let token, _) = lookup else { return nil }
        return token.userID
    }
}
