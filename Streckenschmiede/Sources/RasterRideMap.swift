import Foundation
import MapKit
import SwiftUI

struct RasterCameraTarget: Equatable {
    let center: CLLocationCoordinate2D
    let riderCoordinate: CLLocationCoordinate2D
    let distance: CLLocationDistance
    let heading: CLLocationDirection
    let pitch: CGFloat
    let bottomOverlayHeight: CGFloat

    static func == (left: RasterCameraTarget, right: RasterCameraTarget) -> Bool {
        left.center.latitude == right.center.latitude
            && left.center.longitude == right.center.longitude
            && left.riderCoordinate.latitude == right.riderCoordinate.latitude
            && left.riderCoordinate.longitude == right.riderCoordinate.longitude
            && left.distance == right.distance
            && left.heading == right.heading
            && left.pitch == right.pitch
            && left.bottomOverlayHeight == right.bottomOverlayHeight
    }
}

enum NativeRideMapStyle {
    case standard
    case imagery
    case hybrid
}

struct RasterRideMap: UIViewRepresentable {
    let providerID: String
    let tileTemplate: String?
    let nativeStyle: NativeRideMapStyle
    let coordinates: [CLLocationCoordinate2D]
    let plannedRoute: [CLLocationCoordinate2D]
    let currentCoordinate: CLLocationCoordinate2D?
    let courseDegrees: Double?
    let cameraTarget: RasterCameraTarget?
    let cameraRevision: Int
    let showsTraffic: Bool
    @Binding var followsPosition: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsCompass = false
        mapView.showsScale = true
        mapView.showsTraffic = showsTraffic
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true
        let compass = MKCompassButton(mapView: mapView)
        compass.compassVisibility = .visible
        compass.translatesAutoresizingMaskIntoConstraints = false
        mapView.addSubview(compass)
        NSLayoutConstraint.activate([
            compass.leadingAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            compass.topAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.topAnchor, constant: -8)
        ])
        context.coordinator.installMapStyle(on: mapView)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        mapView.showsTraffic = showsTraffic
        context.coordinator.installMapStyle(on: mapView)
        context.coordinator.updatePolylines(on: mapView)
        context.coordinator.updatePosition(on: mapView)
        context.coordinator.applyCameraIfNeeded(on: mapView)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: RasterRideMap
        private var installedProviderID: String?
        private var tileOverlay: PolicyTileOverlay?
        private var routeOverlay: MKPolyline?
        private var trackOverlay: MKPolyline?
        private var positionAnnotation: RidePositionAnnotation?
        private var lastRouteSignature: Int?
        private var lastTrackCount = -1
        private var lastCameraRevision = -1

        init(parent: RasterRideMap) {
            self.parent = parent
        }

        func installMapStyle(on mapView: MKMapView) {
            guard installedProviderID != parent.providerID else { return }
            if let tileOverlay { mapView.removeOverlay(tileOverlay) }
            tileOverlay = nil
            switch parent.nativeStyle {
            case .standard:
                mapView.preferredConfiguration = MKStandardMapConfiguration(
                    elevationStyle: .realistic
                )
            case .imagery:
                mapView.preferredConfiguration = MKImageryMapConfiguration(
                    elevationStyle: .realistic
                )
            case .hybrid:
                mapView.preferredConfiguration = MKHybridMapConfiguration(
                    elevationStyle: .realistic
                )
            }
            if let tileTemplate = parent.tileTemplate {
                let overlay = PolicyTileOverlay(urlTemplate: tileTemplate)
                overlay.canReplaceMapContent = true
                overlay.minimumZ = 0
                overlay.maximumZ = 19
                mapView.addOverlay(overlay, level: .aboveLabels)
                tileOverlay = overlay
            }
            installedProviderID = parent.providerID
        }

        func updatePolylines(on mapView: MKMapView) {
            let routeSignature = coordinateSignature(parent.plannedRoute)
            if lastRouteSignature != routeSignature {
                if let routeOverlay { mapView.removeOverlay(routeOverlay) }
                routeOverlay = parent.plannedRoute.count > 1
                    ? MKPolyline(coordinates: parent.plannedRoute, count: parent.plannedRoute.count)
                    : nil
                if let routeOverlay { mapView.addOverlay(routeOverlay, level: .aboveLabels) }
                lastRouteSignature = routeSignature
            }
            if lastTrackCount != parent.coordinates.count {
                if let trackOverlay { mapView.removeOverlay(trackOverlay) }
                trackOverlay = parent.coordinates.count > 1
                    ? MKPolyline(coordinates: parent.coordinates, count: parent.coordinates.count)
                    : nil
                if let trackOverlay { mapView.addOverlay(trackOverlay, level: .aboveLabels) }
                lastTrackCount = parent.coordinates.count
            }
        }

        private func coordinateSignature(_ coordinates: [CLLocationCoordinate2D]) -> Int {
            var hasher = Hasher()
            hasher.combine(coordinates.count)
            for coordinate in coordinates {
                hasher.combine(Int64((coordinate.latitude * 1_000_000).rounded()))
                hasher.combine(Int64((coordinate.longitude * 1_000_000).rounded()))
            }
            return hasher.finalize()
        }

        func updatePosition(on mapView: MKMapView) {
            guard let coordinate = parent.currentCoordinate else {
                if let positionAnnotation { mapView.removeAnnotation(positionAnnotation) }
                positionAnnotation = nil
                return
            }
            if let positionAnnotation {
                positionAnnotation.coordinate = coordinate
                positionAnnotation.courseDegrees = parent.courseDegrees
            } else {
                let annotation = RidePositionAnnotation(
                    coordinate: coordinate,
                    courseDegrees: parent.courseDegrees
                )
                positionAnnotation = annotation
                mapView.addAnnotation(annotation)
            }
            updatePositionRotation(on: mapView)
        }

        func applyCameraIfNeeded(on mapView: MKMapView) {
            guard lastCameraRevision != parent.cameraRevision,
                  let target = parent.cameraTarget,
                  mapView.bounds.width > 0,
                  mapView.bounds.height > 0 else { return }
            let camera = MKMapCamera(
                lookingAtCenter: target.center,
                fromDistance: target.distance,
                pitch: target.pitch,
                heading: target.heading
            )
            mapView.setCamera(camera, animated: false)
            anchorRider(
                target.riderCoordinate,
                bottomOverlayHeight: target.bottomOverlayHeight,
                on: mapView
            )
            lastCameraRevision = parent.cameraRevision
        }

        private func anchorRider(
            _ coordinate: CLLocationCoordinate2D,
            bottomOverlayHeight: CGFloat,
            on mapView: MKMapView
        ) {
            let desiredPoint = CGPoint(
                x: mapView.bounds.midX,
                y: CGFloat(MapCameraPolicy.riderScreenY(
                    viewHeight: Double(mapView.bounds.height),
                    controlHitSize: 84,
                    controlsBottomPadding: 34,
                    markerDiameter: 42,
                    additionalBottomReservedHeight: Double(bottomOverlayHeight)
                ))
            )
            for _ in 0..<2 {
                let actualPoint = mapView.convert(coordinate, toPointTo: mapView)
                guard actualPoint.x.isFinite, actualPoint.y.isFinite else { return }
                let adjustedCenterPoint = CGPoint(
                    x: mapView.bounds.midX + actualPoint.x - desiredPoint.x,
                    y: mapView.bounds.midY + actualPoint.y - desiredPoint.y
                )
                let adjustedCenter = mapView.convert(
                    adjustedCenterPoint,
                    toCoordinateFrom: mapView
                )
                mapView.setCenter(adjustedCenter, animated: false)
            }
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            let userGesture = mapView.subviews
                .compactMap(\.gestureRecognizers)
                .flatMap { $0 }
                .contains { $0.state == .began || $0.state == .changed }
            if userGesture { parent.followsPosition = false }
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            updatePositionRotation(on: mapView)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tile)
            }
            guard let line = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.lineCap = .round
            renderer.lineJoin = .round
            if line === routeOverlay {
                renderer.strokeColor = UIColor(red: 0.82, green: 1.0, blue: 0.1, alpha: 1)
                renderer.lineWidth = 8
            } else {
                renderer.strokeColor = .systemOrange
                renderer.lineWidth = 6
            }
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is RidePositionAnnotation else { return nil }
            let identifier = "ride-position"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.frame = CGRect(x: 0, y: 0, width: 42, height: 42)
            view.backgroundColor = UIColor.black.withAlphaComponent(0.86)
            view.layer.cornerRadius = 21
            view.layer.borderWidth = 2
            view.layer.borderColor = UIColor.white.cgColor
            view.layer.shadowColor = UIColor.black.cgColor
            view.layer.shadowOpacity = 0.65
            view.layer.shadowRadius = 5
            view.layer.shadowOffset = CGSize(width: 0, height: 2)

            let arrow: UIImageView
            if let existing = view.viewWithTag(77) as? UIImageView {
                arrow = existing
            } else {
                arrow = UIImageView(image: UIImage(systemName: "location.north.fill"))
                arrow.tag = 77
                arrow.tintColor = .systemOrange
                arrow.contentMode = .scaleAspectFit
                arrow.frame = CGRect(x: 10, y: 9, width: 22, height: 24)
                view.addSubview(arrow)
            }
            updatePositionRotation(on: mapView, view: view)
            return view
        }

        private func updatePositionRotation(on mapView: MKMapView, view: MKAnnotationView? = nil) {
            guard let annotation = positionAnnotation,
                  let annotationView = view ?? mapView.view(for: annotation),
                  let arrow = annotationView.viewWithTag(77) else { return }
            let course = annotation.courseDegrees ?? mapView.camera.heading
            let rotation = (course - mapView.camera.heading) * .pi / 180
            arrow.transform = CGAffineTransform(rotationAngle: rotation)
        }
    }
}

private final class RidePositionAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var courseDegrees: Double?

    init(coordinate: CLLocationCoordinate2D, courseDegrees: Double?) {
        self.coordinate = coordinate
        self.courseDegrees = courseDegrees
    }
}

private final class PolicyTileOverlay: MKTileOverlay {
    private let template: String
    private let session: URLSession

    init(urlTemplate: String) {
        template = urlTemplate
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.urlCache = URLCache(
            memoryCapacity: 32 * 1_024 * 1_024,
            diskCapacity: 256 * 1_024 * 1_024,
            diskPath: "streckenschmiede-map-tiles"
        )
        session = URLSession(configuration: configuration)
        super.init(urlTemplate: nil)
    }

    override func loadTile(
        at path: MKTileOverlayPath,
        result: @escaping (Data?, (any Error)?) -> Void
    ) {
        guard let url = TileURLTemplate.url(
            template: template,
            x: path.x,
            y: path.y,
            z: path.z
        ) else {
            result(nil, URLError(.badURL))
            return
        }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        request.setValue(
            "Streckenschmiede/\(version) (+https://p1337.github.io/meshtastic-backend/)",
            forHTTPHeaderField: "User-Agent"
        )
        session.dataTask(with: request) { data, response, error in
            if let error {
                result(nil, error)
                return
            }
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let data else {
                result(nil, URLError(.badServerResponse))
                return
            }
            result(data, nil)
        }.resume()
    }
}
