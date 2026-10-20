import Foundation

/// Lets one rusage process at a time renew or change rusage's own Claude sign-in, so two processes never send the same
/// single-use refresh token. It holds an exclusive `flock` on a lock file.
///
/// Each acquisition opens its own file descriptor. A `flock` belongs to the open file, so two holders in one process
/// exclude each other too. Closing the descriptor releases it, and the kernel releases it if rusage crashes.
struct ClaudeRefreshLock: Sendable {
    static let defaultTimeout: Duration = .seconds(30)

    let fileURL: URL
    var timeout: Duration = Self.defaultTimeout
    var pollInterval: Duration = .milliseconds(50)

    /// Runs `body` while holding the lock. Returns nil without running it when the lock stays busy for `timeout`.
    /// It polls instead of blocking, so it never holds up a cooperative thread.
    func withLock<T>(isolation: isolated (any Actor)? = #isolation, _ body: () async -> T) async -> T? {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(fileURL.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        let deadline = ContinuousClock.now.advanced(by: timeout)
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK, ContinuousClock.now < deadline else { return nil }
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                return nil
            }
        }
        return await body()
    }
}
