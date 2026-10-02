import AppKit
import ApplicationServices
import ClickThroughCore

final class ClickEngine {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var buffer = EventBuffer<CGEvent>()
    private let worker = DispatchQueue(label: "fr.clickthrough.accessibility", qos: .userInteractive)
    private let resolver = WindowResolver()
    private let marker: Int64 = 0x43544852554748
    private var resolverBusy = false
    private var watchdog: DispatchWorkItem?
    private var leftIsDown = false
    private var bypassGesture = false
    private var discardLeftUntilUp = false
    private var activationStarted = false
    private var cancellation: CancellationToken?
    var exclusions: Set<String> = []
    var onStatus: ((String) -> Void)?
    var onClick: (() -> Void)?
    var isRunning: Bool { tap != nil }

    func start() -> Bool {
        guard tap == nil else { return true }
        guard AXIsProcessTrusted() else { return false }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .mouseMoved, .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                return Unmanaged<ClickEngine>.fromOpaque(info).takeUnretainedValue().handle(type, event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        tap = newTap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        return true
    }

    func stop() {
        if activationStarted { discardClick(token: buffer.token) }
        else { flush(token: buffer.token) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        tap = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if activationStarted { discardClick(token: buffer.token) }
            else { flush(token: buffer.token) }
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            onStatus?("Le suivi des clics a été rétabli.")
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == marker { return Unmanaged.passUnretained(event) }
        if type == .leftMouseDown { leftIsDown = true }
        if type == .leftMouseUp { leftIsDown = false }
        if discardLeftUntilUp {
            if type == .leftMouseUp { discardLeftUntilUp = false; return nil }
            if type == .leftMouseDragged { return nil }
            if type == .leftMouseDown { discardLeftUntilUp = false }
        }

        if buffer.isPending {
            guard let copy = event.copy() else { flush(token: buffer.token); return Unmanaged.passUnretained(event) }
            if buffer.append(copy) { return nil }
            // Include the current event in the replay so it cannot overtake the queue.
            flush(token: buffer.token, trailing: copy)
            return nil
        }
        if bypassGesture {
            if type == .leftMouseUp { bypassGesture = false }
            return Unmanaged.passUnretained(event)
        }
        guard type == .leftMouseDown, !resolverBusy,
              event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty,
              event.getIntegerValueField(.mouseEventClickState) == 1,
              let copy = event.copy() else { return Unmanaged.passUnretained(event) }

        let token = buffer.begin(copy)
        cancellation = CancellationToken()
        activationStarted = false
        // CGEvent.location is already in the global, top-left display space
        // used by AXUIElementCopyElementAtPosition. Do not mirror it again.
        let point = event.location
        let excluded = exclusions
        resolverBusy = true
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.buffer.isPending, self.buffer.token == token else { return }
            if self.activationStarted {
                self.onStatus?("Activation non confirmée : cliquez à nouveau dans la fenêtre.")
                self.discardClick(token: token)
            } else {
                self.onStatus?("Fenêtre lente : clic transmis normalement.")
                self.flush(token: token)
            }
        }
        watchdog = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250), execute: timeout)
        worker.async { [weak self] in
            guard let self else { return }
            let target = self.resolver.target(at: point, excluded: excluded)
            DispatchQueue.main.async {
                self.resolverBusy = false
                guard self.buffer.isPending, self.buffer.token == token else { return }
                guard let target else { self.flush(token: token); return }
                self.activate(target, token: token)
            }
        }
        return nil
    }

    private func activate(_ target: WindowTarget, token: UInt64) {
        guard let cancellation, !cancellation.isCancelled,
              let app = NSRunningApplication(processIdentifier: target.pid), !app.isTerminated else {
            flush(token: token); return
        }
        activationStarted = true
        if !app.isActive { app.activate(options: [.activateIgnoringOtherApps]) }
        resolverBusy = true
        worker.async {
            self.resolver.raise(target, cancellation: cancellation)
            DispatchQueue.main.async {
                self.resolverBusy = false
                self.checkFocus(target, token: token)
            }
        }
    }

    private func checkFocus(_ target: WindowTarget, token: UInt64) {
        guard buffer.isPending, buffer.token == token else { return }
        resolverBusy = true
        worker.async {
            let focused = self.resolver.isFocused(target)
            let stillAtPoint = self.resolver.stillUnderPointer(target)
            DispatchQueue.main.async {
                self.resolverBusy = false
                guard self.buffer.isPending, self.buffer.token == token else { return }
                if stillAtPoint == false {
                    self.onStatus?("La fenêtre visée a changé : clic annulé.")
                    self.discardClick(token: token)
                } else if focused {
                    // One run-loop interval lets the destination finish its activation handlers.
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(12)) {
                        guard self.buffer.isPending, self.buffer.token == token else { return }
                        self.onClick?()
                        self.flush(token: token)
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) {
                        self.checkFocus(target, token: token)
                    }
                }
            }
        }
    }

    private func flush(token: UInt64, trailing: CGEvent? = nil) {
        guard buffer.isPending, buffer.token == token else { return }
        cancellation?.cancel()
        cancellation = nil
        activationStarted = false
        watchdog?.cancel()
        watchdog = nil
        var events = buffer.drain(token: token)
        if let trailing { events.append(trailing) }
        bypassGesture = leftIsDown
        for event in events {
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.post(tap: .cgSessionEventTap)
        }
    }

    /// Do not deliver a held click to a window that replaced the intended target.
    /// Keep unrelated mouse events, and consume the physical release if still held.
    private func discardClick(token: UInt64) {
        guard buffer.isPending, buffer.token == token else { return }
        cancellation?.cancel()
        cancellation = nil
        activationStarted = false
        watchdog?.cancel()
        watchdog = nil
        let events = buffer.drain(token: token)
        discardLeftUntilUp = leftIsDown
        for event in events where ![CGEventType.leftMouseDown, .leftMouseUp, .leftMouseDragged].contains(event.type) {
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.post(tap: .cgSessionEventTap)
        }
    }
}
