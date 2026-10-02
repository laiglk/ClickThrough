import Foundation
import CoreGraphics
import ClickThroughCore

// Runnable with Command Line Tools alone (XCTest requires a full Xcode install).
var passed = 0
func check(_ name: String, _ test: () -> Bool) {
    guard test() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
    passed += 1
    print("PASS: \(name)")
}

check("Quick click is replayed exactly once") {
    var buffer = EventBuffer<String>()
    let token = buffer.begin("down")
    return buffer.append("up") && buffer.drain(token: token) == ["down", "up"] && buffer.drain(token: token).isEmpty
}
check("Drag, release and second click preserve order") {
    var buffer = EventBuffer<String>()
    let token = buffer.begin("down-1")
    for event in ["drag", "up-1", "down-2", "up-2"] {
        guard buffer.append(event) else { return false }
    }
    return buffer.drain(token: token) == ["down-1", "drag", "up-1", "down-2", "up-2"]
}
check("Late AX reply cannot release a newer click") {
    var buffer = EventBuffer<Int>()
    let old = buffer.begin(1)
    guard buffer.drain(token: old) == [1] else { return false }
    let new = buffer.begin(2)
    return buffer.drain(token: old).isEmpty && buffer.isPending && buffer.drain(token: new) == [2]
}
check("Overflow is explicit and all accepted events remain available") {
    var buffer = EventBuffer<Int>(capacity: 3)
    let token = buffer.begin(1)
    return buffer.append(2) && buffer.append(3) && !buffer.append(4)
        && buffer.drain(token: token) == [1, 2, 3] && !buffer.append(5)
}
check("Cancellation prevents a late worker from starting more AX actions") {
    let token = CancellationToken()
    guard !token.isCancelled else { return false }
    token.cancel()
    token.cancel()
    return token.isCancelled
}
check("Real Quartz event metadata survives buffering and replay tagging") {
    guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                             mouseCursorPosition: CGPoint(x: -1440, y: -200), mouseButton: .left),
          let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                           mouseCursorPosition: CGPoint(x: -1400, y: -180), mouseButton: .left) else { return false }
    down.flags = .maskShift
    down.timestamp = 123456789
    down.setIntegerValueField(.mouseEventClickState, value: 2)
    guard let copy = down.copy() else { return false }
    var buffer = EventBuffer<CGEvent>()
    let token = buffer.begin(copy)
    guard buffer.append(up) else { return false }
    let events = buffer.drain(token: token)
    events[0].setIntegerValueField(.eventSourceUserData, value: 42)
    return events.count == 2 && events[0].type == .leftMouseDown && events[1].type == .leftMouseUp
        && events[0].location == CGPoint(x: -1440, y: -200)
        && events[1].location == CGPoint(x: -1400, y: -180)
        && events[0].timestamp == 123456789 && events[0].flags.contains(.maskShift)
        && events[0].getIntegerValueField(.mouseEventClickState) == 2
        && down.getIntegerValueField(.eventSourceUserData) != 42
}
print("\(passed) checks passed.")
