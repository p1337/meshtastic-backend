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
    private let autoPause = AutoPauseController()
    private enum PendingAction { case newRide, recoveredRide }
    private var pendingActionAfterAuthorization: PendingAction?
    private var elapsedTimer: Timer?
    private var applicationIsActive = true

    var active: Bool { sessionPhase == .recording || sessionPhase == .paused }
    var isRecording: Bool { sessionPhase == .recording }
    var isPaused: Bool { sessionPhase == .paused }
    var isAutoPaused: Bool { isPaused && autoPause.isAutomaticallyPaused }
    var recoveryAvailable: Bool { sessionPhase == .recoveryRequired }

    private var autoPauseConfiguration: AutoPauseConfiguration {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: "rideAutoPauseEnabled") == nil
            ? true
            : defaults.bool(forKey: "rideAutoPauseEnabled")
        let speed = defaults.object(forKey: "rideAutoPauseSpeedKmh") == nil
            ? 2.5
            : defaults.double(forKey: "rideAutoPauseSpeedKmh")
        let delay = defaults.object(forKey: "rideAutoPauseDelaySeconds") == nil
            ? 8
            : defaults.double(forKey: "rideAutoPauseDelaySeconds")
        return AutoPauseConfiguration(
            enabled: enabled,
            pauseBelowKmh: min(max(speed, 1), 8),
            pauseDelaySeconds: min(max(delay, 3), 30)
        )
    }

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

    func activateLiveLocation() {
        guard CLLocationManager.locationServicesEnabled() else {
            status = "Ortungsdienste am iPhone einschalten"
            return
        }
        if location.authorizationStatus == .notDetermined {
            status = "Standortfreigabe wird angefordert"
            location.requestWhenInUseAuthorization()
            return
        }
        guard location.authorizationStatus == .authorizedWhenInUse
                || location.authorizationStatus == .authorizedAlways else {
            status = "Standortzugriff in Einstellungen erlauben"
            return
        }
        updateLocationMode()
    }

    func setApplicationActive(_ isActive: Bool) {
        applicationIsActive = isActive
        updateLocationMode()
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
        autoPause.reset()
        sessionEngine.start(now: Date())
        trackCoordinates = []
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
        autoPause.manualPause()
        sessionEngine.pause(now: Date())
        syncFromSession(now: Date())
        updateLocationMode()
        status = "Fahrt pausiert"
    }

    func resume() {
        guard isPaused else { return }
        guard location.authorizationStatus == .authorizedWhenInUse
                || location.authorizationStatus == .authorizedAlways else {
            status = "Standortzugriff in Einstellungen erlauben"
            return
        }
        autoPause.manualResume()
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
        autoPause.reset()
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

    private func startLocationUpdates() { updateLocationMode() }

    private func updateLocationMode() {
        let allowed = location.authorizationStatus == .authorizedWhenInUse
            || location.authorizationStatus == .authorizedAlways
        let mode = LocationModePolicy.mode(
            isAuthorized: allowed,
            servicesEnabled: CLLocationManager.locationServicesEnabled(),
            applicationIsActive: applicationIsActive,
            isRecording: isRecording || autoPause.isAutomaticallyPaused
        )
        switch mode {
        case .off:
            location.stopUpdatingLocation()
            location.allowsBackgroundLocationUpdates = false
            location.showsBackgroundLocationIndicator = false
            location.pausesLocationUpdatesAutomatically = true
        case .recordingBackground:
            location.allowsBackgroundLocationUpdates = true
            location.showsBackgroundLocationIndicator = true
            location.pausesLocationUpdatesAutomatically = false
            location.startUpdatingLocation()
        case .foregroundLive:
            location.allowsBackgroundLocationUpdates = false
            location.showsBackgroundLocationIndicator = false
            location.pausesLocationUpdatesAutomatically = false
            location.startUpdatingLocation()
        }
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
        } else if allowed {
            updateLocationMode()
        } else if manager.authorizationStatus != .notDetermined {
            manager.stopUpdatingLocation()
        }
    }

    func stop() {
        guard active else { return }
        finishSession()
    }

    private func finishSession() {
        autoPause.reset()
        _ = sessionEngine.finish(now: Date())
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        syncFromSession(now: Date())
        updateLocationMode()
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
        guard let point = updates.last(where: {
            $0.horizontalAccuracy >= 0
                && $0.horizontalAccuracy < 100
                && abs($0.timestamp.timeIntervalSinceNow) < 30
        }) else { return }
        currentCoordinate = point.coordinate
        currentHorizontalAccuracy = point.horizontalAccuracy
        if point.verticalAccuracy >= 0 { elevation = point.altitude }
        speedKmh = point.speed >= 0 ? point.speed * 3.6 : 0
        if point.course >= 0, point.speed >= 0.8 { courseDegrees = point.course }

        guard active else { return }
        let autoPauseAction = autoPause.evaluate(
            speedKmh: point.speed >= 0 ? point.speed * 3.6 : nil,
            at: point.timestamp,
            configuration: autoPauseConfiguration
        )
        switch autoPauseAction {
        case .pause where isRecording:
            sessionEngine.pause(now: Date())
            syncFromSession(now: Date())
            updateLocationMode()
            status = "Auto-Pause · Bewegung startet wieder"
            return
        case .resume where isPaused:
            sessionEngine.resume(now: Date())
            syncFromSession(now: Date())
            updateLocationMode()
            status = "Aufzeichnung automatisch fortgesetzt"
        default:
            break
        }
        guard isRecording else { return }
        let recordingUpdates = autoPauseAction == .resume ? [point] : updates
        var acceptedPoint = false
        for point in recordingUpdates {
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
        maximumSpeedKmh = snapshot.maximumSpeedKmh
        ascent = snapshot.ascentMeters
        descent = snapshot.descentMeters
        points = snapshot.samples.count
        trackCoordinates = snapshot.samples.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        let shouldUseRecordedPosition = sessionPhase == .recording || currentCoordinate == nil
        if shouldUseRecordedPosition, let latest = snapshot.samples.last {
            speedKmh = snapshot.latestSpeedKmh
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
    @State private var routePlan: RideRoutePlan?
    @State private var routeMessage: String

    init() {
        do {
            let restored = try RoutePlanStore.load()
            _routePlan = State(initialValue: restored)
            _routeMessage = State(initialValue:
                restored?.summary ?? "Noch keine GPX-Strecke importiert"
            )
        } catch {
            try? RoutePlanStore.clear()
            _routePlan = State(initialValue: nil)
            _routeMessage = State(initialValue:
                "Gespeicherte Route konnte nicht geladen werden"
            )
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                RideDashboard(
                    ride: ride,
                    sensors: sensors,
                    importing: $importing,
                    routePlan: routePlan,
                    routeMessage: routeMessage,
                    selectPlannedRoute: { plan in
                        activateRoute(plan)
                    },
                    clearRoute: clearRoute
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
            .tabItem {
                Label {
                    Text("Outdoor")
                } icon: {
                    Image("OutdoorTab")
                }
            }
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
                .navigationTitle("Indoor")
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
            .tabItem {
                Label {
                    Text("Indoor")
                } icon: {
                    Image("IndoorTab")
                }
            }
            .tag(AppTab.indoor)
        }
        .onOpenURL { url in
            importGPX(from: url, source: "Geteilt")
        }
        .onChange(of: scenePhase) { _, phase in
            ride.setApplicationActive(phase == .active)
            if phase == .background || phase == .inactive {
                ride.persistNow()
            }
        }
        .tint(Color(red:1,green:0.57,blue:0))
        .preferredColorScheme(.dark)
    }

    private func importGPX(from url: URL, source: String) {
        do {
            let coordinates = try GPXParser.load(url)
            selectedTab = .recording
            let name = url.deletingPathExtension().lastPathComponent
            let points = coordinates.map {
                RoutePoint(latitude: $0.latitude, longitude: $0.longitude)
            }
            let summary = "\(name) · \(coordinates.count) Punkte · \(source)"
            activateRoute(RideRoutePlan(
                destinationName: name,
                providerName: "GPX",
                summary: summary,
                distanceMeters: NavigationProgressEngine.routeLengthMeters(points),
                expectedTravelTime: 0,
                points: points,
                maneuvers: []
            ))
        } catch {
            routeMessage = "Import fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func activateRoute(_ plan: RideRoutePlan) {
        routePlan = plan
        routeMessage = plan.summary
        do {
            try RoutePlanStore.save(plan)
        } catch {
            routeMessage = "\(plan.summary) · Sicherung fehlgeschlagen"
        }
    }

    private func clearRoute() {
        routePlan = nil
        routeMessage = "Keine aktive Route"
        do {
            try RoutePlanStore.clear()
        } catch {
            routeMessage = "Route beendet · Löschen der Sicherung fehlgeschlagen"
        }
    }
}

private struct RideDashboard: View {
    @ObservedObject var ride: RideTracker
    @ObservedObject var sensors: SensorHub
    @Binding var importing: Bool
    let routePlan: RideRoutePlan?
    let routeMessage: String
    let selectPlannedRoute: (RideRoutePlan) -> Void
    let clearRoute: () -> Void
    @State private var showingCameraSync = false
    @State private var showingRoutePlanner = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LiveRideMap(
                    coordinates: ride.trackCoordinates,
                    plannedRoute: routeCoordinates,
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
        .sheet(isPresented: $showingRoutePlanner) {
            RoutePlannerView(
                origin: ride.currentCoordinate,
                onSelectRoute: selectPlannedRoute
            )
        }
        .onAppear { ride.activateLiveLocation() }
    }

    private var cockpitOverlay: some View {
        VStack(spacing: 7) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ride.isRecording ? Color.green : (ride.recoveryAvailable ? Color.red : Color.orange))
                            .frame(width: 8, height: 8)
                        Text(ride.isAutoPaused ? "AUTO-PAUSE" : "TEMPO")
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

            HStack(spacing: 6) {
                RideMetric(title: "PULS", value: sensors.heartRateBpm.map { "\($0)" } ?? "–")
                RideMetric(title: "KADENZ", value: sensors.cadenceRpm.map { String(format: "%.0f", $0) } ?? "–")
                RideMetric(title: "WATT", value: sensors.powerWatts.map { "\($0)" } ?? "–")
                RideMetric(title: "AKKU", value: sensors.batteryPercent.map { "\($0)%" } ?? "–")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.18)))
    }

    private var bottomOverlay: some View {
        VStack(spacing: 8) {
            if let navigationProgress {
                navigationBanner(navigationProgress)
            } else if routePlan != nil {
                HStack(spacing: 8) {
                    Text(routeMessage)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    clearRouteButton
                }
                .padding(.leading, 12)
                .padding(.trailing, 4)
                .padding(.vertical, 4)
                .background(.black.opacity(0.78), in: Capsule())
            }

            if ride.active {
                HStack(spacing: 10) {
                    primaryRideButton
                    Button { ride.stop() } label: {
                        Image(systemName: "stop.fill")
                            .font(.title2.weight(.bold))
                            .frame(width: 60, height: 60)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .accessibilityLabel("Fahrt beenden")
                }
            } else {
                primaryRideButton
            }

            HStack(spacing: 8) {
                Button { showingRoutePlanner = true } label: {
                    Image(systemName: "map.fill")
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .compactToolButton()
                .accessibilityLabel("Zielroute planen")

                Button { importing = true } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .compactToolButton()
                .accessibilityLabel("GPX-Strecke importieren")

                Button { showingCameraSync = true } label: {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .compactToolButton()
                .disabled(!ride.active && ride.points == 0)
                .accessibilityLabel("DJI Action 5 Pro synchronisieren")

                if let url = ride.exportURL {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .compactToolButton()
                    .accessibilityLabel("Aufgezeichnete GPX teilen")
                } else {
                    Button {} label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .compactToolButton()
                    .disabled(true)
                    .accessibilityLabel("GPX-Teilen nach abgeschlossener Aufzeichnung verfügbar")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        routePlan?.points.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        } ?? []
    }

    private var navigationProgress: NavigationProgress? {
        guard let routePlan, let coordinate = ride.currentCoordinate else { return nil }
        return NavigationProgressEngine.progress(
            position: RoutePoint(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ),
            plan: routePlan
        )
    }

    private func navigationBanner(_ progress: NavigationProgress) -> some View {
        let isOffRoute = progress.distanceFromRouteMeters >= 60
        let instruction = isOffRoute
            ? "Route verlassen · \(formatRouteDistance(progress.distanceFromRouteMeters)) entfernt"
            : (progress.nextManeuver?.instruction ?? "Route bis zum Ziel folgen")
        let maneuverDistance = progress.distanceToNextManeuverMeters.map(formatRouteDistance)
        let remainingTime = progress.remainingTravelTime.map(formatRouteDuration)
        return HStack(spacing: 10) {
            Image(systemName: isOffRoute
                  ? "exclamationmark.triangle.fill"
                  : "arrow.triangle.turn.up.right.diamond.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(isOffRoute ? .red : .orange)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(instruction)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                HStack(spacing: 7) {
                    if let maneuverDistance, progress.nextManeuver != nil, !isOffRoute {
                        Text("in \(maneuverDistance)")
                    }
                    Text("Rest \(formatRouteDistance(progress.remainingDistanceMeters))")
                    if let remainingTime { Text(remainingTime) }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            clearRouteButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isOffRoute ? Color.red.opacity(0.8) : Color.orange.opacity(0.55))
        )
        .accessibilityElement(children: .contain)
    }

    private var clearRouteButton: some View {
        Button(action: clearRoute) {
            Image(systemName: "xmark")
                .font(.caption.weight(.black))
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Navigation beenden")
    }

    private func formatRouteDistance(_ meters: Double) -> String {
        meters >= 1_000
            ? String(format: "%.1f km", meters / 1_000)
            : String(format: "%.0f m", meters)
    }

    private func formatRouteDuration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        return minutes >= 60
            ? "\(minutes / 60):\(String(format: "%02d", minutes % 60)) Std"
            : "\(minutes) Min"
    }

    @ViewBuilder
    private var primaryRideButton: some View {
        if ride.active {
            Button {
                if ride.isPaused { ride.resume() } else { ride.pause() }
            } label: {
                Label(
                    ride.isPaused ? "Aufzeichnung fortsetzen" : "Aufzeichnung pausieren",
                    systemImage: ride.isPaused ? "play.fill" : "pause.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 60)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        } else if !ride.recoveryAvailable {
            Button { ride.start() } label: {
                Label("Aufzeichnung starten", systemImage: "play.fill")
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .accessibilityHint("Beginnt das Speichern der GPS-Spur und Fahrtdaten")
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
    @AppStorage("rideMap3DEnabled") private var rideMap3DEnabled = true
    @AppStorage("rideMapStickToRoute") private var rideMapStickToRoute = false
    @AppStorage("rideAutoPauseEnabled") private var rideAutoPauseEnabled = true
    @AppStorage("rideAutoPauseSpeedKmh") private var rideAutoPauseSpeedKmh = 2.5
    @AppStorage("rideAutoPauseDelaySeconds") private var rideAutoPauseDelaySeconds = 8.0

    private let zoomPresets: [(String, Double)] = [
        ("Nah", 500),
        ("Fahrt", 1_500),
        ("Voraus", 3_000),
        ("Übersicht", 8_000)
    ]

    var body: some View {
        Form {
            Section("Aufzeichnung") {
                Toggle("Auto-Pause", isOn: $rideAutoPauseEnabled)
                if rideAutoPauseEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Pause unter")
                            Spacer()
                            Text(String(format: "%.1f km/h", rideAutoPauseSpeedKmh))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $rideAutoPauseSpeedKmh, in: 1...8, step: 0.5)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Verzögerung")
                            Spacer()
                            Text("\(Int(rideAutoPauseDelaySeconds)) s")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $rideAutoPauseDelaySeconds, in: 3...30, step: 1)
                    }
                    Text("Stoppt die Fahrzeit erst nach anhaltendem Stillstand. Bewegung startet automatisch wieder; eine manuelle Pause bleibt immer bestehen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Fahrtkarte") {
                Toggle("Automatischer Zoom", isOn: $rideMapAutoZoom)
                Toggle("Fahrtrichtung oben und Vorausblick", isOn: $rideMapHeadingUp)
                Toggle("Geneigte 3D-Ansicht", isOn: $rideMap3DEnabled)
                Toggle("An geplante Straße kleben", isOn: $rideMapStickToRoute)
                Text(rideMapStickToRoute
                     ? "Nur der Kartenpfeil wird bis 50 m an die aktive Route angelegt. Aufzeichnung, Roh-GPS und Abweichungswarnung bleiben unverändert."
                     : "Roh-GPS: Der Kartenpfeil wird nicht auf eine Nachbarstraße oder Route verschoben.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

private struct CompactToolButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.2)))
    }
}

private extension View {
    func compactToolButton() -> some View {
        modifier(CompactToolButtonModifier())
    }
}
