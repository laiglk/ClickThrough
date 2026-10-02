import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var model: AppModel!
    private var statusItem: NSStatusItem!
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second launch should reveal the first instance, never install a second tap.
        if let id = Bundle.main.bundleIdentifier,
           let other = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }),
           let url = other.bundleURL {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        model = AppModel()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()
        if !model.trusted || !UserDefaults.standard.bool(forKey: "hasLaunched") {
            showSettings()
        }
        UserDefaults.standard.set(true, forKey: "hasLaunched")
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.updateIcon() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(); return true
    }

    private func updateIcon() {
        guard let model else { return }
        let image = NSImage(systemSymbolName: model.running ? "cursorarrow.click.2" : "cursorarrow.slash",
                            accessibilityDescription: "ClickThrough : \(model.status)")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = "ClickThrough : \(model.status)"
    }

    private func installMainMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "ClickThrough")
        add("Réglages…", #selector(showSettings), to: appMenu, key: ",")
        appMenu.addItem(.separator())
        add("Quitter ClickThrough", #selector(quit), to: appMenu, key: "q")
        appItem.submenu = appMenu
        bar.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Édition")
        for (title, action, key) in [("Couper", "cut:", "x"), ("Copier", "copy:", "c"),
                                     ("Coller", "paste:", "v"), ("Tout sélectionner", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        editItem.submenu = editMenu
        bar.addItem(editItem)
        NSApp.mainMenu = bar
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let state = NSMenuItem(title: "ClickThrough · \(model.status)", action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)
        menu.addItem(.separator())
        add(model.enabled ? "Mettre en pause" : "Activer ClickThrough", #selector(toggle), to: menu)
        if let app = NSWorkspace.shared.frontmostApplication,
           let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
           !model.exclusions.contains(where: { $0.id == id }) {
            let item = add("Exclure \(app.localizedName ?? id)", #selector(excludeFrontmost(_:)), to: menu)
            item.representedObject = [id, app.localizedName ?? id]
        }
        add("Réglages…", #selector(showSettings), to: menu, key: ",")
        menu.addItem(.separator())
        add("Quitter ClickThrough", #selector(quit), to: menu, key: "q")
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, to menu: NSMenu, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func toggle() { model.enabled.toggle(); updateIcon() }
    @objc private func excludeFrontmost(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? [String], value.count == 2 else { return }
        model.exclude(id: value[0], name: value[1])
    }
    @objc func showSettings() {
        guard model != nil else { return }
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(model: model))
            let panel = NSWindow(contentViewController: controller)
            panel.title = "ClickThrough"
            panel.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            panel.setContentSize(NSSize(width: 610, height: 680))
            panel.minSize = NSSize(width: 570, height: 580)
            panel.isReleasedWhenClosed = false
            panel.center()
            window = panel
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
