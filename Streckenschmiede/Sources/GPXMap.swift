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
    @AppStorage("rideMap3DEnabled") private var rideMap3DEnabled = true
    @AppStorage("rideMapStickToRoute") private var rideMapStickToRoute = false
    @AppStorage("rideMapLayer") private var rideMapLayerRaw = RideMapLayer.appleStandard.rawValue
    @State private var rasterCameraTarget: RasterCameraTarget?
    @State private var cameraRevision = 0
    @State private var followsPosition = true
    private let mapControlHitSize: CGFloat = 84
    private let mapControlVisualSize: CGFloat = 58

    private let mapControlsBottomPadding: CGFloat = 34
    private let attributionBottomPadding: CGFloat = 116

    private var effectiveZoomMeters: Double {
        guard rideMapAutoZoom else { return rideMapZoomMeters }
        if speedKmh >= 30 { return max(rideMapZoomMeters, 2_500) }
        if speedKmh >= 15 { return max(rideMapZoomMeters, 1_500) }
        return rideMapZoomMeters
    }

    var body: some View {
        mapSurface
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            if selectedMapLayer.usesOSMData {
                Link(destination: URL(string: selectedMapLayer.attributionURL)!) {
                    Text(selectedMapLayer.attribution)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.78), in: Capsule())
                }
                .padding(.trailing, 12)
                .padding(.bottom, attributionBottomPadding)
            }
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 0) {
                mapButton(systemImage: "minus", accessibilityLabel: "Karte verkleinern") {
                    rideMapZoomMeters = min(10_000, rideMapZoomMeters * 1.5)
                    followsPosition = true
                    recenter()
                }
                Spacer(minLength: 0)

                mapButton(
                    systemImage: "scope",
                    accessibilityLabel: "Fahrrad auf der Karte zentrieren",
                    foreground: followsPosition ? .orange : .white
                ) {
                    followsPosition = true
                    recenter()
                }
                Spacer(minLength: 0)

                mapButton(systemImage: "plus", accessibilityLabel: "Karte vergrößern") {
                    rideMapZoomMeters = max(250, rideMapZoomMeters / 1.5)
                    followsPosition = true
                    recenter()
                }
            }
            .padding(.horizontal, 0)
            .padding(.bottom, mapControlsBottomPadding)
        }
        .overlay(alignment: .topLeading) {
            if !followsPosition {
                Text("Karte verschoben")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.78), in: Capsule())
                    .padding(.top, 210)
                    .padding(.leading, 12)
            }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in
            followsPosition = false
        })
        .simultaneousGesture(MagnifyGesture().onChanged { _ in
            followsPosition = false
        })
        .onAppear {
            if selectedMapLayer == .openCycleMap, RideMapLayer.openCycleMapKey == nil {
                rideMapLayerRaw = RideMapLayer.appleStandard.rawValue
            }
            recenter()
        }
        .onChange(of: rideMapLayerRaw) { _, _ in recenter() }
        .onChange(of: rideMapZoomMeters) { _, _ in
            if followsPosition { recenter() }
        }
        .onChange(of: rideMapAutoZoom) { _, _ in
            if followsPosition { recenter() }
        }
        .onChange(of: rideMapHeadingUp) { _, _ in
            if followsPosition { recenter() }
        }
        .onChange(of: rideMap3DEnabled) { _, _ in
            if followsPosition { recenter() }
        }
        .onChange(of: rideMapStickToRoute) { _, _ in
            if followsPosition { recenter() }
        }
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
    private var mapSurface: some View {
        switch selectedMapLayer {
        case .openStreetMap:
            RasterRideMap(
                providerID: selectedMapLayer.rawValue,
                tileTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                nativeStyle: .standard,
                coordinates: coordinates,
                plannedRoute: plannedRoute,
                currentCoordinate: displayedCoordinate,
                courseDegrees: courseDegrees,
                cameraTarget: rasterCameraTarget,
                cameraRevision: cameraRevision,
                followsPosition: $followsPosition
            )
        case .cycleOSM:
            RasterRideMap(
                providerID: selectedMapLayer.rawValue,
                tileTemplate: "https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png",
                nativeStyle: .standard,
                coordinates: coordinates,
                plannedRoute: plannedRoute,
                currentCoordinate: displayedCoordinate,
                courseDegrees: courseDegrees,
                cameraTarget: rasterCameraTarget,
                cameraRevision: cameraRevision,
                followsPosition: $followsPosition
            )
        case .openCycleMap:
            if let openCycleMapKey = RideMapLayer.openCycleMapKey {
                RasterRideMap(
                    providerID: selectedMapLayer.rawValue,
                    tileTemplate: "https://tile.thunderforest.com/cycle/{z}/{x}/{y}.png?apikey=\(openCycleMapKey)",
                    nativeStyle: .standard,
                    coordinates: coordinates,
                    plannedRoute: plannedRoute,
                    currentCoordinate: displayedCoordinate,
                    courseDegrees: courseDegrees,
                    cameraTarget: rasterCameraTarget,
                    cameraRevision: cameraRevision,
                    followsPosition: $followsPosition
                )
            } else {
                appleMap
            }
        default:
            appleMap
        }
    }

    private var appleMap: some View {
        RasterRideMap(
            providerID: selectedMapLayer.rawValue,
            tileTemplate: nil,
            nativeStyle: nativeMapStyle,
            coordinates: coordinates,
            plannedRoute: plannedRoute,
            currentCoordinate: displayedCoordinate,
            courseDegrees: courseDegrees,
            cameraTarget: rasterCameraTarget,
            cameraRevision: cameraRevision,
            followsPosition: $followsPosition
        )
    }

    private var nativeMapStyle: NativeRideMapStyle {
        switch selectedMapLayer {
        case .appleSatellite: .imagery
        case .appleHybrid: .hybrid
        default: .standard
        }
    }

    private var selectedMapLayer: RideMapLayer {
        RideMapLayer(rawValue: rideMapLayerRaw) ?? .appleStandard
    }

    @ViewBuilder
    private func mapButton(
        systemImage: String,
        accessibilityLabel: String,
        foreground: Color = .orange,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.82))
                    .frame(width: mapControlVisualSize, height: mapControlVisualSize)
                    .overlay(Circle().stroke(.white.opacity(0.42), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.55), radius: 6, y: 2)
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .bold))
            }
            .frame(
                width: mapControlHitSize,
                height: mapControlHitSize,
                alignment: .bottom
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
        .accessibilityLabel(accessibilityLabel)
    }

    private func recenter() {
        guard let currentCoordinate = displayedCoordinate else { return }
        let travelBearing = travelBearingDegrees
        let heading = rideMapHeadingUp ? travelBearing ?? 0 : 0
        let screenTopBearing = rideMapHeadingUp ? travelBearing ?? 0 : 0
        let center = coordinate(
            from: currentCoordinate,
            bearingDegrees: screenTopBearing,
            distanceMeters: MapCameraPolicy.lookAheadDistance(
                zoomMeters: effectiveZoomMeters,
                is3D: rideMap3DEnabled
            )
        )
        let pitch = CGFloat(MapCameraPolicy.pitchDegrees(is3DEnabled: rideMap3DEnabled))
        rasterCameraTarget = RasterCameraTarget(
            center: center,
            riderCoordinate: currentCoordinate,
            distance: effectiveZoomMeters,
            heading: heading,
            pitch: pitch
        )
        cameraRevision &+= 1
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

    private var displayedCoordinate: CLLocationCoordinate2D? {
        guard let currentCoordinate else { return nil }
        guard rideMapStickToRoute, plannedRoute.count > 1 else {
            return currentCoordinate
        }
        return snappedCoordinate(
            currentCoordinate,
            to: plannedRoute,
            maximumDistanceMeters: 50
        ) ?? currentCoordinate
    }

    private func snappedCoordinate(
        _ position: CLLocationCoordinate2D,
        to route: [CLLocationCoordinate2D],
        maximumDistanceMeters: Double
    ) -> CLLocationCoordinate2D? {
        let earthRadius = 6_378_137.0
        let referenceLatitude = position.latitude * .pi / 180
        func local(_ coordinate: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            (
                (coordinate.longitude - position.longitude) * .pi / 180
                    * earthRadius * cos(referenceLatitude),
                (coordinate.latitude - position.latitude) * .pi / 180 * earthRadius
            )
        }

        var nearest: (coordinate: CLLocationCoordinate2D, distance: Double)?
        for index in 0..<(route.count - 1) {
            let start = route[index]
            let end = route[index + 1]
            let a = local(start)
            let b = local(end)
            let dx = b.x - a.x
            let dy = b.y - a.y
            let squaredLength = dx * dx + dy * dy
            guard squaredLength > 0 else { continue }
            let fraction = max(0, min(1, -(a.x * dx + a.y * dy) / squaredLength))
            let x = a.x + fraction * dx
            let y = a.y + fraction * dy
            let distance = hypot(x, y)
            if nearest == nil || distance < nearest!.distance {
                nearest = (
                    CLLocationCoordinate2D(
                        latitude: start.latitude + fraction * (end.latitude - start.latitude),
                        longitude: start.longitude + fraction * (end.longitude - start.longitude)
                    ),
                    distance
                )
            }
        }
        guard let nearest, nearest.distance <= maximumDistanceMeters else { return nil }
        return nearest.coordinate
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

enum RideMapLayer: String, CaseIterable, Identifiable {
    case appleStandard
    case appleSatellite
    case appleHybrid
    case openStreetMap
    case cycleOSM
    case openCycleMap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleStandard: "Apple Karte"
        case .appleSatellite: "Apple Satellit"
        case .appleHybrid: "Apple Hybrid"
        case .openStreetMap: "OpenStreetMap"
        case .cycleOSM: "OSM Fahrrad · CyclOSM"
        case .openCycleMap: "OpenCycleMap"
        }
    }

    var systemImage: String {
        switch self {
        case .appleStandard: "map"
        case .appleSatellite: "globe.americas.fill"
        case .appleHybrid: "square.2.layers.3d"
        case .openStreetMap: "signpost.right.and.left"
        case .cycleOSM, .openCycleMap: "bicycle"
        }
    }

    var usesOSMData: Bool {
        self == .openStreetMap || self == .cycleOSM || self == .openCycleMap
    }

    var attribution: String {
        switch self {
        case .openStreetMap: "© OpenStreetMap contributors"
        case .cycleOSM: "CyclOSM · © OpenStreetMap contributors"
        case .openCycleMap: "Maps © Thunderforest · Data © OpenStreetMap contributors"
        default: ""
        }
    }

    var attributionURL: String {
        switch self {
        case .cycleOSM: "https://www.cyclosm.org/"
        case .openCycleMap: "https://www.thunderforest.com/terms/"
        default: "https://www.openstreetmap.org/copyright"
        }
    }

    static var openCycleMapKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "THUNDERFOREST_API_KEY") as? String,
              key.count == 32,
              key.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return key
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
