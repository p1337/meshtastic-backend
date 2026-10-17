import SwiftUI
import UniformTypeIdentifiers
import Darwin
import CoreTelephony

@main
struct LoRaLabApp: App {
    var body: some Scene { WindowGroup { LabView() } }
}

struct LabSnapshot: Codable {
    var schemaVersion = 3
    var state = "completed"
    var suite: LabReport
    var importedFile: IQAnalysis?
    var runtimeAudit: RuntimeAuditReport?
    var accessSession: AccessSession?
}

@MainActor
final class LabModel: ObservableObject {
    @Published var report: LabReport?
    @Published var busy = false
    @Published var fileBusy = false
    @Published var error: String?
    @Published var fileMessage = "Noch keine Datei untersucht."
    @Published var analysis: IQAnalysis?
    @Published var jsonURL: URL?
    @Published var textURL: URL?
    @Published var demoURL: URL?
    @Published var rate = "250000"
    @Published var bandwidth = 250000
    @Published var sf = 11
    @Published var audit: RuntimeAuditReport?
    @Published var auditBusy = false
    @Published var session: AccessSession?
    @Published var sessionSeconds = 60
    private var sessionTask: Task<Void, Never>?
    private var automaticStarted = false
    private var isForeground = true
    private let telephony = CTTelephonyNetworkInfo()

    var environment: LabEnvironment {
        var size = 0
        var model = "unbekannt"
        if sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 {
            var bytes = [CChar](repeating: 0, count: size)
            if sysctlbyname("hw.machine", &bytes, &size, nil, 0) == 0 { model = String(cString: bytes) }
        }
        #if targetEnvironment(simulator)
        let simulated = true
        #else
        let simulated = false
        #endif
        return LabEnvironment(model: model, os: UIDevice.current.systemVersion,
                              appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
                              build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
                              simulator: simulated, processorCount: ProcessInfo.processInfo.processorCount,
                              memoryMiB: ProcessInfo.processInfo.physicalMemory / 1048576)
    }
    var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    func startAutomatically() {
        guard !automaticStarted else { return }
        automaticStarted = true
        run()
        runAudit(startSessionAfterwards: true)
    }

    func runAudit(startSessionAfterwards: Bool = false) {
        guard !auditBusy else { return }
        auditBusy = true
        let env = environment
        Task {
            let result = await Task.detached(priority: .userInitiated) { RuntimeAudit.run(environment: env) }.value
            audit = result; auditBusy = false; saveReports()
            if startSessionAfterwards && isForeground { startSession() }
        }
    }

    func startSession() {
        guard isForeground, session?.state != "running" else { return }
        do {
            session = try AccessSession(seconds: Double(sessionSeconds), startedUTC: ISO8601DateFormatter().string(from: Date()))
        } catch { self.error = "Ungültige Diagnosedauer."; return }
        let id = session!.runID
        let start = ProcessInfo.processInfo.systemUptime
        UIApplication.shared.isIdleTimerDisabled = true
        sessionTask = Task {
            while !Task.isCancelled && session?.runID == id && session?.state == "running" {
                let elapsed = ProcessInfo.processInfo.systemUptime - start
                let technologies = telephony.serviceCurrentRadioAccessTechnology?.values.map { String($0.prefix(80)) } ?? []
                do {
                    try session?.record(elapsed: elapsed, utc: ISO8601DateFormatter().string(from: Date()), technologies: technologies)
                } catch {
                    session?.stop(interrupted: true)
                    self.error = "Zeitdiagnose: ungültiger Zeitwert."
                }
                saveReports()
                if session?.state != "running" { break }
                let remaining = (session?.requestedSeconds ?? 60) - elapsed
                do { try await Task.sleep(nanoseconds: UInt64(max(0.005, min(1, remaining)) * 1_000_000_000)) }
                catch { break }
            }
            if session?.runID == id {
                UIApplication.shared.isIdleTimerDisabled = false
                saveReports()
            }
        }
    }

    func stopSession(interrupted: Bool = false) {
        session?.stop(interrupted: interrupted)
        sessionTask?.cancel(); sessionTask = nil
        UIApplication.shared.isIdleTimerDisabled = false
        saveReports()
    }

    func background() {
        isForeground = false
        if session?.state == "running" { stopSession(interrupted: true) }
    }

    func foreground() {
        isForeground = true
        if automaticStarted && audit != nil && session == nil { startSession() }
    }

    func run(extended: Bool = false) {
        guard !busy else { return }
        busy = true; error = nil
        let env = environment
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                LabDiagnostics.run(environment: env, extended: extended)
            }.value
            report = result; busy = false
            saveReports()
        }
    }

    func saveReports() {
        guard let report else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let json = documents.appendingPathComponent("LoRaLab-Latest.json")
            try encoder.encode(LabSnapshot(suite: report, importedFile: analysis, runtimeAudit: audit, accessSession: session)).write(to: json, options: .atomic)
            let text = documents.appendingPathComponent("LoRaLab-Latest.txt")
            var description = report.text
            if let audit { description += "\n\n" + audit.text }
            if let session { description += "\n\n" + session.text }
            if let analysis { description += "\n\nDateianalyse:\n\(analysis.note)\nSamples: \(analysis.sampleCount)\nFs: \(analysis.sampleRate)\nBin: \(analysis.symbolBin.map(String.init) ?? "nicht ausgewertet")" }
            try description.write(to: text, atomically: true, encoding: .utf8)
            jsonURL = json; textURL = text
        } catch { self.error = "Bericht: \(error.localizedDescription)" }
    }

    func importFile(_ url: URL) {
        do {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 8 * 1024 * 1024 else { throw IQSummary.IQError.tooLarge }
            analyze(try Data(contentsOf: url), label: "Lokale Datei")
        } catch { fileMessage = "Import: \(error.localizedDescription)"; analysis = nil; saveReports() }
    }

    func analyze(_ data: Data, label: String) {
        guard !fileBusy else { return }
        guard let sampleRate = Double(rate.replacingOccurrences(of: ",", with: ".")), sampleRate.isFinite, sampleRate > 0 else {
            fileMessage = "Bitte eine positive Samplerate eingeben."; analysis = nil; saveReports(); return
        }
        let selectedSF = sf, selectedBW = Double(bandwidth)
        fileBusy = true
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try IQAnalysis.analyze(data, sampleRate: sampleRate, bandwidth: selectedBW, sf: selectedSF)
                }.value
                analysis = result; fileMessage = label
            } catch { analysis = nil; fileMessage = "Analyse: \(error.localizedDescription)" }
            fileBusy = false; saveReports()
        }
    }

    func demo() {
        let value = 173 % (1 << sf)
        let data = IQAnalysis.fixture(sf: sf, value: value)
        rate = String(bandwidth)
        do {
            let url = documents.appendingPathComponent("LoRaLab-Synthetic-SF\(sf)-Bin\(value).cf32")
            try data.write(to: url, options: .atomic); demoURL = url
            analyze(data, label: "Synthetische Referenz · erwarteter Bin \(value)")
        } catch { fileMessage = error.localizedDescription }
    }
}

struct LabView: View {
    @StateObject private var model = LabModel()
    @State private var importing = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            NavigationStack { RadioView(model: model).navigationTitle("Funkpfad") }
                .tabItem { Label("Funkpfad", systemImage: "antenna.radiowaves.left.and.right") }
            NavigationStack { dashboard.navigationTitle("LoRa Lab") }
                .tabItem { Label("Tests", systemImage: "waveform.path.ecg") }
            NavigationStack { files.navigationTitle("I/Q untersuchen") }
                .tabItem { Label("Dateien", systemImage: "waveform") }
            NavigationStack { reports.navigationTitle("Berichte") }
                .tabItem { Label("Berichte", systemImage: "doc.text.magnifyingglass") }
        }
        .tint(.mint).preferredColorScheme(.dark)
        .task { model.startAutomatically() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.background() }
            else if phase == .active { model.foreground() }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { response in
            do { if let url = try response.get().first { model.importFile(url) } }
            catch { model.fileMessage = error.localizedDescription }
        }
    }
    private var dashboard: some View {
        List {
            Section {
                Label("Live-Funkzugang noch offen", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.headline).foregroundStyle(.orange)
                Text("Die folgenden Messungen verwenden synthetische Signale. Sie empfangen keine LoRa-Pakete.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Automatischer Testlauf") {
                if model.busy {
                    HStack { ProgressView(); Text("Signaltests laufen …") }.accessibilityIdentifier("suite-running")
                } else if let report = model.report {
                    Label(report.failedChecks == 0 ? "Softwaretests bestanden" : "Prüfungen fehlgeschlagen",
                          systemImage: report.failedChecks == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(report.failedChecks == 0 ? .mint : .red)
                        .accessibilityIdentifier("suite-complete")
                    LabeledContent("Testfälle", value: "\(report.totalCases)")
                    LabeledContent("Fehlerhafte Gruppen", value: "\(report.failedChecks)")
                    LabeledContent("Laufzeit", value: String(format: "%.2f s", report.totalMilliseconds / 1000))
                }
                Button("Tests erneut starten") { model.run() }.disabled(model.busy)
                Button("Erweiterten Testlauf starten") { model.run(extended: true) }.disabled(model.busy)
                Text("Reine Berechnung mit künstlichen Signalen. Die separate Zeitdiagnose findest du im Tab Funkpfad.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let report = model.report {
                Section("Prüfgruppen") {
                    ForEach(report.checks) { check in
                        DisclosureGroup {
                            Text(check.detail).font(.caption)
                            LabeledContent("Fälle / Abweichungen", value: "\(check.cases) / \(check.errors)")
                            LabeledContent("Laufzeit", value: String(format: "%.1f ms", check.milliseconds))
                            if let ms = check.metrics["millisecondsPerSymbol"] {
                                LabeledContent("Pro SF11-Symbol", value: String(format: "%.3f ms", ms))
                            }
                        } label: {
                            HStack {
                                Image(systemName: check.status == "passed" ? "checkmark.circle.fill" : check.status == "failed" ? "xmark.circle.fill" : check.status == "unsupported" ? "lock.fill" : "chart.bar.fill")
                                    .foregroundStyle(check.status == "passed" ? .mint : check.status == "failed" ? .red : .orange)
                                Text(check.name).font(.subheadline)
                            }
                        }
                    }
                }
                Section("Rauschen · Symbolfehlerrate") {
                    NoiseChart(measurements: report.noise).frame(height: 180)
                    Text("SNR −18 bis +10 dB · AWGN-Simulation · bekannte Symbolgrenzen. Keine gemessene Empfindlichkeit der iPhone-Funkhardware.")
                        .font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("Alle 30 Messpunkte") {
                        ForEach(report.noise) { row in
                            LabeledContent("SF\(row.sf) · \(Int(row.snrDB)) dB", value: "\(row.errors)/\(row.trials) Fehler")
                                .font(.caption)
                        }
                    }
                }
            }
            Section("Gerät und Build") {
                LabeledContent("Version", value: "\(model.environment.appVersion) (\(model.environment.build))")
                LabeledContent("Gerät", value: model.environment.model)
                LabeledContent("iOS", value: model.environment.os)
                LabeledContent("Prozessoren / RAM", value: "\(model.environment.processorCount) / \(model.environment.memoryMiB) MiB")
                Text("Ziel: EU868 LongFast · 869,525 MHz · SF11 / BW250 / CR4/5").font(.caption)
                Link("Neue Version installieren", destination: URL(string: "https://p1337.github.io/meshtastic-backend/")!)
            }
        }
    }
    private var files: some View {
        List {
            Section("Analyse konfigurieren") {
                TextField("Samplerate (Samples/s)", text: $model.rate).keyboardType(.decimalPad)
                Picker("Spreading Factor", selection: $model.sf) { ForEach(7...12, id: \.self) { Text("SF\($0)").tag($0) } }
                Picker("Bandbreite", selection: $model.bandwidth) {
                    ForEach([125000, 250000, 500000], id: \.self) { Text("\($0 / 1000) kHz").tag($0) }
                }
                Text("Diese Einstellungen betreffen nur die Datei. BW500 ist keine Meshtastic-EU868-Sendekonfiguration.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Lokale I/Q-Daten") {
                Button("CF32LE-Datei auswählen") { importing = true }.disabled(model.fileBusy)
                Button("Synthetische Referenz erzeugen und prüfen") { model.demo() }.disabled(model.fileBusy)
                if let demo = model.demoURL { ShareLink("Referenzdatei teilen", item: demo) }
                if model.fileBusy { ProgressView("Datei wird untersucht …") }
                Text(model.fileMessage).font(.caption).textSelection(.enabled)
                Text("Float32 little-endian, I/Q abwechselnd; maximal 8 MiB. Keine automatische Aufnahme und kein Upload.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let a = model.analysis {
                Section("Messwerte") {
                    LabeledContent("Samples", value: "\(a.sampleCount)")
                    LabeledContent("Dauer", value: String(format: "%.6f s", a.duration))
                    LabeledContent("Mittlere Leistung", value: String(format: "%.6g", a.meanPower))
                    LabeledContent("Spitzenleistung", value: String(format: "%.6g", a.peakPower))
                    LabeledContent("DC I / Q", value: String(format: "%.4g / %.4g", a.dcI, a.dcQ))
                    LabeledContent("Komponente nahe ±1", value: String(format: "%.2f %%", 100 * a.nearFullScaleFraction))
                    Text("Nur ein Hinweis bei auf ±1 normierten Dateien; keine bestätigte ADC-Übersteuerung.")
                        .font(.caption).foregroundStyle(.secondary)
                    LabeledContent("Erster Symbolbin", value: a.symbolBin.map(String.init) ?? "nicht ausgewertet")
                    if let fraction = a.peakEnergyFraction {
                        LabeledContent("Energie im Spitzenbin", value: String(format: "%.2f %%", 100 * fraction))
                    }
                    Text(a.note).font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }
    private var reports: some View {
        List {
            Section("Automatisch gespeichert") {
                if let url = model.jsonURL { ShareLink("JSON-Bericht teilen", item: url).accessibilityIdentifier("share-json") }
                if let url = model.textURL { ShareLink("Textbericht teilen", item: url) }
                Button("Berichte aktualisieren") { model.saveReports() }.disabled(model.report == nil)
                if let error = model.error { Text(error).foregroundStyle(.red) }
                Text("Teile den JSON-Bericht hier im Chat. Er enthält die Geräteprüfung, Fehlercodes, ausgewählte Berechtigungen und die Zeitdiagnose sowie Softwaretests und gegebenenfalls Dateistatistik. Keine Rohsamples, Konten, SIM-Kennung, Standorte oder dauerhafte Gerätekennung.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Was ist automatisiert?") {
                Label("Signaltests und Messbericht beim App-Start", systemImage: "iphone")
                Label("Geräteprüfung und 60-Sekunden-Zeitdiagnose beim Start", systemImage: "timer")
                Label("Tests, Simulator-Start, Signierung und Veröffentlichung in GitHub", systemImage: "gearshape.2")
                Text("Der Simulator bestätigt keine Geräte-HF-Funktion. Dein echtes iPhone lässt sich aus diesem Chat nicht unbeaufsichtigt fernbedienen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct NoiseChart: View {
    let measurements: [NoiseMeasurement]
    private let colors: [Color] = [.mint, .blue, .orange, .pink, .purple, .yellow]
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack {
                    Path { p in
                        for value in [0.0, 0.5, 1.0] {
                            p.move(to: CGPoint(x: 0, y: geometry.size.height * value))
                            p.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height * value))
                        }
                    }.stroke(.secondary.opacity(0.3), lineWidth: 1)
                    ForEach(7...12, id: \.self) { sf in
                        Path { p in
                            let rows = measurements.filter { $0.sf == sf }.sorted { $0.snrDB < $1.snrDB }
                            for (index, row) in rows.enumerated() {
                                let x = (row.snrDB + 18) / 28 * geometry.size.width
                                let y = (1 - Double(row.errors) / Double(row.trials)) * geometry.size.height
                                if index == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }.stroke(colors[sf - 7], lineWidth: 2)
                    }
                }
            }
            HStack { Text("−18 dB"); Spacer(); Text("+10 dB") }.font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 8) { ForEach(7...12, id: \.self) { sf in Text("SF\(sf)").foregroundStyle(colors[sf - 7]) } }.font(.caption2)
        }
        .accessibilityLabel("Simulierte Symbolfehlerrate für SF7 bis SF12")
    }
}
