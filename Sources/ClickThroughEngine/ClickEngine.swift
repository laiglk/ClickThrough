import AppKit
import ApplicationServices
import ClickThroughCore

public final class ClickEngine {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var buffer = EventBuffer<CGEvent>()
    private let scheduler: ClickScheduling
    private let resolver: WindowResolving
    private let activateApplication: (pid_t) -> Bool
    private let postEvent: (CGEvent) -> Void
    private let copyEvent: (CGEvent) -> CGEvent?
    private let marker: Int64 = 0x43544852554748
    private var resolverBusy = false
    private var watchdog: DispatchWorkItem?
    private var leftIsDown = false
    private var bypassGesture = false
    private var discardLeftUntilUp = false
    private var activationStarted = false
    private var cancellation: CancellationToken?
    public var exclusions: Set<String> = []
    public var onStatus: ((String) -> Void)?
    public var onClick: (() -> Void)?
    public var isRunning: Bool { tap != nil }

    public convenience init() {
        self.init(resolver: WindowResolver(), scheduler: ClickScheduler(), activateApplication: { pid in
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return false }
            if !app.isActive { app.activate(options: [.activateIgnoringOtherApps]) }
            return true
        }, postEvent: { $0.post(tap: .cgSessionEventTap) })
    }

    /// Tests exercise the production transaction without installing a tap or posting events.
    init(resolver: WindowResolving, scheduler: ClickScheduling,
         activateApplication: @escaping (pid_t) -> Bool, postEvent: @escaping (CGEvent) -> Void,
         copyEvent: @escaping (CGEvent) -> CGEvent? = { $0.copy() }) {
        self.resolver = resolver
        self.scheduler = scheduler
        self.activateApplication = activateApplication
        self.postEvent = postEvent
        self.copyEvent = copyEvent
    }

    public func start() -> Bool {
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

    public func stop() {
        finishUnconfirmed(token: buffer.token)
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        tap = nil
    }

    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            finishUnconfirmed(token: buffer.token)
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
            guard let copy = copyEvent(event) else {
                let discardCurrent = activationStarted && isLeftGesture(type)
                finishUnconfirmed(token: buffer.token)
                return discardCurrent ? nil : Unmanaged.passUnretained(event)
            }
            if buffer.append(copy) { return nil }
            // Overflow is an interruption, not confirmation that activation succeeded.
            // Include unrelated trailing events so they cannot overtake the queue.
            finishUnconfirmed(token: buffer.token, trailing: copy)
            return nil
        }
        if bypassGesture {
            if type == .leftMouseUp { bypassGesture = false }
            return Unmanaged.passUnretained(event)
        }
        guard type == .leftMouseDown, !resolverBusy,
              event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty,
              event.getIntegerValueField(.mouseEventClickState) == 1,
              let copy = copyEvent(event) else { return Unmanaged.passUnretained(event) }

        let token = buffer.begin(copy)
        cancellation = CancellationToken()
        activationStarted = false
        // CGEvent.location is already in the global, top-left display space
        // used by AXUIElementCopyElementAtPosition. Do not mirror it again.
        let point = event.location
        let excluded = exclusions
        resolverBusy = true
        watchdog = scheduler.after(milliseconds: 250) { [weak self] in
            guard let self, self.buffer.isPending, self.buffer.token == token else { return }
            if self.activationStarted {
                self.onStatus?("Activation non confirmée : cliquez à nouveau dans la fenêtre.")
                self.discardClick(token: token)
            } else {
                self.onStatus?("Fenêtre lente : clic transmis normalement.")
                self.flush(token: token)
            }
        }
        scheduler.resolve { [weak self] in
            guard let self else { return }
            let target = self.resolver.target(at: point, excluded: excluded)
            self.scheduler.complete {
                self.resolverBusy = false
                guard self.buffer.isPending, self.buffer.token == token else { return }
                guard let target else { self.flush(token: token); return }
                self.activate(target, token: token)
            }
        }
        return nil
    }

    private func activate(_ target: WindowTarget, token: UInt64) {
        guard let cancellation, !cancellation.isCancelled else {
            flush(token: token); return
        }
        activationStarted = true
        guard activateApplication(target.pid) else {
            activationStarted = false
            flush(token: token); return
        }
        resolverBusy = true
        scheduler.resolve {
            self.resolver.raise(target, cancellation: cancellation)
            self.scheduler.complete {
                self.resolverBusy = false
                self.checkFocus(target, token: token)
            }
        }
    }

    private func checkFocus(_ target: WindowTarget, token: UInt64, afterSettling: Bool = false) {
        guard buffer.isPending, buffer.token == token else { return }
        resolverBusy = true
        scheduler.resolve {
            let focused = self.resolver.isFocused(target)
            let stillAtPoint = self.resolver.stillUnderPointer(target)
            self.scheduler.complete {
                self.resolverBusy = false
                guard self.buffer.isPending, self.buffer.token == token else { return }
                if stillAtPoint == false {
                    self.onStatus?("La fenêtre visée a changé : clic annulé.")
                    self.discardClick(token: token)
                } else if focused && afterSettling {
                    self.onClick?()
                    self.flush(token: token)
                } else if focused {
                    // One run-loop interval lets the destination finish its activation handlers.
                    self.scheduler.after(milliseconds: 12) {
                        // The earlier focus/target result is stale after this delay.
                        self.checkFocus(target, token: token, afterSettling: true)
                    }
                } else if afterSettling {
                    self.onStatus?("Le focus a changé : clic annulé.")
                    self.discardClick(token: token)
                } else {
                    self.scheduler.after(milliseconds: 10) {
                        self.checkFocus(target, token: token)
                    }
                }
            }
        }
    }

    /// Until focus is confirmed, all interruption paths must use the same policy.
    private func finishUnconfirmed(token: UInt64, trailing: CGEvent? = nil) {
        if activationStarted { discardClick(token: token, trailing: trailing) }
        else { flush(token: token, trailing: trailing) }
    }

    private func isLeftGesture(_ type: CGEventType) -> Bool {
        [.leftMouseDown, .leftMouseUp, .leftMouseDragged].contains(type)
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
            postEvent(event)
        }
    }

    /// Do not deliver a held click to a window that replaced the intended target.
    /// Keep unrelated mouse events, and consume the physical release if still held.
    private func discardClick(token: UInt64, trailing: CGEvent? = nil) {
        guard buffer.isPending, buffer.token == token else { return }
        cancellation?.cancel()
        cancellation = nil
        activationStarted = false
        watchdog?.cancel()
        watchdog = nil
        var events = buffer.drain(token: token)
        if let trailing { events.append(trailing) }
        discardLeftUntilUp = leftIsDown
        for event in events where !isLeftGesture(event.type) {
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            postEvent(event)
        }
    }
}
