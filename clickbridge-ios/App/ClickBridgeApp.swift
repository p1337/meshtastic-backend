import SwiftUI
import ClickBridgeCore
import ClickBridgeBLE

@main struct ClickBridgeApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.dark)
                .tint(.orange)
                .onChange(of: scenePhase) { _, phase in
                    model.hub.log.record("App", "Lebenszyklus: \(String(describing: phase))")
                    if phase == .active { model.hub.checkHealth() }
                }
        }
    }
}

@MainActor final class AppModel: ObservableObject {
    let hub = ControllerHub()
    @Published var settings: SavedSettings
    @Published var message: String?
    @Published var lastInput = "Noch kein Tastendruck"
    @Published var inputCount = 0
    @Published var exportURL: URL?
    private var engine: GearEngine
    private let key = "ClickBridge.settings.v1"

    init() {
        let restored = SavedSettings.restore(from: UserDefaults.standard.data(forKey: key))
        settings = restored
        // A persisted value is history, never a live connection or gear confirmation.
        engine = try! GearEngine(configuration: restored.gearing)
        hub.debounce = restored.gearing.debounce; hub.longPress = restored.gearing.longPress
        hub.onButton = { [weak self] _, side, event in
            guard let self else { return }
            self.lastInput = "\(side.label) · \(event.button.label) · \(event.phase.rawValue)"
            if event.phase == .down { self.inputCount += 1 }
            if let direction = self.settings.gearing.direction(for: event) { self.shift(direction) }
        }
        hub.log.record("Integration", "Standalone-Diagnose; kein Ausgang zu Incyclist und keine Trainerverbindung")
        if ProcessInfo.processInfo.arguments.contains("--clickbridge-smoke") { writeSmokeEvidence() }
    }

    func shift(_ direction: ShiftDirection) {
        do {
            _ = try engine.request(direction, at: ProcessInfo.processInfo.systemUptime, integrationAvailable: false)
        } catch {
            hub.log.record("Schaltung blockiert", "\(direction.label): keine Incyclist-Eingabeschnittstelle aktiv")
            message = "Keine Incyclist-Verbindung. Die eigenständige App kann die unveränderte Incyclist-App auf diesem iPhone derzeit nicht schalten."
        }
    }

    func save(_ configuration: GearConfiguration) throws {
        try configuration.validate()
        var updated = settings; updated.gearing = configuration
        if let gear = updated.lastAcceptedGear, gear > configuration.count { updated.lastAcceptedGear = nil }
        let data = try JSONEncoder().encode(updated)
        UserDefaults.standard.set(data, forKey: key)
        settings = updated
        engine = try GearEngine(configuration: configuration)
        hub.debounce = configuration.debounce; hub.longPress = configuration.longPress
        hub.log.record("Einstellungen", "\(configuration.count) Gänge; Standalone ohne aktiven Schaltausgang")
    }
    func exportLog() {
        do { exportURL = try hub.log.export() }
        catch { message = "Export fehlgeschlagen: \(error.localizedDescription)" }
    }
    private func writeSmokeEvidence() {
        // A real app launch observation with honest, explicitly negative hardware fields.
        let report: [String: Any] = [
            "app": "ClickBridge", "mode": "standalone-diagnostics", "source": "app-launch-smoke",
            "integrationAvailable": false, "trainerCommandsSent": 0,
            "hardwareTested": false, "gearCount": settings.gearing.count,
            "liveGear": NSNull(), "system": ProcessInfo.processInfo.operatingSystemVersionString
        ]
        do {
            let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: base.appendingPathComponent("ClickBridge-Smoke.json"), options: .atomic)
        } catch { hub.log.record("Smoke-Fehler", error.localizedDescription) }
    }
}
