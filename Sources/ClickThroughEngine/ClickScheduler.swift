import Foundation

/// Keep AX work off the tap run loop, and return all transaction updates to it.
protocol ClickScheduling {
    func resolve(_ operation: @escaping () -> Void)
    func complete(_ operation: @escaping () -> Void)
    @discardableResult
    func after(milliseconds: Int, _ operation: @escaping () -> Void) -> DispatchWorkItem
}

final class ClickScheduler: ClickScheduling {
    private let worker = DispatchQueue(label: "fr.clickthrough.accessibility", qos: .userInteractive)

    func resolve(_ operation: @escaping () -> Void) { worker.async(execute: operation) }
    func complete(_ operation: @escaping () -> Void) { DispatchQueue.main.async(execute: operation) }

    @discardableResult
    func after(milliseconds: Int, _ operation: @escaping () -> Void) -> DispatchWorkItem {
        let item = DispatchWorkItem(block: operation)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds), execute: item)
        return item
    }
}
