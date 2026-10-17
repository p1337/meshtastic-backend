import SwiftUI
import UniformTypeIdentifiers
import Darwin

@main
struct LoRaLabApp: App {
    var body: some Scene { WindowGroup { LabView() } }
}

struct LabView: View {
    @State private var result = "Noch nicht ausgeführt."
    @State private var busy = false
    @State private var importing = false
    @State private var fileResult = "Keine Datei importiert."
    @State private var rate = "500000"
    @State private var importedCount: Int?
    @State private var exported: URL?
    @State private var exportError: String?

    private var deviceModel: String {
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else { return "Unbekannt" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &bytes, &size, nil, 0) == 0 else { return "Unbekannt" }
        return String(cString: bytes)
    }
    private var duration: String? {
        guard let count = importedCount, let value = Double(rate), value.isFinite, value > 0 else { return nil }
        return String(format: "Aufnahmedauer: %.6f s bei angegebener Samplerate.", Double(count) / value)
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Live-Empfang nicht verfügbar", systemImage: "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(.orange).font(.headline)
                    Text("Für die interne Funkhardware ist noch kein nutzbarer I/Q-Zugang nachgewiesen. Diese Test-App empfängt keine LoRa-Pakete.")
                        .font(.subheadline)
                } header: { Text("Forschungsstand") }
                Section("Zielkonfiguration") {
                    LabeledContent("Meshtastic", value: "EU_868 · LongFast")
                    LabeledContent("Träger", value: "869,525 MHz")
                    LabeledContent("PHY", value: "SF11 · BW250 · CR4/5")
                    LabeledContent("Gerät", value: deviceModel)
                    LabeledContent("iOS", value: UIDevice.current.systemVersion)
                }
                Section("CSS-Selbsttest · offline") {
                    Text(result).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                    Button(busy ? "Berechnung läuft …" : "CSS-Selbsttest ausführen") {
                        busy = true
                        Task {
                            let text = await Task.detached(priority: .userInitiated) { CSS.selfTest() }.value
                            result = text; busy = false
                        }
                    }.disabled(busy)
                    Text("Prüft den eingebauten Chirp-/Dechirp-Algorithmus mit synthetischen Symbolen. Kein LoRa-Header, keine FEC, keine CRC und kein Meshtastic-Paketdecoder.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("I/Q-Datei untersuchen · CF32LE") {
                    Text("Dateiformat: Float32 little-endian, abwechselnd I und Q. Maximal 8 MiB. Die Datei bleibt lokal.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Samplerate in komplexen Samples/s", text: $rate).keyboardType(.decimalPad)
                    Button("I/Q-Datei auswählen") { importing = true }
                    Text(fileResult).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                    if let duration { Text(duration).font(.caption) }
                    Text("Der angezeigte SF11-Bin ist nur eine Dechirp-Auswertung der ersten 2048 Samples bei Fs=BW=250 kHz und angenommener Symbolgrenze. Er erkennt kein Paket und kann bei beliebigen Daten einen beliebigen Wert liefern. Die eingetragene Samplerate dient nur der Dauerberechnung.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Diagnose") {
                    Button("Lokalen Bericht erzeugen") { exportReport() }
                    if let exported { ShareLink("Bericht teilen", item: exported) }
                    if let exportError { Text(exportError).foregroundStyle(.red) }
                    Text("Enthält Gerätemodell, iOS-Version und Testergebnisse. Keine Gerätekennung, Konten oder Standortdaten.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("LoRa Lab")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { response in
                do {
                    guard let url = try response.get().first else { return }
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 8 * 1024 * 1024 else { throw IQSummary.IQError.tooLarge }
                    let summary = try IQSummary.readCF32LE(Data(contentsOf: url, options: .mappedIfSafe))
                    importedCount = summary.sampleCount
                    fileResult = "Samples: \(summary.sampleCount)\nMittlere normierte Leistung: \(summary.meanPower)\nSpitzenleistung: \(summary.peakPower)\nSF11-Bin (keine Paketerkennung): \(summary.firstSF11Symbol.map(String.init) ?? "nicht ausgewertet")"
                } catch {
                    importedCount = nil
                    fileResult = "Import: \(error.localizedDescription)"
                }
            }
        }.preferredColorScheme(.dark)
    }
    private func exportReport() {
        let report = """
        LoRa Lab – Testbericht
        Datum: \(Date().ISO8601Format())
        Modell: \(deviceModel)
        iOS: \(UIDevice.current.systemVersion)
        App: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
        Live-RF: NICHT IMPLEMENTIERT / KEIN NACHGEWIESENER ZUGANG
        Ziel: 869.525 MHz, SF11, BW250, CR4/5

        CSS-Selbsttest:
        \(result)

        Importierte Datei:
        \(fileResult)
        \(duration ?? "")

        Keine Funkaufnahme und kein Hardware-PoC.
        """
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("LoRaLab-Diagnose.txt")
            try report.write(to: url, atomically: true, encoding: .utf8)
            exported = url; exportError = nil
        } catch { exportError = error.localizedDescription }
    }
}
