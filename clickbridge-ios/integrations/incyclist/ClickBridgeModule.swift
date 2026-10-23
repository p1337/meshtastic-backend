import Foundation
import UIKit
import SwiftUI
import Combine
import React
import ClickBridgeCore
import ClickBridgeBLE

/// Instantiated by AppDelegate before React Native so BLE restoration can attach early.
@MainActor final class ClickBridgeHost {
    static let shared = ClickBridgeHost()
    let hub = ControllerHub(namespace: "Incyclist.ClickBridge")
    var emit: ((String, [String: Any]) -> Void)?
    private var session: String?

    private init() {
        hub.onButton = { [weak self] _, side, event in
            guard let self, let session = self.session,
                  let direction = GearConfiguration.standard.direction(for: event) else { return }
            self.emit?("ClickBridgeShift", [
                "id": UUID().uuidString, "session": session, "direction": direction.rawValue,
                "emittedAtMs": Date().timeIntervalSince1970 * 1000,
                "side": side.rawValue
            ])
        }
    }
    func arm(_ enabled: Bool) -> String {
        let token = UUID().uuidString
        session = enabled ? token : nil
        hub.log.record("Incyclist", enabled ? "Schaltereignisse für neue Fahrsitzung freigegeben" : "Schaltereignisse gesperrt")
        return token
    }
}

@objc(ClickBridgeModule)
final class ClickBridgeModule: RCTEventEmitter {
    override static func requiresMainQueueSetup() -> Bool { true }
    override var methodQueue: DispatchQueue! { DispatchQueue.main }
    override func supportedEvents() -> [String]! { ["ClickBridgeShift"] }

    override func startObserving() {
        Task { @MainActor [weak self] in
            ClickBridgeHost.shared.emit = { [weak self] name, body in
                self?.sendEvent(withName: name, body: body)
            }
        }
    }
    override func stopObserving() {
        Task { @MainActor in
            _ = ClickBridgeHost.shared.arm(false)
            ClickBridgeHost.shared.emit = nil
        }
    }
    @objc(arm:resolver:rejecter:)
    func arm(_ enabled: Bool, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        Task { @MainActor in resolve(ClickBridgeHost.shared.arm(enabled)) }
    }
    @objc(report:result:)
    func report(_ id: String, result: String) {
        Task { @MainActor in
            ClickBridgeHost.shared.hub.log.record("Incyclist-Weiterleitung", "\(id.prefix(8)) \(result.prefix(1500))")
        }
    }
    @objc(presentSetup)
    func presentSetup() {
        Task { @MainActor in
            guard let presenter = RCTPresentedViewController() else { return }
            let screen = UIHostingController(rootView: ClickBridgeSetup(hub: ClickBridgeHost.shared.hub))
            screen.modalPresentationStyle = .formSheet
            presenter.present(screen, animated: true)
        }
    }
}

private struct ClickBridgeSetup: View {
    @ObservedObject var hub: ControllerHub
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var export: URL?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(hub.bluetoothStatus)
                    Button(hub.scanning ? "Suche beenden" : "Click V2 suchen") {
                        if hub.scanning { hub.stopScan() } else { hub.scan() }
                    }
                    Text("Incyclist bleibt alleiniger Trainercontroller. Virtuelle Schaltung in den Incyclist-Geräteeinstellungen aktivieren. Dieser Adapter nutzt dessen Gangtabelle.")
                        .font(.footnote)
                }
                ForEach(hub.devices) { device in
                    Section(device.assignedSide?.label ?? "Nicht zugeordnet") {
                        Text("\(device.name) · \(device.shortID)")
                        Text(device.phase.label)
                        Text("Batterie \(device.battery.map { "\($0) %" } ?? "unbekannt") · Firmware \(device.firmware ?? "unbekannt")")
                            .font(.caption)
                        if let issue = device.issue { Text(issue).foregroundStyle(.orange) }
                        if let side = device.assignedSide {
                            Button("Verbinden / erneut versuchen") { hub.connect(device.id) }
                            Button("Trennen") { hub.disconnect(device.id) }
                            Button("Zuordnung aufheben", role: .destructive) { hub.forget(side) }
                        } else {
                            ForEach(ControllerSide.allCases, id: \.self) { side in
                                Button("Als \(side.label) zuweisen") {
                                    do { try hub.assign(device.id, to: side) }
                                    catch { self.error = "Zuordnung belegt. Vorher bestehende Zuordnung aufheben." }
                                }
                            }
                        }
                        if let last = device.lastButton { Text("Letzte Taste: \(last)") }
                    }
                }
                Section {
                    Text("Zwei Controller, D100-Fahrwirkung und 60-Minuten-Stabilität sind noch nicht auf Hardware bestätigt. Beim linken Click V2 ist eine zeitabhängige Sperre möglich.")
                        .font(.footnote)
                    Button("Diagnoseexport vorbereiten") {
                        do { export = try hub.log.export() } catch { self.error = error.localizedDescription }
                    }
                    if let export { ShareLink("Diagnose teilen", item: export) }
                    if let error { Text(error).foregroundStyle(.orange) }
                }
            }
            .navigationTitle("ClickBridge")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .onAppear { hub.checkHealth() }
        }
    }
}
