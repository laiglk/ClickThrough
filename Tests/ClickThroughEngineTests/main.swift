import Foundation
import ApplicationServices
import ClickThroughCore
@testable import ClickThroughEngine

// Deterministic tests of the real engine: no event tap, app activation, or event posting.
final class ManualScheduler: ClickScheduling {
    private var ready: [() -> Void] = []
    private var delayed: [(time: Int, item: DispatchWorkItem)] = []
    private var now = 0

    func resolve(_ operation: @escaping () -> Void) { ready.append(operation) }
    func complete(_ operation: @escaping () -> Void) { ready.append(operation) }

    @discardableResult
    func after(milliseconds: Int, _ operation: @escaping () -> Void) -> DispatchWorkItem {
        let item = DispatchWorkItem(block: operation)
        delayed.append((now + milliseconds, item))
        return item
    }

    func runReady() {
        var count = 0
        while !ready.isEmpty {
            count += 1
            precondition(count < 100, "Unexpected immediate scheduling loop")
            ready.removeFirst()()
        }
    }

    func advance(milliseconds: Int) {
        now += milliseconds
        let due = delayed.filter { $0.time <= now }.sorted { $0.time < $1.time }
        delayed.removeAll { $0.time <= now }
        for entry in due where !entry.item.isCancelled { entry.item.perform() }
        runReady()
    }
}

final class FakeResolver: WindowResolving {
    var focused = true
    var underPointer: Bool? = true
    var focusChecks = 0
    let window: WindowTarget

    init() {
        let element = AXUIElementCreateApplication(getpid())
        window = WindowTarget(pid: getpid(), window: element, application: element,
                              point: CGPoint(x: -400, y: -200))
    }

    func target(at point: CGPoint, excluded: Set<String>) -> WindowTarget? { window }
    func raise(_ target: WindowTarget, cancellation: CancellationToken) {}
    func isFocused(_ target: WindowTarget) -> Bool { focusChecks += 1; return focused }
    func stillUnderPointer(_ target: WindowTarget) -> Bool? { underPointer }
}

final class RecordingOutput {
    var events: [CGEvent] = []
    var processed = 0
}

final class Fixture {
    let scheduler = ManualScheduler()
    let resolver = FakeResolver()
    let output = RecordingOutput()
    let engine: ClickEngine

    init(failCopyNumber: Int? = nil) {
        let output = output
        var copyCount = 0
        engine = ClickEngine(resolver: resolver, scheduler: scheduler,
                             activateApplication: { _ in true }, postEvent: { output.events.append($0) },
                             copyEvent: { event in
                                 copyCount += 1
                                 return copyCount == failCopyNumber ? nil : event.copy()
                             })
        engine.onClick = { output.processed += 1 }
    }

    @discardableResult
    func send(_ type: CGEventType, number: Int64) -> Unmanaged<CGEvent>? {
        engine.handle(type, mouse(type, number: number))
    }

    var numbers: [Int64] { output.events.map { $0.getIntegerValueField(.mouseEventNumber) } }
}

func mouse(_ type: CGEventType, number: Int64) -> CGEvent {
    let event = CGEvent(mouseEventSource: nil, mouseType: type,
                        mouseCursorPosition: CGPoint(x: -400, y: -200),
                        mouseButton: type == .rightMouseDown ? .right : .left)!
    event.flags = []
    event.setIntegerValueField(.mouseEventClickState, value: 1)
    event.setIntegerValueField(.mouseEventNumber, value: number)
    return event
}

struct TestFailure: Error { let message: String }
func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw TestFailure(message: message) }
}
var passed = 0
var failed = 0
func check(_ name: String, _ test: () throws -> Void) {
    do {
        try test()
        passed += 1
        print("PASS: \(name)")
    } catch {
        failed += 1
        print("FAIL: \(name): \(error)")
    }
}

check("Stable activation replays the original gesture exactly once") {
    let f = Fixture()
    let down = mouse(.leftMouseDown, number: 1)
    down.timestamp = 123456789
    try expect(f.engine.handle(.leftMouseDown, down) == nil, "Initial down must be held")
    f.send(.leftMouseUp, number: 2)
    f.scheduler.runReady()
    try expect(f.output.events.isEmpty, "Do not replay before activation settles")
    f.scheduler.advance(milliseconds: 12)
    try expect(f.numbers == [1, 2], "Replay down/up in order without duplicates")
    try expect(f.output.events[0].timestamp == down.timestamp, "Preserve the original timestamp")
    try expect(f.output.events[0].location == down.location, "Preserve negative display coordinates")
    try expect(f.output.processed == 1, "Count one successful transmission")
    try expect(f.engine.handle(.leftMouseDown, f.output.events[0]) != nil, "Own replay must bypass the tap")
    f.scheduler.advance(milliseconds: 250)
    try expect(f.numbers == [1, 2], "Cancelled watchdog must not replay again")
}

check("Overflow before activation preserves every event including the trailing one") {
    let f = Fixture()
    f.send(.leftMouseDown, number: 1)
    f.send(.leftMouseUp, number: 2)
    for number in 3...257 { f.send(.mouseMoved, number: Int64(number)) }
    try expect(f.numbers == Array(1...257).map(Int64.init), "Replay the full queue in order")
    f.scheduler.runReady()
    try expect(f.output.processed == 0, "A late target must not count or replay the flushed gesture")
}

check("Overflow during unconfirmed activation cancels only the held left gesture") {
    let f = Fixture()
    f.resolver.focused = false
    f.send(.leftMouseDown, number: 1)
    f.scheduler.runReady()
    f.send(.leftMouseUp, number: 2)
    for number in 3...256 { f.send(.mouseMoved, number: Int64(number)) }
    f.send(.rightMouseDown, number: 257)
    try expect(f.numbers == Array(3...257).map(Int64.init), "Cancel left down/up, preserve unrelated events and trailing right click")
    f.scheduler.advance(milliseconds: 250)
    try expect(f.output.processed == 0, "Cancelled activation must not report a transmitted click")
}

check("Overflow while left is held consumes drag and release, then accepts a new gesture") {
    let f = Fixture()
    f.resolver.focused = false
    f.send(.leftMouseDown, number: 1)
    f.scheduler.runReady()
    for number in 2...257 { f.send(.mouseMoved, number: Int64(number)) }
    try expect(f.numbers == Array(2...257).map(Int64.init), "Do not deliver the held left down")
    try expect(f.send(.leftMouseDragged, number: 258) == nil, "Consume drag after cancelling the down")
    try expect(f.send(.leftMouseUp, number: 259) == nil, "Consume release after cancelling the down")
    f.resolver.focused = true
    f.send(.leftMouseDown, number: 260)
    f.send(.leftMouseUp, number: 261)
    f.scheduler.runReady()
    f.scheduler.advance(milliseconds: 12)
    try expect(Array(f.numbers.suffix(2)) == [260, 261], "A new gesture must still work")
}

check("A release causing overflow is cancelled without swallowing the next gesture") {
    let f = Fixture()
    f.resolver.focused = false
    f.send(.leftMouseDown, number: 1)
    f.scheduler.runReady()
    for number in 2...256 { f.send(.mouseMoved, number: Int64(number)) }
    f.send(.leftMouseUp, number: 257)
    try expect(f.numbers == Array(2...256).map(Int64.init), "Cancel the queued down and overflowing release")
    f.resolver.focused = true
    f.send(.leftMouseDown, number: 258)
    f.send(.leftMouseUp, number: 259)
    f.scheduler.runReady()
    f.scheduler.advance(milliseconds: 12)
    try expect(Array(f.numbers.suffix(2)) == [258, 259], "Do not swallow a new gesture after its predecessor was released")
}

check("Copy failure before activation releases the down and passes through the physical up") {
    let f = Fixture(failCopyNumber: 2)
    f.send(.leftMouseDown, number: 1)
    try expect(f.send(.leftMouseUp, number: 2) != nil, "Preserve release when activation has not begun")
    f.scheduler.runReady()
    try expect(f.numbers == [1], "Replay only the previously buffered down")
    try expect(f.output.processed == 0, "Do not count a fallback as successful activation")
}

check("Copy failure during activation cancels both the held down and physical up") {
    let f = Fixture(failCopyNumber: 2)
    f.send(.leftMouseDown, number: 1)
    f.scheduler.runReady()
    try expect(f.send(.leftMouseUp, number: 2) == nil, "Do not send an orphaned release")
    f.scheduler.advance(milliseconds: 12)
    try expect(f.output.events.isEmpty, "Do not release a down after unconfirmed activation")
    try expect(f.output.processed == 0, "Do not count a cancelled gesture")
}

check("Copy failure during activation keeps unrelated input and consumes the cancelled release") {
    let f = Fixture(failCopyNumber: 2)
    f.send(.leftMouseDown, number: 1)
    f.scheduler.runReady()
    try expect(f.send(.rightMouseDown, number: 2) != nil, "Preserve unrelated physical input")
    try expect(f.send(.leftMouseUp, number: 3) == nil, "Consume the cancelled left release")
    f.scheduler.advance(milliseconds: 12)
    try expect(f.output.events.isEmpty, "Do not release the cancelled left down")
}

check("Focus lost during the settle delay cancels the held click") {
    let f = Fixture()
    f.send(.leftMouseDown, number: 1)
    f.send(.leftMouseUp, number: 2)
    f.scheduler.runReady()
    f.resolver.focused = false
    f.scheduler.advance(milliseconds: 12)
    try expect(f.output.events.isEmpty, "A stale focus confirmation must not release the click")
    try expect(f.output.processed == 0, "Cancelled click must not increment the counter")
}

check("Window replaced during the settle delay cancels the held click") {
    let f = Fixture()
    f.send(.leftMouseDown, number: 1)
    f.send(.leftMouseUp, number: 2)
    f.scheduler.runReady()
    f.resolver.underPointer = false
    f.scheduler.advance(milliseconds: 12)
    try expect(f.output.events.isEmpty, "Do not replay to a replacement window")
    try expect(f.output.processed == 0, "Cancelled click must not increment the counter")
}

check("Unknown AX hit after settling still allows a confirmed focused window") {
    let f = Fixture()
    f.send(.leftMouseDown, number: 1)
    f.send(.leftMouseUp, number: 2)
    f.scheduler.runReady()
    f.resolver.underPointer = nil
    f.scheduler.advance(milliseconds: 12)
    try expect(f.numbers == [1, 2], "Preserve the existing web repaint fallback")
}

check("Timeout during activation cancels the gesture and ignores a late focus result") {
    let f = Fixture()
    f.resolver.focused = false
    f.send(.leftMouseDown, number: 1)
    f.send(.leftMouseUp, number: 2)
    f.scheduler.runReady()
    f.resolver.focused = true
    f.scheduler.advance(milliseconds: 250)
    f.scheduler.advance(milliseconds: 12)
    try expect(f.output.events.isEmpty, "Do not replay after the activation deadline")
    try expect(f.output.processed == 0, "Late focus confirmation must not count a timed-out click")
}

check("Stopping before activation releases the original gesture once") {
    let f = Fixture()
    f.send(.leftMouseDown, number: 1)
    f.send(.leftMouseUp, number: 2)
    f.engine.stop()
    f.scheduler.runReady()
    f.scheduler.advance(milliseconds: 250)
    try expect(f.numbers == [1, 2], "Stop before activation must preserve the user's click")
    try expect(f.output.processed == 0, "A stopped transaction must not be counted")
}

check("Stopping during settling cancels the gesture and ignores late work") {
    let f = Fixture()
    f.send(.leftMouseDown, number: 1)
    f.send(.leftMouseUp, number: 2)
    f.scheduler.runReady()
    f.engine.stop()
    f.scheduler.advance(milliseconds: 12)
    f.scheduler.advance(milliseconds: 250)
    try expect(f.output.events.isEmpty, "Stop during activation must not release the click")
    try expect(f.output.processed == 0, "Late work must not count a cancelled transaction")
}

print("\(passed) engine checks passed; \(failed) failed. No live events sent.")
if failed > 0 { exit(1) }
