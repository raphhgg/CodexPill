import Foundation
import Testing

@testable import CodexPill

struct TokenUsageCacheFileStoreTests {
    @Test
    func readsBackEveryWrittenEntryAndReplacesSameKey() throws {
        let store = makeStore()

        try store.writeEntry(TestEntry(total: 100), forKey: "7")
        try store.writeEntry(TestEntry(total: 300), forKey: "30")
        try store.writeEntry(TestEntry(total: 200), forKey: "7")

        #expect(store.readEntries().map(\.total).sorted() == [200, 300])
    }

    @Test
    func readsNothingWhenCacheFileIsMissing() {
        #expect(makeStore().readEntries().isEmpty)
    }

    @Test
    func corruptCacheFileReadsAsEmptyAndIsReplacedOnWrite() throws {
        let store = makeStore()
        try FileManager.default.createDirectory(
            at: store.cacheFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{not json".utf8).write(to: store.cacheFile)

        #expect(store.readEntries().isEmpty)

        try store.writeEntry(TestEntry(total: 100), forKey: "7")
        #expect(store.readEntries() == [TestEntry(total: 100)])
    }

    @Test
    func ignoresEntriesWrittenWithAnotherSchemaVersion() throws {
        let store = makeStore()
        try store.writeEntry(TestEntry(total: 100), forKey: "7")

        let nextVersionStore = TokenUsageCacheFileStore<TestEntry>(cacheFile: store.cacheFile, schemaVersion: 2)

        #expect(nextVersionStore.readEntries().isEmpty)
        try nextVersionStore.writeEntry(TestEntry(total: 200), forKey: "30")
        #expect(nextVersionStore.readEntries() == [TestEntry(total: 200)])
    }

    @Test
    func writesOwnerOnlyCacheDirectoryAndFile() throws {
        let store = makeStore()

        try store.writeEntry(TestEntry(total: 100), forKey: "7")

        #expect(try posixPermissions(at: store.cacheFile.deletingLastPathComponent()) == 0o700)
        #expect(try posixPermissions(at: store.cacheFile) == 0o600)
    }

    @Test
    func tightensPermissionsOfCacheWrittenByPreviousReleases() throws {
        let store = makeStore()
        let cacheDirectory = store.cacheFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        try Data(#"{"entries":{"7":{"total":100}},"schemaVersion":1}"#.utf8).write(to: store.cacheFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.cacheFile.path)

        try store.writeEntry(TestEntry(total: 300), forKey: "30")

        #expect(store.readEntries().map(\.total).sorted() == [100, 300])
        #expect(try posixPermissions(at: cacheDirectory) == 0o700)
        #expect(try posixPermissions(at: store.cacheFile) == 0o600)
    }

    private struct TestEntry: Codable, Equatable {
        var total: Int
    }

    private func makeStore() -> TokenUsageCacheFileStore<TestEntry> {
        TokenUsageCacheFileStore(
            cacheFile: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent("CodexPill", isDirectory: true)
                .appendingPathComponent("token-usage-cache.json"),
            schemaVersion: 1
        )
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let value = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
        return try #require(value as? Int) & 0o777
    }
}
