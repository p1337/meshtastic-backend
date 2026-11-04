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
    @Published var active = false
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
    @Published var exportURL: URL?
    @Published var status = "Bereit"
    @Published private(set) var rideID = UUID()
    @Published private(set) var startedAt: Date?
    private let location = CLLocationManager()
    private var track: [CLLocation] = []
    private var pendingStartAfterAuthorization = false
    private var elapsedTimer: Timer?

    var elapsedMilliseconds: Int64 {
        guard active, let startedAt else { return Int64(elapsedSeconds) * 1_000 }
        return max(0, Int64(Date().timeIntervalSince(startedAt) * 1_000))
    }
    override init() {
        super.init()
        location.delegate = self
        location.activityType = .fitness
        location.desiredAccuracy = kCLLocationAccuracyBest
        location.distanceFilter = 5
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
            pendingStartAfterAuthorization = true
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
        track = []
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
        exportURL = nil
        rideID = UUID()
        startedAt = Date()
        elapsedTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let startedAt = self.startedAt else { return }
            self.elapsedSeconds = max(0, Int(Date().timeIntervalSince(startedAt)))
            self.updateAverageSpeed()
        }
        elapsedTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        active = true
        location.allowsBackgroundLocationUpdates = true
        location.showsBackgroundLocationIndicator = true
        location.pausesLocationUpdatesAutomatically = false
        location.startUpdatingLocation()
        status = "Aufzeichnung läuft"
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let allowed = manager.authorizationStatus == .authorizedAlways
            || manager.authorizationStatus == .authorizedWhenInUse
        if pendingStartAfterAuthorization {
            if manager.authorizationStatus == .notDetermined { return }
            pendingStartAfterAuthorization = false
            if allowed {
                beginRecording()
            } else {
                status = "Standortzugriff verweigert"
            }
        } else if allowed {
            manager.requestLocation()
        }
    }
    func stop() {
        active = false
        location.stopUpdatingLocation()
        location.allowsBackgroundLocationUpdates = false
        location.showsBackgroundLocationIndicator = false
        location.pausesLocationUpdatesAutomatically = true
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        speedKmh = 0
        guard !track.isEmpty else { status = "Keine GPS-Daten"; return }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        var gpx = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><gpx version=\"1.1\" creator=\"Streckenschmiede\" xmlns=\"http://www.topografix.com/GPX/1/1\"><trk><name>Fahrt</name><trkseg>"
        for p in track {
            gpx += "<trkpt lat=\"\(p.coordinate.latitude)\" lon=\"\(p.coordinate.longitude)\"><ele>\(p.altitude)</ele><time>\(f.string(from:p.timestamp))</time></trkpt>"
        }
        gpx += "</trkseg></trk></gpx>"
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let url = documents.appendingPathComponent("Fahrt-\(Int(Date().timeIntervalSince1970)).gpx")
        do { try gpx.write(to:url,atomically:true,encoding:.utf8); exportURL = url; status = "GPX bereit" }
        catch { status = error.localizedDescription }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations updates: [CLLocation]) {
        if !active {
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
        for p in updates where p.horizontalAccuracy >= 0 && p.horizontalAccuracy < 40 && abs(p.timestamp.timeIntervalSinceNow) < 20 {
            if let last = track.last {
                let d = p.distance(from:last)
                guard d >= 3 && d < 300 else { continue }
                distance += d
                if p.verticalAccuracy >= 0, p.verticalAccuracy < 30,
                   last.verticalAccuracy >= 0, last.verticalAccuracy < 30 {
                    let change = p.altitude - last.altitude
                    if change >= 1 { ascent += change }
                    if change <= -1 { descent += abs(change) }
                }
                let seconds = p.timestamp.timeIntervalSince(last.timestamp)
                let measuredSpeed = p.speed >= 0 ? p.speed : (seconds > 0 ? d / seconds : 0)
                speedKmh = max(0, measuredSpeed * 3.6)
                maximumSpeedKmh = max(maximumSpeedKmh, speedKmh)
            } else if p.speed >= 0 {
                speedKmh = p.speed * 3.6
                maximumSpeedKmh = max(maximumSpeedKmh, speedKmh)
            }
            track.append(p)
            currentCoordinate = p.coordinate
            currentHorizontalAccuracy = p.horizontalAccuracy
            if p.course >= 0, p.speed >= 1 {
                courseDegrees = p.course
            }
            if p.verticalAccuracy >= 0, p.verticalAccuracy < 30 { elevation = p.altitude }
        }
        points = track.count
        trackCoordinates = track.map(\.coordinate)
        updateAverageSpeed()
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
    private func updateAverageSpeed() {
        guard elapsedSeconds > 0 else { averageSpeedKmh = 0; return }
        averageSpeedKmh = distance / Double(elapsedSeconds) * 3.6
    }
}
final class TrainerScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published var status = "Bluetooth wird gestartet"
    @Published var devices: [String] = []
    private var manager: CBCentralManager!
    override init() { super.init(); manager = CBCentralManager(delegate:self,queue:.main) }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        status = central.state == .poweredOn ? "Bluetooth bereit" : "Bluetooth nicht bereit"
    }
    func scan() {
        guard manager.state == .poweredOn else { return }
        devices = []
        manager.scanForPeripherals(withServices:nil,options:[CBCentralManagerScanOptionAllowDuplicatesKey:false])
        status = "Suche läuft"
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String:Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unbekannt"
        let entry = "\(name) – \(peripheral.identifier.uuidString.prefix(8)) – \(RSSI) dBm"
        if !devices.contains(entry) { devices.append(entry) }
    }
}
struct MainView: View {
    private enum AppTab: Hashable {
        case recording
        case indoor
    }

    @StateObject private var ride = RideTracker()
    @StateObject private var ble = TrainerScanner()
    @State private var selectedTab: AppTab = .recording
    @State private var importing = false
    @State private var route: [CLLocationCoordinate2D] = []
    @State private var routeMessage = "Noch keine GPX-Strecke importiert"
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                RideDashboard(
                    ride: ride,
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
                    Section("Indoor-Trainer") {
                        Text(ble.status)
                        Button("D100 und Clicks suchen") { ble.scan() }
                        ForEach(ble.devices,id:\.self) { Text($0).font(.caption) }
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
    @Binding var importing: Bool
    let route: [CLLocationCoordinate2D]
    let routeMessage: String
    @State private var showingCameraSync = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Circle()
                        .fill(ride.active ? Color.green : Color.orange)
                        .frame(width: 9, height: 9)
                    Text(ride.status)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text("GPS · \(ride.points)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
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
                    .background(Color.white.opacity(0.07), in: Circle())
                }
                .padding(.horizontal, 4)

                LiveRideMap(
                    coordinates: ride.trackCoordinates,
                    plannedRoute: route,
                    currentCoordinate: ride.currentCoordinate,
                    speedKmh: ride.speedKmh,
                    courseDegrees: ride.courseDegrees
                )
                .overlay(alignment: .top) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("TEMPO")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(String(format: "%.1f", ride.speedKmh))
                                    .font(.system(size: 49, weight: .black, design: .rounded))
                                    .monospacedDigit()
                                Text("km/h")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(minWidth: 128, alignment: .leading)

                        LazyVGrid(columns: columns, spacing: 8) {
                            RideMetric(title: "km", value: String(format: "%.2f", ride.distance / 1_000))
                            RideMetric(title: "Ø", value: String(format: "%.1f", ride.averageSpeedKmh))
                            RideMetric(title: "max", value: String(format: "%.1f", ride.maximumSpeedKmh))
                            RideMetric(title: "Zeit", value: formatDuration(ride.elapsedSeconds))
                            RideMetric(title: "Höhe", value: String(format: "%.0f m", ride.elevation))
                            RideMetric(title: "↗ ↘", value: String(format: "%.0f · %.0f", ride.ascent, ride.descent))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.16)))
                    .padding(10)
                }

                HStack(spacing: 10) {
                    Button {
                        if ride.active { ride.stop() } else { ride.start() }
                    } label: {
                        Label(
                            ride.active ? "Fahrt beenden" : "Aufzeichnung starten",
                            systemImage: ride.active ? "stop.fill" : "play.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ride.active ? .red : .orange)

                    Button {
                        showingCameraSync = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.title2.weight(.bold))
                            .frame(width: 56, height: 56)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .disabled(!ride.active && ride.points == 0)
                    .accessibilityLabel("DJI Action 5 Pro synchronisieren")
                }

                if let url = ride.exportURL {
                    ShareLink(item: url) {
                        Label("Aufgezeichnete GPX teilen", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                    .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("STRECKEN")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(routeMessage)
                                .font(.subheadline)
                        }
                        Spacer()
                        Button("GPX importieren") { importing = true }
                    }
                }
                .padding()
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color.black)
        .sheet(isPresented: $showingCameraSync) {
            CameraSyncView(ride: ride)
        }
        .onAppear { ride.refreshLocation() }
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
                Text("Nah, Fahrt, Voraus und Übersicht sind handschuhtaugliche Presets. Im Vorausblick steht das Fahrrad unten mittig, damit mehr Route vor dir sichtbar bleibt.")
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
