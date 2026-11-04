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
    func start() {
        guard !active else { return }
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
        location.startUpdatingLocation()
        status = "Aufzeichnung läuft"
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard pendingStartAfterAuthorization else { return }
        if manager.authorizationStatus == .notDetermined { return }
        pendingStartAfterAuthorization = false
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            beginRecording()
        } else {
            status = "Standortzugriff verweigert"
        }
    }
    func stop() {
        active = false
        location.stopUpdatingLocation()
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
        guard active else { return }
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
            if p.verticalAccuracy >= 0, p.verticalAccuracy < 30 { elevation = p.altitude }
        }
        points = track.count
        trackCoordinates = track.map(\.coordinate)
        updateAverageSpeed()
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
    @StateObject private var ride = RideTracker()
    @StateObject private var ble = TrainerScanner()
    @State private var importing = false
    @State private var route: [CLLocationCoordinate2D] = []
    @State private var routeMessage = "Noch keine GPX-Strecke importiert"
    var body: some View {
        TabView {
            NavigationStack {
                RideDashboard(
                    ride: ride,
                    importing: $importing,
                    route: route,
                    routeMessage: routeMessage
                )
                .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml, .xml, .data]) { result in
                    do {
                        let url = try result.get()
                        route = try GPXParser.load(url)
                        routeMessage = "\(route.count) Streckenpunkte importiert"
                    } catch {
                        routeMessage = "Import fehlgeschlagen: \(error.localizedDescription)"
                    }
                }
                .navigationTitle("Aufzeichnung")
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
            .tabItem { Label("Aufzeichnung",systemImage:"record.circle") }
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
        }
        .tint(Color(red:1,green:0.57,blue:0))
        .preferredColorScheme(.dark)
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
            VStack(spacing: 16) {
                HStack {
                    Circle()
                        .fill(ride.active ? Color.green : Color.orange)
                        .frame(width: 9, height: 9)
                    Text(ride.status)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("GPS · \(ride.points)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)

                VStack(spacing: 2) {
                    Text("GESCHWINDIGKEIT")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(String(format: "%.1f", ride.speedKmh))
                            .font(.system(size: 68, weight: .black, design: .rounded))
                            .monospacedDigit()
                        Text("km/h")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22))

                LazyVGrid(columns: columns, spacing: 10) {
                    RideMetric(title: "Distanz", value: String(format: "%.2f", ride.distance / 1_000), unit: "km")
                    RideMetric(title: "Ø Tempo", value: String(format: "%.1f", ride.averageSpeedKmh), unit: "km/h")
                    RideMetric(title: "Maximum", value: String(format: "%.1f", ride.maximumSpeedKmh), unit: "km/h")
                    RideMetric(title: "Zeit", value: formatDuration(ride.elapsedSeconds), unit: "")
                    RideMetric(title: "Höhe", value: String(format: "%.0f", ride.elevation), unit: "m")
                    RideMetric(title: "Auf · Ab", value: String(format: "%.0f · %.0f", ride.ascent, ride.descent), unit: "m")
                }

                LiveRideMap(
                    coordinates: ride.trackCoordinates,
                    currentCoordinate: ride.currentCoordinate,
                    speedKmh: ride.speedKmh
                )

                Button {
                    showingCameraSync = true
                } label: {
                    Label("DJI Action 5 Pro synchronisieren", systemImage: "qrcode.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(!ride.active && ride.points == 0)

                Button {
                    if ride.active { ride.stop() } else { ride.start() }
                } label: {
                    Label(
                        ride.active ? "Fahrt beenden" : "Aufzeichnung starten",
                        systemImage: ride.active ? "stop.fill" : "play.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(ride.active ? .red : .orange)

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
                    if !route.isEmpty { RouteMap(coordinates: route) }
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
    }
}

private struct RideMetric: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text(unit.isEmpty ? " " : unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15))
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

    var body: some View {
        Form {
            Section("Fahrtkarte") {
                Toggle("Automatischer Zoom", isOn: $rideMapAutoZoom)
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
                Text("Die Einstellung wird dauerhaft für die Live-Fahrtkarte gespeichert. Auf der Karte kann zusätzlich direkt hinein- und herausgezoomt werden.")
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
