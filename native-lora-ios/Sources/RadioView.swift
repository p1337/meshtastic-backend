import SwiftUI

struct RadioView: View {
    @ObservedObject var model: LabModel

    private func label(_ status: String) -> String {
        switch status {
        case "observed": return "Beobachtet"
        case "absent": return "Nicht gesetzt"
        case "restricted": return "Abgewiesen"
        case "error": return "Abfragefehler"
        case "not_observed": return "Nicht beobachtet"
        case "unverified": return "Nicht nachgewiesen"
        default: return "Nicht verfügbar"
        }
    }
    private func sessionLabel(_ state: String) -> String {
        switch state {
        case "running": return "Diagnose läuft"
        case "completed": return "Diagnose abgeschlossen"
        case "interrupted": return "Durch Hintergrundwechsel beendet"
        default: return "Diagnose beendet"
        }
    }
    var body: some View {
        List {
            Section {
                Label("I/Q-Aufnahme noch nicht zugänglich", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.headline).foregroundStyle(.orange)
                LabeledContent("Echte Funk-Samples", value: "0")
                Text("Diese Version untersucht echte Zugriffsmerkmale deines Geräts. Der Zeitlauf protokolliert Mobilfunkstatus, keine HF-Wellenform und keine LoRa-Pakete.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Zeitdiagnose auf diesem Gerät") {
                if let s = model.session {
                    Label(sessionLabel(s.state), systemImage: s.state == "running" ? "timer" : s.state == "completed" ? "checkmark.circle" : "pause.circle")
                        .accessibilityIdentifier(s.state == "completed" ? "radio-session-complete" : "radio-session-running")
                    ProgressView(value: min(s.elapsed, s.requestedSeconds), total: s.requestedSeconds)
                    LabeledContent("Beobachtungsdauer", value: String(format: "%.1f / %.0f s", s.elapsed, s.requestedSeconds))
                    LabeledContent("Statusabfragen", value: "\(s.observations.count)")
                    LabeledContent("Größte Statuslücke", value: String(format: "%.2f s", s.maximumMetadataGap))
                    if let last = s.observations.last {
                        LabeledContent("Mobilfunktechnik", value: last.radioTechnologies.isEmpty ? "nicht geliefert" : last.radioTechnologies.map { $0.replacingOccurrences(of: "CTRadioAccessTechnology", with: "") }.joined(separator: ", "))
                    }
                    if let reason = s.reason { Text(reason).font(.caption).foregroundStyle(.orange) }
                } else { Text("Wird nach der Geräteprüfung automatisch gestartet.").foregroundStyle(.secondary) }
                if model.session?.state == "running" {
                    Button("Diagnose beenden", role: .destructive) { model.stopSession() }
                } else {
                    Picker("Dauer", selection: $model.sessionSeconds) {
                        Text("60 Sekunden").tag(60); Text("120 Sekunden").tag(120)
                    }
                    Button("Neue Zeitdiagnose starten") { model.startSession() }.disabled(model.auditBusy)
                }
                Text("Beim ersten Öffnen automatisch 60 Sekunden. Lass die App dafür im Vordergrund. Ein Wechsel in den Hintergrund wird als Unterbrechung protokolliert. Die Dauer ist keine Funk-Aufnahmedauer.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Tatsächliche Laufzeitprüfung") {
                if model.auditBusy { ProgressView("Schnittstellen werden untersucht …") }
                if let audit = model.audit {
                    LabeledContent("iOS-Build", value: audit.osBuild)
                    LabeledContent("Version", value: "\(audit.environment.appVersion) (\(audit.environment.build))")
                    LabeledContent("Gerät", value: audit.environment.model)
                    LabeledContent("Simulator", value: audit.environment.simulator ? "ja" : "nein")
                    ForEach(audit.probes) { probe in
                        DisclosureGroup {
                            Text(probe.detail).font(.caption).textSelection(.enabled)
                            if let code = probe.code { Text(code).font(.caption.monospaced()).textSelection(.enabled) }
                            ForEach(probe.observations, id: \.self) { Text($0).font(.caption.monospaced()).textSelection(.enabled) }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(probe.name).font(.subheadline).lineLimit(3)
                                Text(label(probe.status)).font(.caption)
                                    .foregroundStyle(probe.status == "observed" ? .mint : .secondary)
                            }
                        }
                    }
                }
                Button("Geräteprüfung wiederholen") { model.runAudit() }.disabled(model.auditBusy)
                Text("Eine sichtbare Bibliothek oder ein sichtbarer Treiber beweist weder die Berechtigung zum Öffnen noch einen Antennen-Samplepfad.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Bericht für die nächste Untersuchung") {
                if let url = model.jsonURL { ShareLink("Gesamten JSON-Bericht teilen", item: url) }
                if let url = model.textURL { ShareLink("Gesamten Textbericht teilen", item: url) }
                Text("Enthält die konkreten Rückgabecodes und Ergebnisse dieses Geräts. Teilen startet keinen automatischen Upload.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
