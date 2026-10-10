import Foundation
import Network
import os

/// Runs one "Sign in with Claude" in the browser and returns the new sign-in. Cancelling the task cancels the sign-in.
protocol ClaudeSignInAuthorizing: Sendable {
    func signIn() async throws -> ClaudeSignIn
}

/// Where the browser lands after the user approves: a redirect URI and the callback that arrives there.
protocol ClaudeOAuthRedirectReceiver: Sendable {
    var redirectURI: URL { get }
    func nextCallback() async throws -> ClaudeOAuthCallback
    func stop()
}

/// OAuth 2.0 authorization code with PKCE (S256) and a loopback redirect, the flow Claude Code uses.
struct ClaudeBrowserSignIn: ClaudeSignInAuthorizing {
    static let defaultTimeout: Duration = .seconds(5 * 60)

    let tokenEndpoint: any ClaudeTokenEndpoint
    let startReceiver: @Sendable () async throws -> any ClaudeOAuthRedirectReceiver
    let openURL: @Sendable (URL) -> Void
    var timeout: Duration = Self.defaultTimeout
    var makePKCE: @Sendable () -> ClaudePKCE = { ClaudePKCE.random() }
    var makeState: @Sendable () -> String = { ClaudeOAuth.randomURLSafeString() }
    var now: @Sendable () -> Date = { Date() }

    func signIn() async throws -> ClaudeSignIn {
        let pkce = makePKCE()
        let state = makeState()
        let receiver = try await startReceiver()
        defer { receiver.stop() }

        openURL(ClaudeOAuth.authorizeURL(redirectURI: receiver.redirectURI, state: state, pkce: pkce))
        let callback = try await withThrowingTaskGroup(of: ClaudeOAuthCallback.self) { group in
            group.addTask { try await receiver.nextCallback() }
            group.addTask { [timeout] in
                try await Task.sleep(for: timeout)
                throw ClaudeSignInError.timedOut
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
        let code = try ClaudeOAuth.authorizationCode(from: callback, expectedState: state)
        do {
            return try await tokenEndpoint.exchange(code: code, pkce: pkce, state: state, redirectURI: receiver.redirectURI, now: now())
        } catch {
            throw ClaudeSignInError.token(error)
        }
    }
}

/// A one-shot HTTP listener on the loopback interface for `http://localhost:<port>/callback`.
/// It answers other paths with 404 and stops after the first callback.
final class LoopbackClaudeOAuthReceiver: ClaudeOAuthRedirectReceiver, @unchecked Sendable {
    private static let maxRequestLength = 16 * 1_024
    private static let page = "<!doctype html><meta charset=utf-8><title>CodexPill</title>"
        + "<p style=\"font:15px -apple-system;margin:3em\">You can close this tab and return to CodexPill.</p>"

    /// Set once the listener is ready, before `start()` returns the receiver.
    private(set) var redirectURI = ClaudeOAuth.redirectURI(port: 0)
    private let listener: NWListener
    private let queue = DispatchQueue(label: "CodexPill.ClaudeOAuthCallback")
    private let lock = NSLock()
    private var waiter: CheckedContinuation<ClaudeOAuthCallback, any Error>?
    private var result: Result<ClaudeOAuthCallback, any Error>?

    private init(listener: NWListener) {
        self.listener = listener
    }

    static func start() async throws -> LoopbackClaudeOAuthReceiver {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.acceptLocalOnly = true
        guard let listener = try? NWListener(using: parameters) else {
            throw ClaudeSignInError.listenerFailed
        }
        let receiver = LoopbackClaudeOAuthReceiver(listener: listener)
        // Network requires the connection handler before `start`.
        listener.newConnectionHandler = { [weak receiver] connection in
            guard let receiver else { return connection.cancel() }
            receiver.handle(connection)
        }
        do {
            receiver.redirectURI = ClaudeOAuth.redirectURI(port: try await receiver.waitUntilReady())
        } catch {
            listener.cancel()
            throw error
        }
        listener.stateUpdateHandler = { [weak receiver] state in
            if case .failed = state { receiver?.finish(.failure(ClaudeSignInError.listenerFailed)) }
        }
        return receiver
    }

    func nextCallback() async throws -> ClaudeOAuthCallback {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let finished = lock.withLock { () -> Result<ClaudeOAuthCallback, any Error>? in
                    if let result { return result }
                    waiter = continuation
                    return nil
                }
                if let finished { continuation.resume(with: finished) }
            }
        } onCancel: {
            finish(.failure(CancellationError()))
        }
    }

    func stop() {
        listener.cancel()
        finish(.failure(CancellationError()))
    }

    private func finish(_ outcome: Result<ClaudeOAuthCallback, any Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<ClaudeOAuthCallback, any Error>? in
            guard result == nil else { return nil }
            result = outcome
            defer { waiter = nil }
            return waiter
        }
        continuation?.resume(with: outcome)
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequestLine(on: connection, buffer: Data())
    }

    private func receiveRequestLine(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maxRequestLength) { [weak self] data, _, isComplete, error in
            guard let self else { return connection.cancel() }
            let received = buffer + (data ?? Data())
            if let lineEnd = received.range(of: Data("\r\n".utf8)) {
                let requestLine = String(decoding: received[..<lineEnd.lowerBound], as: UTF8.self)
                respond(to: requestLine, on: connection)
            } else if error != nil || isComplete || received.count >= Self.maxRequestLength {
                connection.cancel()
            } else {
                receiveRequestLine(on: connection, buffer: received)
            }
        }
    }

    private func respond(to requestLine: String, on connection: NWConnection) {
        let callback = ClaudeOAuth.callback(fromRequestLine: requestLine)
        let status = callback == nil ? "404 Not Found" : "200 OK"
        let body = callback == nil ? "" : Self.page
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
        if let callback {
            finish(.success(callback))
        }
    }

    private func waitUntilReady() async throws -> UInt16 {
        let didResume = OSAllocatedUnfairLock(initialState: false)
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [listener] state in
                let outcome: Result<UInt16, any Error>?
                switch state {
                case .ready:
                    outcome = listener.port.map { .success($0.rawValue) } ?? .failure(ClaudeSignInError.listenerFailed)
                case .failed, .cancelled:
                    outcome = .failure(ClaudeSignInError.listenerFailed)
                default:
                    outcome = nil
                }
                guard let outcome else { return }
                let first = didResume.withLock { resumed in
                    defer { resumed = true }
                    return !resumed
                }
                if first { continuation.resume(with: outcome) }
            }
            listener.start(queue: queue)
        }
    }
}
