import Foundation
import SwiftUI
#if canImport(FoundationXML)
import FoundationXML
#endif
import CoreLocation
import MapKit
import UniformTypeIdentifiers

extension UTType {
    static let gpx = UTType(importedAs: "com.topografix.gpx", conformingTo: .xml)
}

struct LiveRideMap: View {
    let coordinates: [CLLocationCoordinate2D]
    let plannedRoute: [CLLocationCoordinate2D]
    let currentCoordinate: CLLocationCoordinate2D?
    let speedKmh: Double
    let courseDegrees: Double?

    @AppStorage("rideMapZoomMeters") private var rideMapZoomMeters = 1_500.0
    @AppStorage("rideMapAutoZoom") private var rideMapAutoZoom = true
    @AppStorage("rideMapHeadingUp") private var rideMapHeadingUp = true
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
            if plannedRoute.count > 1 {
                MapPolyline(coordinates: plannedRoute)
                    .stroke(
                        Color(red: 0.82, green: 1.0, blue: 0.1),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
                    )
            }
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates)
                    .stroke(.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            if let currentCoordinate {
                Annotation("Aktuelle Position", coordinate: currentCoordinate) {
                    ZStack {
                        Circle()
                            .fill(.black.opacity(0.86))
                            .frame(width: 38, height: 38)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(.orange)
                            .rotationEffect(.degrees(markerRotationDegrees))
                    }
                    .shadow(color: .black.opacity(0.65), radius: 5, y: 2)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .trailing) {
            VStack(spacing: 10) {
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
            .padding(.trailing, 12)
            .offset(y: -24)
        }
        .overlay(alignment: .topLeading) {
            if !followsPosition {
                Text("Karte verschoben")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.78), in: Capsule())
                    .padding(.top, 126)
                    .padding(.leading, 12)
            }
        }
        .overlay(alignment: .bottom) {
            Button {
                followsPosition = true
                recenter()
            } label: {
                Image(systemName: "scope")
                    .font(.title2.weight(.black))
                    .frame(width: 60, height: 60)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(followsPosition ? .orange : .white)
            .background(.black.opacity(0.84), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.65), lineWidth: 1))
            .shadow(color: .black.opacity(0.55), radius: 8, y: 3)
            .padding(.bottom, 154)
            .accessibilityLabel("Fahrrad auf der Karte zentrieren")
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
        .onChange(of: courseDegrees) { _, _ in
            if followsPosition { recenter() }
        }
        .onChange(of: plannedRoute.count) { _, _ in
            if followsPosition { recenter() }
        }
        .accessibilityLabel("Live-Fahrtkarte mit aktueller Position und gefahrenem Track")
    }

    @ViewBuilder
    private func mapButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.bold))
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.orange)
        .background(.black.opacity(0.8), in: Circle())
        .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
        .accessibilityLabel(systemImage)
    }

    private func recenter() {
        guard let currentCoordinate else { return }
        let travelBearing = travelBearingDegrees
        let heading = rideMapHeadingUp ? travelBearing ?? 0 : 0
        let center = travelBearing.map {
            coordinate(
                from: currentCoordinate,
                bearingDegrees: $0,
                distanceMeters: effectiveZoomMeters / 3
            )
        } ?? currentCoordinate
        cameraPosition = .camera(MapCamera(
            centerCoordinate: center,
            distance: effectiveZoomMeters,
            heading: heading,
            pitch: rideMapHeadingUp && travelBearing != nil ? 40 : 0
        ))
    }

    private var markerRotationDegrees: Double {
        guard let travelBearing = travelBearingDegrees else { return 0 }
        let mapHeading = rideMapHeadingUp ? travelBearing : 0
        let difference = (travelBearing - mapHeading).truncatingRemainder(dividingBy: 360)
        return difference < 0 ? difference + 360 : difference
    }

    private var travelBearingDegrees: Double? {
        if let courseDegrees, courseDegrees >= 0 { return courseDegrees }
        if coordinates.count >= 2,
           let previous = coordinates.dropLast().last,
           let current = coordinates.last {
            return bearing(from: previous, to: current)
        }
        guard let currentCoordinate, plannedRoute.count >= 2 else { return nil }
        let nearestIndex = plannedRoute.indices.min { left, right in
            squaredDistance(plannedRoute[left], currentCoordinate)
                < squaredDistance(plannedRoute[right], currentCoordinate)
        }
        guard let nearestIndex, nearestIndex + 1 < plannedRoute.count else { return nil }
        for nextIndex in (nearestIndex + 1)..<plannedRoute.count {
            let candidate = plannedRoute[nextIndex]
            if CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude)
                .distance(from: CLLocation(latitude: candidate.latitude, longitude: candidate.longitude)) >= 10 {
                return bearing(from: currentCoordinate, to: candidate)
            }
        }
        return nil
    }

    private func squaredDistance(
        _ left: CLLocationCoordinate2D,
        _ right: CLLocationCoordinate2D
    ) -> Double {
        let latitude = left.latitude - right.latitude
        let longitude = left.longitude - right.longitude
        return latitude * latitude + longitude * longitude
    }

    private func bearing(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) -> Double {
        let originLatitude = origin.latitude * .pi / 180
        let destinationLatitude = destination.latitude * .pi / 180
        let deltaLongitude = (destination.longitude - origin.longitude) * .pi / 180
        let y = sin(deltaLongitude) * cos(destinationLatitude)
        let x = cos(originLatitude) * sin(destinationLatitude)
            - sin(originLatitude) * cos(destinationLatitude) * cos(deltaLongitude)
        let degrees = atan2(y, x) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    private func coordinate(
        from origin: CLLocationCoordinate2D,
        bearingDegrees: Double,
        distanceMeters: Double
    ) -> CLLocationCoordinate2D {
        let earthRadius = 6_378_137.0
        let angularDistance = distanceMeters / earthRadius
        let bearing = bearingDegrees * .pi / 180
        let latitude = origin.latitude * .pi / 180
        let longitude = origin.longitude * .pi / 180
        let resultLatitude = asin(
            sin(latitude) * cos(angularDistance)
                + cos(latitude) * sin(angularDistance) * cos(bearing)
        )
        let resultLongitude = longitude + atan2(
            sin(bearing) * sin(angularDistance) * cos(latitude),
            cos(angularDistance) - sin(latitude) * sin(resultLatitude)
        )
        return CLLocationCoordinate2D(
            latitude: resultLatitude * 180 / .pi,
            longitude: resultLongitude * 180 / .pi
        )
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
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile != false else {
            throw NSError(domain: "Streckenschmiede", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Die Auswahl ist keine GPX-Datei"])
        }
        if let fileSize = values.fileSize, fileSize > 50 * 1_024 * 1_024 {
            throw NSError(domain: "Streckenschmiede", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "GPX-Datei ist größer als 50 MB"])
        }
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
