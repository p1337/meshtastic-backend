import Foundation
import SwiftUI
#if canImport(FoundationXML)
import FoundationXML
#endif
import CoreLocation
import MapKit

struct LiveRideMap: View {
    let coordinates: [CLLocationCoordinate2D]
    let currentCoordinate: CLLocationCoordinate2D?
    let speedKmh: Double

    @AppStorage("rideMapZoomMeters") private var rideMapZoomMeters = 1_500.0
    @AppStorage("rideMapAutoZoom") private var rideMapAutoZoom = true
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var followsPosition = true

    private var effectiveZoomMeters: Double {
        guard rideMapAutoZoom else { return rideMapZoomMeters }
        if speedKmh >= 30 { return max(rideMapZoomMeters, 2_500) }
        if speedKmh >= 15 { return max(rideMapZoomMeters, 1_500) }
        return rideMapZoomMeters
    }

    var body: some View {
        Map(position: $cameraPosition, interactionModes: .all) {
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates)
                    .stroke(.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            if let currentCoordinate {
                Annotation("Aktuelle Position", coordinate: currentCoordinate) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 17, height: 17)
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                        .shadow(radius: 4)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .frame(height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 8) {
                mapButton(systemImage: followsPosition ? "location.fill" : "location") {
                    followsPosition = true
                    recenter()
                }
                mapButton(systemImage: "plus.magnifyingglass") {
                    rideMapZoomMeters = max(250, rideMapZoomMeters / 1.5)
                    followsPosition = true
                    recenter()
                }
                mapButton(systemImage: "minus.magnifyingglass") {
                    rideMapZoomMeters = min(10_000, rideMapZoomMeters * 1.5)
                    followsPosition = true
                    recenter()
                }
            }
            .padding(12)
        }
        .overlay(alignment: .bottomLeading) {
            Text(followsPosition ? "Position folgen" : "Karte frei")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.black.opacity(0.72), in: Capsule())
                .padding(12)
        }
        .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in
            followsPosition = false
        })
        .simultaneousGesture(MagnifyGesture().onChanged { _ in
            followsPosition = false
        })
        .onAppear { recenter() }
        .onChange(of: currentCoordinate?.latitude) { _, _ in
            if followsPosition { recenter() }
        }
        .onChange(of: currentCoordinate?.longitude) { _, _ in
            if followsPosition { recenter() }
        }
        .onChange(of: speedKmh) { _, _ in
            if followsPosition, rideMapAutoZoom { recenter() }
        }
        .accessibilityLabel("Live-Fahrtkarte mit aktueller Position und gefahrenem Track")
    }

    @ViewBuilder
    private func mapButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline)
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.orange)
        .background(.black.opacity(0.8), in: Circle())
        .accessibilityLabel(systemImage)
    }

    private func recenter() {
        guard let currentCoordinate else { return }
        cameraPosition = .region(MKCoordinateRegion(
            center: currentCoordinate,
            latitudinalMeters: effectiveZoomMeters,
            longitudinalMeters: effectiveZoomMeters
        ))
    }
}

final class GPXParser: NSObject, XMLParserDelegate {
    private(set) var coordinates: [CLLocationCoordinate2D] = []
    private var lat: Double?
    private var lon: Double?
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "trkpt" || elementName == "rtept" {
            lat = attributeDict["lat"].flatMap(Double.init)
            lon = attributeDict["lon"].flatMap(Double.init)
            if let lat, let lon, (-90...90).contains(lat), (-180...180).contains(lon) {
                coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
        }
    }
    static func load(_ url: URL) throws -> [CLLocationCoordinate2D] {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let delegate = GPXParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), !delegate.coordinates.isEmpty else {
            throw NSError(domain: "Streckenschmiede", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "GPX enthält keine gültigen Streckenpunkte"])
        }
        return delegate.coordinates
    }
}

struct RouteMap: View {
    let coordinates: [CLLocationCoordinate2D]

    private var initialCamera: MapCameraPosition {
        guard let first = coordinates.first else { return .automatic }
        if coordinates.count == 1 {
            return .region(MKCoordinateRegion(
                center: first,
                latitudinalMeters: 1_000,
                longitudinalMeters: 1_000
            ))
        }
        // Fit the imported route, not the user's current GPS position.
        let line = MKPolyline(coordinates: coordinates, count: coordinates.count)
        return .rect(line.boundingMapRect)
    }

    var body: some View {
        Map(initialPosition: initialCamera) {
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates)
                    .stroke(.orange, lineWidth: 5)
            }
            if let start = coordinates.first {
                Annotation("Start", coordinate: start) {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(.orange)
                        .padding(7)
                        .background(.black.opacity(0.85), in: Circle())
                }
            }
            if coordinates.count > 1, let finish = coordinates.last {
                Annotation("Ziel", coordinate: finish) {
                    Image(systemName: "flag.checkered")
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(.black.opacity(0.85), in: Circle())
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityLabel("Streckenkarte mit Start und Ziel")
    }
}
