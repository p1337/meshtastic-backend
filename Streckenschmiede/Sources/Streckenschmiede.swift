import SwiftUI
import CoreLocation
import CoreBluetooth
import Foundation
import MapKit
import UniformTypeIdentifiers

@main
struct StreckenschmiedeApp: App {
    var body: some Scene { WindowGroup { MainView() } }
}
final class RideTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var sessionPhase: RideSessionPhase = .idle
    @Published var distance = 0.0
    @Published var points = 0
    @Published var trackCoordinates: [CLLocationCoordinate2D] = []
    @Published var currentCoordinate: CLLocationCoordinate2D?
    @Published var currentHorizontalAccuracy: Double?
    @Published var courseDegrees: Double?
    @Published var speedKmh = 0.0
    @Published var averageSpeedKmh = 0.0
    @Published var maximumSpeedKmh = 0.0
    @Published var elevation = 0.0
    @Published var ascent = 0.0
    @Published var descent = 0.0
    @Published var elapsedSeconds = 0
    @Published var ridingSeconds = 0
    @Published var pausedSeconds = 0
    @Published var exportURL: URL?
    @Published var status = "Bereit"
    @Published private(set) var rideID = UUID()
    @Published private(set) var startedAt: Date?
    private let location = CLLocationManager()
    private let sessionEngine: RideSessionEngine
    private enum PendingAction { case newRide, recoveredRide }
    private var pendingActionAfterAuthorization: PendingAction?
    private var elapsedTimer: Timer?

    var active: Bool { sessionPhase == .recording || sessionPhase == .paused }
    var isRecording: Bool { sessionPhase == .recording }
    var isPaused: Bool { sessionPhase == .paused }
    var recoveryAvailable: Bool { sessionPhase == .recoveryRequired }

    var elapsedMilliseconds: Int64 {
        Int64(elapsedSeconds) * 1_000
    }

    override init() {
        sessionEngine = RideSessionEngine()
        super.init()
        location.delegate = self
        location.activityType = .fitness
        location.desiredAccuracy = kCLLocationAccuracyBest
        location.distanceFilter = 5
        syncFromSession(now: Date())
        if recoveryAvailable {
            status = "Unterbrochene Fahrt gefunden"
            startElapsedTimer()
        }
    }

    func refreshLocation() {
        guard location.authorizationStatus == .authorizedWhenInUse
                || location.authorizationStatus == .authorizedAlways else { return }
        location.requestLocation()
    }

    func start() {
        guard !active else { return }
        guard CLLocationManager.locationServicesEnabled() else {
            status = "Ortungsdienste am iPhone einschalten"
            return
        }
        if location.authorizationStatus == .notDetermined {
            pendingActionAfterAuthorization = .newRide
            status = "Standortfreigabe wird angefordert"
            location.requestWhenInUseAuthorization()
            return
        }
        guard location.authorizationStatus == .authorizedWhenInUse || location.authorizationStatus == .authorizedAlways else {
            status = "Standortzugriff in Einstellungen erlauben"
            return
        }
        beginRecording()
    }

    private func beginRecording() {
        sessionEngine.start(now: Date())
        trackCoordinates = []
        currentCoordinate = nil
        currentHorizontalAccuracy = nil
        courseDegrees = nil
        distance = 0
        points = 0
        speedKmh = 0
        averageSpeedKmh = 0
        maximumSpeedKmh = 0
        elevation = 0
        ascent = 0
        descent = 0
        elapsedSeconds = 0
        ridingSeconds = 0
        pausedSeconds = 0
        exportURL = nil
        syncFromSession(now: Date())
        startElapsedTimer()
        startLocationUpdates()
        status = sessionEngine.lastPersistenceError == nil
            ? "Aufzeichnung läuft"
            : "Aufzeichnung läuft · Sicherung fehlgeschlagen"
    }

    func pause() {
        guard isRecording else { return }
        sessionEngine.pause(now: Date())
        stopLocationUpdates()
        syncFromSession(now: Date())
        status = "Fahrt pausiert"
    }

    func resume() {
        guard isPaused else { return }
        guard location.authorizationStatus == .authorizedWhenInUse
                || location.authorizationStatus == .authorizedAlways else {
            status = "Standortzugriff in Einstellungen erlauben"
            return
        }
        sessionEngine.resume(now: Date())
        syncFromSession(now: Date())
        startLocationUpdates()
        status = "Aufzeichnung läuft"
    }

    func resumeRecoveredRide() {
        guard recoveryAvailable else { return }
        guard CLLocationManager.locationServicesEnabled() else {
            status = "Ortungsdienste am iPhone einschalten"
            return
        }
        if location.authorizationStatus == .notDetermined {
            pendingActionAfterAuthorization = .recoveredRide
            status = "Standortfreigabe wird angefordert"
            location.requestWhenInUseAuthorization()
            return
        }
        guard location.authorizationStatus == .authorizedWhenInUse
                || location.authorizationStatus == .authorizedAlways else {
            status = "Standortzugriff in Einstellungen erlauben"
            return
        }
        beginRecoveredRecording()
    }

    private func beginRecoveredRecording() {
        sessionEngine.resume(now: Date())
        syncFromSession(now: Date())
        startElapsedTimer()
        startLocationUpdates()
        status = "Fahrt wiederhergestellt"
    }

    func finishRecoveredRide() {
        guard recoveryAvailable else { return }
        finishSession()
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.syncFromSession(now: Date())
        }
        elapsedTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func startLocationUpdates() {
        location.allowsBackgroundLocationUpdates = true
        location.showsBackgroundLocationIndicator = true
        location.pausesLocationUpdatesAutomatically = false
        location.startUpdatingLocation()
    }

    private func stopLocationUpdates() {
        location.stopUpdatingLocation()
        location.allowsBackgroundLocationUpdates = false
        location.showsBackgroundLocationIndicator = false
        location.pausesLocationUpdatesAutomatically = true
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let allowed = manager.authorizationStatus == .authorizedAlways
            || manager.authorizationStatus == .authorizedWhenInUse
        if let pendingActionAfterAuthorization {
            if manager.authorizationStatus == .notDetermined { return }
            self.pendingActionAfterAuthorization = nil
            if allowed {
                switch pendingActionAfterAuthorization {
                case .newRide: beginRecording()
                case .recoveredRide: beginRecoveredRecording()
                }
            } else {
                status = "Standortzugriff verweigert"
            }
        } else if allowed, !isRecording {
            manager.requestLocation()
        }
    }

    func stop() {
        guard active else { return }
        finishSession()
    }

    private func finishSession() {
        _ = sessionEngine.finish(now: Date())
        stopLocationUpdates()
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        syncFromSession(now: Date())
        guard !sessionEngine.samples.isEmpty else {
            sessionEngine.clearPersistedSession()
            sessionPhase = .finished
            status = "Keine GPS-Daten"
            return
        }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        var gpx = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><gpx version=\"1.1\" creator=\"Streckenschmiede\" xmlns=\"http://www.topografix.com/GPX/1/1\"><trk><name>Fahrt</name><trkseg>"
        for sample in sessionEngine.samples {
            gpx += "<trkpt lat=\"\(sample.latitude)\" lon=\"\(sample.longitude)\"><ele>\(sample.altitude)</ele><time>\(f.string(from:sample.timestamp))</time></trkpt>"
        }
        gpx += "</trkseg></trk></gpx>"
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let url = documents.appendingPathComponent("Fahrt-\(Int(Date().timeIntervalSince1970)).gpx")
        do {
            try gpx.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
            sessionEngine.clearPersistedSession()
            sessionPhase = .finished
            status = "GPX bereit"
        }
        catch { status = error.localizedDescription }
    }

    func persistNow() {
        sessionEngine.persistNow(now: Date())
        if sessionEngine.lastPersistenceError != nil, active {
            status = "Fahrt läuft · Sicherung fehlgeschlagen"
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations updates: [CLLocation]) {
        if !isRecording {
            guard let point = updates.last(where: {
                $0.horizontalAccuracy >= 0
                    && $0.horizontalAccuracy < 100
                    && abs($0.timestamp.timeIntervalSinceNow) < 30
            }) else { return }
            currentCoordinate = point.coordinate
            currentHorizontalAccuracy = point.horizontalAccuracy
            if point.verticalAccuracy >= 0 { elevation = point.altitude }
            return
        }
        var acceptedPoint = false
        for point in updates {
            let sample = RideSample(
                latitude: point.coordinate.latitude,
                longitude: point.coordinate.longitude,
                altitude: point.altitude,
                horizontalAccuracy: point.horizontalAccuracy,
                verticalAccuracy: point.verticalAccuracy,
                speedMetersPerSecond: point.speed,
                courseDegrees: point.course,
                timestamp: point.timestamp
            )
            if sessionEngine.append(sample, now: Date()) { acceptedPoint = true }
        }
        if acceptedPoint { syncFromSession(now: Date()) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let locationError = error as? CLError
        if locationError?.code == .locationUnknown {
            if !active { status = "GPS-Position wird gesucht" }
            return
        }
        if locationError?.code == .denied {
            status = "Standortzugriff in Einstellungen erlauben"
        } else {
            status = active ? "GPS vorübergehend nicht verfügbar" : "GPS-Position nicht verfügbar"
        }
    }

    private func syncFromSession(now: Date) {
        guard let snapshot = sessionEngine.snapshot else { return }
        sessionPhase = snapshot.phase
        rideID = snapshot.rideID
        startedAt = snapshot.startedAt
        distance = snapshot.distanceMeters
        speedKmh = snapshot.latestSpeedKmh
        maximumSpeedKmh = snapshot.maximumSpeedKmh
        ascent = snapshot.ascentMeters
        descent = snapshot.descentMeters
        points = snapshot.samples.count
        trackCoordinates = snapshot.samples.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        if let latest = snapshot.samples.last {
            currentCoordinate = CLLocationCoordinate2D(
                latitude: latest.latitude,
                longitude: latest.longitude
            )
            currentHorizontalAccuracy = latest.horizontalAccuracy
            if latest.verticalAccuracy >= 0 { elevation = latest.altitude }
            if latest.courseDegrees >= 0, latest.speedMetersPerSecond >= 1 {
                courseDegrees = latest.courseDegrees
            }
        }
        let durations = sessionEngine.durations(at: now)
        elapsedSeconds = max(0, Int(durations.totalSeconds))
        ridingSeconds = max(0, Int(durations.ridingSeconds))
        pausedSeconds = max(0, Int(durations.pausedSeconds))
        averageSpeedKmh = ridingSeconds > 0
            ? distance / Double(ridingSeconds) * 3.6
            : 0
    }
}
struct MainView: View {
    private enum AppTab: Hashable {
        case recording
        case indoor
    }

    @StateObject private var ride = RideTracker()
    @StateObject private var sensors = SensorHub()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .recording
    @State private var importing = false
    @State private var route: [CLLocationCoordinate2D] = []
    @State private var routeMessage = "Noch keine GPX-Strecke importiert"
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                RideDashboard(
                    ride: ride,
                    sensors: sensors,
                    importing: $importing,
                    route: route,
                    routeMessage: routeMessage
                )
                .fileImporter(isPresented: $importing, allowedContentTypes: [.gpx, .xml]) { result in
                    do {
                        let url = try result.get()
                        importGPX(from: url, source: "Dateien")
                    } catch {
                        routeMessage = "Import fehlgeschlagen: \(error.localizedDescription)"
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
            }
            .tabItem { Label("Aufzeichnung",systemImage:"record.circle") }
            .tag(AppTab.recording)
            NavigationStack {
                Form {
                    Section("Live-Sensordaten") {
                        HStack {
                            SensorValue(title: "Puls", value: sensors.heartRateBpm.map { "\($0) bpm" } ?? "–")
                            SensorValue(title: "Kadenz", value: sensors.cadenceRpm.map { String(format: "%.0f rpm", $0) } ?? "–")
                            SensorValue(title: "Leistung", value: sensors.powerWatts.map { "\($0) W" } ?? "–")
                        }
                    }
                    TrainerControlPanel(sensors: sensors)
                    Section("Fahrradsensoren und Trainer") {
                        Text(sensors.status)
                            .foregroundStyle(.secondary)
                        Button {
                            sensors.scan()
                        } label: {
                            Label("Sensoren, D100 und Clicks suchen", systemImage: "dot.radiowaves.left.and.right")
                        }
                        ForEach(sensors.devices) { device in
                            SensorDeviceRow(
                                device: device,
                                isSelectedTrainer: sensors.trainerDeviceID == device.id,
                                toggleConnection: { sensors.toggleConnection(device.id) },
                                selectTrainer: { sensors.selectTrainer(device.id) }
                            )
                        }
                    }
                    Section("Trainingsprogramme") {
                        Text("ERG, Intervalle und RLV werden vorbereitet")
                    }
                }
                .navigationTitle("Indoor-Training")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .tabItem { Label("Indoor-Training",systemImage:"bicycle") }
            .tag(AppTab.indoor)
        }
        .onOpenURL { url in
            importGPX(from: url, source: "Geteilt")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                ride.persistNow()
            }
        }
        .tint(Color(red:1,green:0.57,blue:0))
        .preferredColorScheme(.dark)
    }

    private func importGPX(from url: URL, source: String) {
        do {
            route = try GPXParser.load(url)
            selectedTab = .recording
            let name = url.deletingPathExtension().lastPathComponent
            routeMessage = "\(name) · \(route.count) Punkte · \(source)"
        } catch {
            routeMessage = "Import fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}

private struct RideDashboard: View {
    @ObservedObject var ride: RideTracker
    @ObservedObject var sensors: SensorHub
    @Binding var importing: Bool
    let route: [CLLocationCoordinate2D]
    let routeMessage: String
    @State private var showingCameraSync = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LiveRideMap(
                    coordinates: ride.trackCoordinates,
                    plannedRoute: route,
                    currentCoordinate: ride.currentCoordinate,
                    speedKmh: ride.speedKmh,
                    courseDegrees: ride.courseDegrees
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .ignoresSafeArea(edges: .top)

                VStack(spacing: 0) {
                    cockpitOverlay
                    Spacer(minLength: 170)
                    bottomOverlay
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 12)

                if ride.recoveryAvailable { recoveryOverlay }
            }
        }
        .background(Color.black)
        .sheet(isPresented: $showingCameraSync) {
            CameraSyncView(ride: ride)
        }
        .onAppear { ride.refreshLocation() }
    }

    private var cockpitOverlay: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(ride.isRecording ? Color.green : (ride.recoveryAvailable ? Color.red : Color.orange))
                        .frame(width: 8, height: 8)
                    Text("TEMPO")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", ride.speedKmh))
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .monospacedDigit()
                    Text("km/h")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 122, alignment: .leading)

            LazyVGrid(columns: columns, spacing: 6) {
                RideMetric(title: "km", value: String(format: "%.2f", ride.distance / 1_000))
                RideMetric(title: "Ø", value: String(format: "%.1f", ride.averageSpeedKmh))
                RideMetric(title: "max", value: String(format: "%.1f", ride.maximumSpeedKmh))
                RideMetric(title: "Fahrt", value: formatDuration(ride.ridingSeconds))
                RideMetric(title: "Höhe", value: String(format: "%.0f m", ride.elevation))
                RideMetric(title: "Auf/Ab", value: String(format: "%.0f/%.0f", ride.ascent, ride.descent))
            }

            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.orange)
            .background(.black.opacity(0.7), in: Circle())
            .accessibilityLabel("Einstellungen")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.18)))
    }

    private var bottomOverlay: some View {
        VStack(spacing: 8) {
            if !route.isEmpty {
                Text(routeMessage)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.78), in: Capsule())
            }

            HStack(spacing: 6) {
                SensorValue(title: "PULS", value: sensors.heartRateBpm.map { "\($0)" } ?? "–")
                SensorValue(title: "KADENZ", value: sensors.cadenceRpm.map { String(format: "%.0f", $0) } ?? "–")
                SensorValue(title: "WATT", value: sensors.powerWatts.map { "\($0)" } ?? "–")
                SensorValue(title: "AKKU", value: sensors.batteryPercent.map { "\($0)%" } ?? "–")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.15)))

            HStack(spacing: 9) {
                primaryRideButton
                if ride.active {
                    Button { ride.stop() } label: {
                        Image(systemName: "stop.fill")
                            .font(.title2.weight(.bold))
                            .frame(width: 54, height: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .accessibilityLabel("Fahrt beenden")
                }

                Button { importing = true } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.title2.weight(.bold))
                        .frame(width: 54, height: 54)
                }
                .buttonStyle(.borderedProminent)
                .tint(.black.opacity(0.82))
                .accessibilityLabel("GPX-Strecke importieren")

                Button { showingCameraSync = true } label: {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.title2.weight(.bold))
                        .frame(width: 54, height: 54)
                }
                .buttonStyle(.borderedProminent)
                .tint(.black.opacity(0.82))
                .disabled(!ride.active && ride.points == 0)
                .accessibilityLabel("DJI Action 5 Pro synchronisieren")

                if let url = ride.exportURL {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title2.weight(.bold))
                            .frame(width: 54, height: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.black.opacity(0.82))
                    .accessibilityLabel("Aufgezeichnete GPX teilen")
                }
            }
        }
    }

    @ViewBuilder
    private var primaryRideButton: some View {
        if ride.active {
            Button {
                if ride.isPaused { ride.resume() } else { ride.pause() }
            } label: {
                Label(
                    ride.isPaused ? "Fortsetzen" : "Pause",
                    systemImage: ride.isPaused ? "play.fill" : "pause.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        } else if !ride.recoveryAvailable {
            Button { ride.start() } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
    }

    private var recoveryOverlay: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Unterbrochene Fahrt wiederherstellen", systemImage: "arrow.clockwise.heart.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("\(ride.points) Trackpunkte und \(formatDuration(ride.elapsedSeconds)) Gesamtzeit wurden sicher gefunden.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Fortsetzen") { ride.resumeRecoveredRide() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .frame(maxWidth: .infinity, minHeight: 52)
                Button("GPX abschließen") { ride.finishRecoveredRide() }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
        }
        .padding()
        .background(.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.orange.opacity(0.7)))
        .padding(24)
    }
}

private struct RideMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.55)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SensorValue: View {
    let title: String
    let value: String
    var source: String? = nil

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let source {
                Text(source)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TrainerControlPanel: View {
    @ObservedObject var sensors: SensorHub
    @State private var resistanceTarget = 0.0
    @State private var powerTarget = 150.0
    @State private var gradeTarget = 0.0

    var body: some View {
        Section("D100 / FTMS-Steuerung") {
            if sensors.trainerDeviceID == nil {
                Text("FTMS-Trainer verbinden und darunter „Als Trainer steuern“ wählen.")
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sensors.trainerName ?? "FTMS-Trainer")
                            .font(.headline)
                        Text(sensors.trainerControlStatus)
                            .font(.caption)
                            .foregroundStyle(sensors.trainerHasControl ? .orange : .secondary)
                    }
                    Spacer()
                    if sensors.trainerCommandInFlight { ProgressView() }
                }

                Button("Steuerung anfordern") { sensors.requestTrainerControl() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(sensors.trainerHasControl || sensors.trainerCommandInFlight)

                HStack(spacing: 12) {
                    Button(sensors.trainerIsRunning ? "Läuft" : "Start") { sensors.startTrainer() }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(!controlsReady || sensors.trainerIsRunning)
                    Button("Pause") { sensors.pauseTrainer() }
                        .buttonStyle(.bordered)
                        .disabled(!controlsReady || !sensors.trainerIsRunning)
                    Button("NOT-STOPP") { sensors.emergencyStopTrainer() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(!controlsReady)
                }
                .controlSize(.large)

                if sensors.trainerCapabilities.resistance,
                   let range = sensors.trainerResistanceRange {
                    targetControl(
                        title: "Widerstand",
                        value: resistanceTarget,
                        unit: "",
                        decrement: { resistanceTarget = adjusted(resistanceTarget, range: range, direction: -1) },
                        increment: { resistanceTarget = adjusted(resistanceTarget, range: range, direction: 1) },
                        apply: { sensors.setTrainerResistance(resistanceTarget) }
                    )
                }

                if sensors.trainerCapabilities.power,
                   let range = sensors.trainerPowerRange {
                    targetControl(
                        title: "ERG-Leistung",
                        value: powerTarget,
                        unit: "W",
                        decrement: { powerTarget = adjusted(powerTarget, range: range, direction: -1) },
                        increment: { powerTarget = adjusted(powerTarget, range: range, direction: 1) },
                        apply: { sensors.setTrainerPower(Int(powerTarget.rounded())) }
                    )
                }

                if let range = safeGradeRange {
                    targetControl(
                        title: sensors.trainerCapabilities.indoorBikeSimulation ? "Simulierte Steigung" : "Steigung",
                        value: gradeTarget,
                        unit: "%",
                        decrement: { gradeTarget = adjusted(gradeTarget, range: range, direction: -1) },
                        increment: { gradeTarget = adjusted(gradeTarget, range: range, direction: 1) },
                        apply: { sensors.setTrainerGrade(gradeTarget) }
                    )
                }

                Text("Jeder Wert wird gegen den vom Trainer gemeldeten Bereich geprüft und erst nach FTMS-Bestätigung übernommen.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: synchronizeTargets)
        .onChange(of: sensors.trainerDeviceID) { _, _ in synchronizeTargets() }
        .onChange(of: sensors.trainerResistanceRange) { _, _ in synchronizeTargets() }
        .onChange(of: sensors.trainerPowerRange) { _, _ in synchronizeTargets() }
        .onChange(of: sensors.trainerInclinationRange) { _, _ in synchronizeTargets() }
    }

    private var controlsReady: Bool {
        sensors.trainerHasControl && !sensors.trainerCommandInFlight
    }

    private var safeGradeRange: FTMSValueRange? {
        if sensors.trainerCapabilities.indoorBikeSimulation {
            return FTMSValueRange(minimum: -10, maximum: 15, increment: 0.5)
        }
        guard sensors.trainerCapabilities.inclination,
              let range = sensors.trainerInclinationRange else { return nil }
        let minimum = max(-10, range.minimum)
        let maximum = min(15, range.maximum)
        guard minimum <= maximum else { return nil }
        return FTMSValueRange(minimum: minimum, maximum: maximum, increment: max(0.1, range.increment))
    }

    @ViewBuilder
    private func targetControl(
        title: String,
        value: Double,
        unit: String,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void,
        apply: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: unit == "W" ? "%.0f %@" : "%.1f %@", value, unit))
                    .font(.headline.monospacedDigit())
            }
            HStack(spacing: 12) {
                Button(action: decrement) { Image(systemName: "minus").frame(minWidth: 42, minHeight: 42) }
                    .buttonStyle(.bordered)
                Button(action: increment) { Image(systemName: "plus").frame(minWidth: 42, minHeight: 42) }
                    .buttonStyle(.bordered)
                Button("Übernehmen", action: apply)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .frame(minHeight: 52)
                    .disabled(!controlsReady)
            }
        }
        .padding(.vertical, 4)
    }

    private func adjusted(_ value: Double, range: FTMSValueRange, direction: Double) -> Double {
        let step = max(range.increment, range.increment == 0 ? 1 : range.increment)
        return min(max(value + direction * step, range.minimum), range.maximum)
    }

    private func synchronizeTargets() {
        if let range = sensors.trainerResistanceRange {
            let candidate = sensors.trainerTargetResistance ?? sensors.resistanceLevel ?? max(0, range.minimum)
            resistanceTarget = min(max(candidate, range.minimum), range.maximum)
        }
        if let range = sensors.trainerPowerRange {
            let candidate = Double(sensors.trainerTargetPower ?? sensors.powerWatts ?? 150)
            powerTarget = min(max(candidate, range.minimum), range.maximum)
        }
        if let range = safeGradeRange {
            gradeTarget = min(max(sensors.trainerTargetGrade ?? 0, range.minimum), range.maximum)
        }
    }
}

private struct SensorDeviceRow: View {
    let device: SensorDeviceSnapshot
    let isSelectedTrainer: Bool
    let toggleConnection: () -> Void
    let selectTrainer: () -> Void

    private var values: String {
        var parts: [String] = []
        if let heartRate = device.heartRateBpm { parts.append("\(heartRate) bpm") }
        if let cadence = device.cadenceRpm { parts.append(String(format: "%.0f rpm", cadence)) }
        if let power = device.powerWatts { parts.append("\(power) W") }
        if let speed = device.speedKmh { parts.append(String(format: "%.1f km/h", speed)) }
        if let battery = device.batteryPercent { parts.append("Akku \(battery)%") }
        return parts.isEmpty ? "Noch keine Messwerte" : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.headline)
                    Text(device.services.isEmpty ? "Dienste nach Verbindung" : device.services.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(device.isConnected ? "Trennen" : "Verbinden", action: toggleConnection)
                    .buttonStyle(.bordered)
                    .tint(device.isConnected ? .red : .orange)
            }
            Text(values)
                .font(.caption.monospacedDigit())
            if device.canControlFTMS {
                Button(isSelectedTrainer ? "Aktiver Trainer" : "Als Trainer steuern", action: selectTrainer)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(isSelectedTrainer)
            }
            HStack {
                Text(device.connectionState)
                Spacer()
                Text("\(device.rssi) dBm")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private func formatDuration(_ seconds: Int) -> String {
    let hours = seconds / 3_600
    let minutes = (seconds % 3_600) / 60
    let remainingSeconds = seconds % 60
    return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
}

struct SettingsView: View {
    @AppStorage("rideMapZoomMeters") private var rideMapZoomMeters = 1_500.0
    @AppStorage("rideMapAutoZoom") private var rideMapAutoZoom = true
    @AppStorage("rideMapHeadingUp") private var rideMapHeadingUp = true

    private let zoomPresets: [(String, Double)] = [
        ("Nah", 500),
        ("Fahrt", 1_500),
        ("Voraus", 3_000),
        ("Übersicht", 8_000)
    ]

    var body: some View {
        Form {
            Section("Fahrtkarte") {
                Toggle("Automatischer Zoom", isOn: $rideMapAutoZoom)
                Toggle("Fahrtrichtung oben und Vorausblick", isOn: $rideMapHeadingUp)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(zoomPresets, id: \.0) { preset in
                            Button {
                                rideMapZoomMeters = preset.1
                            } label: {
                                VStack(spacing: 2) {
                                    Text(preset.0)
                                        .font(.subheadline.weight(.bold))
                                    Text(preset.1 >= 1_000
                                         ? String(format: "%.1f km", preset.1 / 1_000)
                                         : String(format: "%.0f m", preset.1))
                                        .font(.caption.monospacedDigit())
                                }
                                .frame(minWidth: 82, minHeight: 52)
                            }
                            .buttonStyle(.bordered)
                            .tint(abs(rideMapZoomMeters - preset.1) < 1 ? .orange : .secondary)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Standard-Zoom")
                        Spacer()
                        Text(String(format: "%.2f km", rideMapZoomMeters / 1_000))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $rideMapZoomMeters, in: 250...10_000, step: 250)
                }
                Text("Nah, Fahrt, Voraus und Übersicht sind handschuhtaugliche Presets. Der Positionspfeil liegt beim Folgen im unteren Bildschirmdrittel, damit die Karte vor dir den größten Raum erhält.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Streckenschmiede") {
                Text("Einstellungen")
                Text("Version: Entwicklungsstand")
            }
        }
        .navigationTitle("Einstellungen")
    }
}
