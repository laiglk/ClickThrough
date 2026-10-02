import AppKit
import ApplicationServices
import ClickThroughEngine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct ExcludedApplication: Codable, Identifiable, Equatable {
    var id: String
    var name: String
}

final class AppModel: ObservableObject {
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "enabled"); reconcile() }
    }
    @Published private(set) var trusted = false
    @Published private(set) var running = false
    @Published private(set) var exclusions: [ExcludedApplication] = []
    @Published private(set) var loginEnabled = false
    @Published private(set) var loginNeedsApproval = false
    @Published private(set) var processedClicks = 0
    @Published var notice: String?
    private let engine = ClickEngine()
    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var asleep = false

    var status: String {
        if !trusted { return "Autorisation nécessaire" }
        if !enabled { return "En pause" }
        return running ? "Actif" : "Suivi des clics indisponible"
    }

    var applicationPath: String { Bundle.main.bundlePath }

    init() {
        enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
        if let data = UserDefaults.standard.data(forKey: "exclusions"),
           let saved = try? JSONDecoder().decode([ExcludedApplication].self, from: data) { exclusions = saved }
        engine.exclusions = Set(exclusions.map(\.id))
        engine.onStatus = { [weak self] in self?.notice = $0 }
        engine.onClick = { [weak self] in self?.processedClicks += 1 }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.asleep = true; self?.reconcile()
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.asleep = false; self?.refresh()
            })
        }
    }

    func refresh() {
        trusted = AXIsProcessTrusted()
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
        reconcile()
    }

    private func reconcile() {
        if enabled && trusted && !asleep {
            running = engine.start()
        } else {
            engine.stop(); running = false
        }
    }

    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openAccessibility()
    }

    func verifyAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
        reconcile()
        if trusted { notice = "Autorisation détectée pour cette copie de ClickThrough." }
        else { notice = "macOS ne reconnaît pas encore cette copie. Retirez l’ancienne entrée ClickThrough, ajoutez le fichier indiqué ci-dessous, activez-le, puis relancez l’application." }
    }

    func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            notice = nil
        } catch { notice = "Le démarrage automatique n’a pas pu être modifié : \(error.localizedDescription)" }
        refresh()
    }

    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }

    func addExclusion() {
        let panel = NSOpenPanel()
        panel.title = "Exclure une application"
        panel.prompt = "Exclure"
        panel.allowedContentTypes = [.application, .applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            for url in panel.urls {
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                self?.exclude(id: id, name: name)
            }
        }
    }

    func exclude(id: String, name: String) {
        guard id != Bundle.main.bundleIdentifier, !exclusions.contains(where: { $0.id == id }) else { return }
        exclusions.append(.init(id: id, name: name))
        exclusions.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        saveExclusions()
    }

    func removeExclusion(_ app: ExcludedApplication) {
        exclusions.removeAll { $0.id == app.id }
        saveExclusions()
    }

    private func saveExclusions() {
        if let data = try? JSONEncoder().encode(exclusions) { UserDefaults.standard.set(data, forKey: "exclusions") }
        engine.exclusions = Set(exclusions.map(\.id))
    }

    func shutdown() { timer?.invalidate(); engine.stop() }
}
