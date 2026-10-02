/// A single, bounded transaction. Generation tokens prevent late accessibility
/// replies from releasing a newer click. Access only from the event-tap run loop.
public struct EventBuffer<Event> {
    public private(set) var token: UInt64 = 0
    public private(set) var events: [Event] = []
    public private(set) var isPending = false
    public let capacity: Int

    public init(capacity: Int = 256) { self.capacity = capacity }

    @discardableResult
    public mutating func begin(_ event: Event) -> UInt64 {
        precondition(!isPending)
        token &+= 1
        events = [event]
        isPending = true
        return token
    }

    /// False means the caller must flush before delivering this event normally.
    public mutating func append(_ event: Event) -> Bool {
        guard isPending, events.count < capacity else { return false }
        events.append(event)
        return true
    }

    public mutating func drain(token expected: UInt64) -> [Event] {
        guard isPending, expected == token else { return [] }
        let result = events
        events.removeAll(keepingCapacity: true)
        isPending = false
        return result
    }
}
