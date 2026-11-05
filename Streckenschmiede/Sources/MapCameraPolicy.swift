import Foundation

/// Keeps the rider visibly inside the lower map area while preserving useful
/// route look-ahead. `MKMapCamera.distance` is not the visible map height, so
/// large fractions can push the annotation beyond the screen, especially with
/// a pitched camera.
enum MapCameraPolicy {
    static let minimumZoomMeters = 250.0
    static let maximumZoomMeters = 10_000.0

    static func lookAheadDistance(zoomMeters: Double, is3D: Bool) -> Double {
        let safeZoom = min(max(zoomMeters, minimumZoomMeters), maximumZoomMeters)
        let safeFraction = is3D ? 0.12 : 0.16
        return safeZoom * safeFraction
    }
}
