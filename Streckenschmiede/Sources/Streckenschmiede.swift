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
    @Published var exportURL: URL?
    @Published var status = "Bereit"
    private let location = CLLocationManager()
    private var track: [CLLocation] = []
    private var pendingStartAfterAuthorization = false
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
        track = []; distance = 0; points = 0; exportURL = nil
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
            }
            track.append(p)
        }
        points = track.count
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
                Form {
                    Section("Meine Fahrt") {
                        Text(ride.status)
                        Text(String(format:"%.2f km · %d GPS-Punkte",ride.distance/1000,ride.points))
                        Button(ride.active ? "Fahrt beenden" : "Aufzeichnung starten") {
                            if ride.active { ride.stop() } else { ride.start() }
                        }
                        if let url = ride.exportURL { ShareLink("GPX teilen",item:url) }
                    }
                    Section("Strecken") {
                        Button("GPX-Datei importieren") { importing = true }
                        Text(routeMessage).font(.caption)
                        if !route.isEmpty { RouteMap(coordinates: route) }
                    }
                }
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
struct SettingsView: View {
    var body: some View {
        Form {
            Section("Streckenschmiede") {
                Text("Einstellungen")
                Text("Version: Entwicklungsstand")
            }
        }
        .navigationTitle("Einstellungen")
    }
}
