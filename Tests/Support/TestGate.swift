/// Holds every caller of `pass()` until the test opens the gate.
actor TestGate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var arrival: CheckedContinuation<Void, Never>?

    func pass() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
            arrival?.resume()
            arrival = nil
        }
    }

    func waitUntilReached() async {
        guard waiting.isEmpty else { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}
