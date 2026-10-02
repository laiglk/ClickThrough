import Foundation

/// Cancellation shared between the tap run loop and the AX worker.
public final class CancellationToken {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
