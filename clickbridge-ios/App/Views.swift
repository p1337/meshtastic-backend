import SwiftUI
import ClickBridgeCore
import ClickBridgeBLE

struct RootView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        TabView {
            NavigationStack { DashboardView(model: model, hub: model.hub) }
                .tabItem { Label("Fahrt", systemImage: "bicycle") }
            NavigationStack { DevicesView(hub: model.hub, model: model) }
                .tabItem { Label("Geräte", systemImage: "dot.radiowaves.left.and.right") }
            NavigationStack { SettingsView(model: model) }
                .tabItem { Label("Einstellungen", systemImage: "slider.horizontal.3") }
            NavigationStack { DiagnosticsView(model: model, log: model.hub.log) }
                .tabItem { Label("Diagnose", systemImage: "waveform.path.ecg") }
        }
        .alert("ClickBridge", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: { Text(model.message ?? "") }
    }
}

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var hub: ControllerHub
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Label("CLICKBRIDGE", systemImage: "arrow.triangle.swap")
                        .font(.caption.weight(.black)).tracking(2)
                    Spacer()
                    Text("BLE PROTOTYP").font(.caption2.bold()).foregroundStyle(.orange)
                }
                .padding(.top, 10)
                VStack(spacing: 12) {
                    Text("AKTUELLER GANG").font(.caption).tracking(2).foregroundStyle(.secondary)
                    Text("—").font(.system(size: 92, weight: .bold, design: .rounded))
                        .accessibilityLabel("Kein bestätigter Gang")
                    Text("Keine Incyclist-Verbindung").font(.headline).foregroundStyle(.orange)
                    Text("\(model.settings.gearing.count) Gänge konfiguriert · kein aktiver Schaltausgang")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    HStack(spacing: 16) {
                        Button { model.shift(.down) } label: {
                            Label("Runter", systemImage: "minus").frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                        Button { model.shift(.up) } label: {
                            Label("Hoch", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                    }.buttonStyle(.bordered).disabled(true)
                }.frame(maxWidth: .infinity).padding(22).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24))
                HStack(alignment: .top, spacing: 12) {
                    controllerCard(.left)
                    controllerCard(.right)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Label("Standalone · Diagnose", systemImage: "stethoscope").font(.headline)
                    Text("Incyclist verwaltet den Smarttrainer. ClickBridge fragt dessen Status nicht ab und sendet keine Trainerkommandos.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Divider()
                    Text(model.lastInput).font(.system(.subheadline, design: .monospaced))
                    Text("\(model.inputCount) Tastendrücke in dieser Sitzung").font(.caption).foregroundStyle(.secondary)
                }.padding(18).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
                Text("Die Schaltintegration benötigt eine geänderte Incyclist-App. Beide Controller und die Fahrwirkung sind noch auf dem iPhone zu prüfen.")
                    .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(20)
        }
        .background(Color(red: 0.045, green: 0.055, blue: 0.065))
        .navigationBarHidden(true)
    }
    private func controllerCard(_ side: ControllerSide) -> some View {
        let device = hub.devices.first { $0.assignedSide == side }
        return VStack(alignment: .leading, spacing: 8) {
            Label(side.label, systemImage: side == .left ? "minus.circle" : "plus.circle").font(.headline)
            Text(device?.phase.label ?? "Nicht zugeordnet").font(.caption).foregroundStyle(.secondary)
            Label(device?.battery.map { "\($0) %" } ?? "Batterie unbekannt", systemImage: "battery.75percent")
                .font(.caption)
            if let issue = device?.issue { Text(issue).font(.caption2).foregroundStyle(.orange) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct DevicesView: View {
    @ObservedObject var hub: ControllerHub
    @ObservedObject var model: AppModel
    var body: some View {
        List {
            Section {
                Label(hub.bluetoothStatus, systemImage: "antenna.radiowaves.left.and.right")
                Button(hub.scanning ? "Suche beenden" : "Controller suchen") {
                    if hub.scanning { hub.stopScan() } else { hub.scan() }
                }
                Text("Beide Clicks aufwecken. Gleichnamige Geräte werden über ihre lokale Kennung unterschieden.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(hub.devices) { device in
                Section(device.assignedSide?.label ?? "Nicht zugeordnet") {
                    LabeledContent(device.name, value: device.shortID)
                    LabeledContent("Status", value: device.phase.label)
                    if let hint = device.suggestedSide { LabeledContent("Herstellerdaten", value: hint.label) }
                    if let battery = device.battery { LabeledContent("Batterie", value: "\(battery) %") }
                    LabeledContent("Firmware", value: device.firmware ?? "Nicht gelesen")
                    LabeledContent("Hardware", value: device.hardware ?? "Nicht gelesen")
                    if let input = device.lastInput {
                        LabeledContent("Letzte Taste", value: device.lastButton ?? "—")
                        Text(input, style: .time).font(.caption).foregroundStyle(.secondary)
                    }
                    if let issue = device.issue { Text(issue).foregroundStyle(.orange) }
                    if let side = device.assignedSide {
                        HStack {
                            Button("Verbinden") { hub.connect(device.id) }
                            Spacer()
                            Button("Trennen") { hub.disconnect(device.id) }
                        }
                        Button("Zuordnung aufheben", role: .destructive) { hub.forget(side) }
                        Text("Verbindung testen: \(side == .left ? "Minus" : "Plus") am Controller drücken und den Eingang hier prüfen.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        HStack {
                            ForEach(ControllerSide.allCases, id: \.self) { side in
                                Button("Als \(side.label) zuweisen") {
                                    do { try hub.assign(device.id, to: side) }
                                    catch { model.message = "Seite bereits belegt. Vorher die vorhandene Zuordnung aufheben." }
                                }
                            }
                        }
                    }
                    DisclosureGroup("GATT-Details") {
                        ForEach(Array(device.gatt.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                }
            }
            if hub.devices.isEmpty {
                ContentUnavailableView("Noch keine Controller", systemImage: "dot.radiowaves.left.and.right",
                                       description: Text("Suche starten und Tasten an beiden Controllern drücken."))
            }
        }.navigationTitle("Geräte")
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var draft = GearConfiguration.standard
    @State private var ratioText = ""
    @State private var saved = false
    var body: some View {
        Form {
            Section("Virtuelle Gänge") {
                Stepper("\(draft.count) Gänge", value: Binding(get: { draft.count }, set: {
                    do { try draft.resize($0); updateRatioText() } catch { model.message = "Ganganzahl ungültig" }
                }), in: 2...64)
                Stepper("Startgang: \(draft.startGear)", value: $draft.startGear, in: 1...draft.count)
                DisclosureGroup("Übersetzungsverhältnisse") {
                    Text("Pro Gang ein positiver Wert, aufsteigend. Dezimalpunkt verwenden.").font(.caption)
                    TextEditor(text: $ratioText).frame(minHeight: 150).font(.system(.caption, design: .monospaced))
                }
                Text("Diese Einstellungen gelten für den Baustein. Die vorbereitete Incyclist-Integration verwendet zunächst Incyclists eigene Gangtabelle.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Schaltreaktion") {
                timing("Mindestabstand", value: $draft.shiftInterval, range: 0...1)
                timing("Entprellen", value: $draft.debounce, range: 0.01...0.5)
                timing("Langer Tastendruck", value: $draft.longPress, range: 0.3...3)
                Text("Lange Tastendrücke werden beim Loslassen gemeldet. Keine automatische Mehrfachschaltung.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Tastenbelegung") {
                ForEach(ClickButton.allCases, id: \.self) { button in
                    Picker("\(button.side.label) · \(button.label)", selection: Binding<ShiftDirection?>(
                        get: { draft.bindings.first { $0.button == button }?.direction },
                        set: { value in
                            draft.bindings.removeAll { $0.button == button }
                            if let value { draft.bindings.append(.init(button: button, direction: value)) }
                        })) {
                            Text("Keine Schaltung").tag(Optional<ShiftDirection>.none)
                            ForEach(ShiftDirection.allCases, id: \.self) { direction in
                                Text(direction.label).tag(Optional(direction))
                            }
                        }
                }
            }
            Section {
                Button(saved ? "Gespeichert" : "Einstellungen speichern") { save() }
                Button("Standard wiederherstellen") { draft = .standard; updateRatioText(); saved = false }
            }
            Section("Verbindung und Datenschutz") {
                LabeledContent("Modus", value: "Standalone-Diagnose")
                Text("Bluetooth-Hintergrundbetrieb und Wiederherstellung sind vorbereitet. iOS garantiert keine dauerhafte Ausführung. Nach erzwungenem Beenden die App manuell öffnen.")
                Text("Kein Konto, keine Werbung und keine automatische Datenübertragung. Diagnose bleibt auf dem Gerät; ein Export erfolgt nur auf Wunsch.")
                Text("Unabhängiges Projekt. Zwift und Incyclist sind Marken ihrer jeweiligen Inhaber.")
                NavigationLink("Lizenzen und Hinweise") { LicenseView() }
            }.font(.footnote)
        }
        .navigationTitle("Einstellungen")
        .onAppear { draft = model.settings.gearing; updateRatioText() }
    }
    private func timing(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(label); Spacer(); Text("\(Int(value.wrappedValue * 1000)) ms").foregroundStyle(.secondary) }
            Slider(value: value, in: range, step: 0.01)
        }
    }
    private func updateRatioText() { ratioText = draft.ratios.map { String(format: "%.5f", $0) }.joined(separator: "\n") }
    private func save() {
        let tokens = ratioText.split { $0.isWhitespace || $0 == ";" }
        let values = tokens.compactMap { Double($0) }
        guard values.count == tokens.count, values.count == draft.count else {
            model.message = "Genau \(draft.count) gültige Übersetzungen eingeben."; return
        }
        do { draft.ratios = values; try model.save(draft); saved = true }
        catch { model.message = "Ungültige Einstellungen: Übersetzungen müssen positiv und aufsteigend sein." }
    }
}

private struct LicenseView: View {
    private var notices: String {
        guard let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "Lizenzdatei nicht gefunden." }
        return text
    }
    var body: some View {
        ScrollView { Text(notices).font(.footnote).textSelection(.enabled).padding() }
            .navigationTitle("Lizenzen")
    }
}

struct DiagnosticsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var log: DiagnosticLog
    var body: some View {
        List {
            Section {
                Text("Tatsächliche BLE-Ereignisse. Ein Handshake oder eine sichtbare Taste bestätigt keine Incyclist-Schaltung.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Diagnoseexport vorbereiten") { model.exportLog() }
                if let url = model.exportURL { ShareLink("Diagnose teilen", item: url) }
                if let error = log.storageError { Text("Protokolldatei: \(error)").foregroundStyle(.orange) }
            }
            ForEach(log.entries.reversed()) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.category).foregroundStyle(.orange)
                        Spacer()
                        Text(entry.time, style: .time).foregroundStyle(.secondary)
                    }.font(.caption.bold())
                    Text(entry.message).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
        }.navigationTitle("Diagnose")
    }
}
