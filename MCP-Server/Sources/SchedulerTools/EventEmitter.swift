import Foundation

// ═══════════════════════════════════════════════════════════
// MARK: - EventEmitter
// ═══════════════════════════════════════════════════════════

/// Broadcasts string events to all active SSE subscribers.
/// Thread-safe via NSLock. Clients subscribe via `subscribe()`,
/// receive events through the returned AsyncStream, and unsubscribe
/// by calling `unsubscribe(_:)` or letting the stream deallocate.
public final class EventEmitter: @unchecked Sendable {

    public typealias StreamContinuation = AsyncStream<String>.Continuation

    private var continuations: [UUID: StreamContinuation] = [:]
    private let lock = NSLock()

    public init() {}

    /// Returns a (subscriptionID, stream) pair.
    /// Call `unsubscribe(id)` when done to release resources.
    public func subscribe() -> (UUID, AsyncStream<String>) {
        let id = UUID()
        var continuation: StreamContinuation!
        let stream = AsyncStream<String> { cont in
            continuation = cont
        }
        lock.withLock {
            continuations[id] = continuation
        }
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock {
                self?.continuations.removeValue(forKey: id)
            }
        }
        return (id, stream)
    }

    /// Finish and remove a subscriber.
    public func unsubscribe(_ id: UUID) {
        lock.withLock {
            continuations[id]?.finish()
            continuations.removeValue(forKey: id)
        }
    }

    /// Push an event to all connected subscribers.
    public func emit(_ event: String) {
        lock.withLock {
            for continuation in continuations.values {
                continuation.yield(event)
            }
        }
    }

    /// Number of active subscribers (for diagnostics).
    public var subscriberCount: Int {
        lock.withLock { continuations.count }
    }
}
