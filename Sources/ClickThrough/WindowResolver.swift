import AppKit
import ApplicationServices
import ClickThroughCore

/// Used only on the resolver queue. No synchronous AX calls in the event tap.
struct WindowTarget {
    let pid: pid_t
    let window: AXUIElement
    let application: AXUIElement
    let point: CGPoint
}

final class WindowResolver {
    private let system = AXUIElementCreateSystemWide()

    init() { AXUIElementSetMessagingTimeout(system, 0.035) }

    func target(at point: CGPoint, excluded: Set<String>) -> WindowTarget? {
        guard let hit = element(at: point) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(hit, &pid) == .success,
              pid != ProcessInfo.processInfo.processIdentifier,
              let running = NSRunningApplication(processIdentifier: pid),
              running.activationPolicy == .regular,
              let bundleID = running.bundleIdentifier,
              !excluded.contains(bundleID),
              !["com.apple.loginwindow", "com.apple.systempreferences"].contains(bundleID),
              let window = window(of: hit),
              string(window, kAXSubroleAttribute) == kAXStandardWindowSubrole as String
        else { return nil }

        // Window controls and sheets retain the normal system behavior.
        let chrome = [kAXCloseButtonSubrole, kAXMinimizeButtonSubrole,
                      kAXZoomButtonSubrole, kAXFullScreenButtonSubrole] as [String]
        if let subrole = string(hit, kAXSubroleAttribute), chrome.contains(subrole) { return nil }
        if let children = attribute(window, kAXChildrenAttribute) as? [AXUIElement],
           children.contains(where: { string($0, kAXRoleAttribute) == kAXSheetRole as String }) { return nil }

        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.035)
        AXUIElementSetMessagingTimeout(window, 0.035)
        let target = WindowTarget(pid: pid, window: window, application: app, point: point)
        return isFocused(target) ? nil : target
    }

    func raise(_ target: WindowTarget, cancellation: CancellationToken) {
        guard !cancellation.isCancelled else { return }
        AXUIElementPerformAction(target.window, kAXRaiseAction as CFString)
        guard !cancellation.isCancelled else { return }
        AXUIElementSetAttributeValue(target.application, kAXFocusedWindowAttribute as CFString, target.window)
        guard !cancellation.isCancelled else { return }
        AXUIElementSetAttributeValue(target.window, kAXMainAttribute as CFString, kCFBooleanTrue)
    }

    func isFocused(_ target: WindowTarget) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid,
              let focused = elementAttribute(target.application, kAXFocusedWindowAttribute)
        else { return false }
        return CFEqual(focused, target.window)
    }

    /// Web content can temporarily disappear from the AX tree during a page
    /// repaint. nil means unknown, while false means AX found another window.
    func stillUnderPointer(_ target: WindowTarget) -> Bool? {
        guard let hit = element(at: target.point), let currentWindow = window(of: hit) else { return nil }
        return CFEqual(currentWindow, target.window)
    }

    private func element(at point: CGPoint) -> AXUIElement? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success else { return nil }
        return hit
    }

    /// Kept as a named helper for diagnostics. CGEvent.location already uses
    /// the global top-left space expected by Accessibility hit testing.
    func accessibilityPoint(for quartzPoint: CGPoint) -> CGPoint {
        quartzPoint
    }

    private func window(of element: AXUIElement) -> AXUIElement? {
        if string(element, kAXRoleAttribute) == kAXWindowRole as String { return element }
        return elementAttribute(element, kAXWindowAttribute)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }
}
