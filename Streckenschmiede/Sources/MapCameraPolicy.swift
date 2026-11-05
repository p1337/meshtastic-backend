import Foundation

/// Keeps the rider visibly inside the lower map area while preserving useful
/// route look-ahead. The screen anchor is calculated from the actual map-view
/// height, so 2D/3D projection and zoom no longer decide whether the marker can
/// collide with the bottom controls.
enum MapCameraPolicy {
    static let minimumZoomMeters = 250.0
    static let maximumZoomMeters = 10_000.0
    static let preferredRiderScreenFraction = 2.0 / 3.0
    static let minimumRiderControlGap = 24.0

    static func lookAheadDistance(zoomMeters: Double, is3D: Bool) -> Double {
        let safeZoom = min(max(zoomMeters, minimumZoomMeters), maximumZoomMeters)
        let safeFraction = 0.22
        return safeZoom * safeFraction
    }

    static func pitchDegrees(is3DEnabled: Bool) -> Double {
        is3DEnabled ? 55 : 0
    }

    static func riderScreenY(
        viewHeight: Double,
        controlHitSize: Double,
        controlsBottomPadding: Double,
        markerDiameter: Double,
        additionalBottomReservedHeight: Double = 0
    ) -> Double {
        let safeHeight = max(0, viewHeight)
        let safeControlSize = max(0, controlHitSize)
        let safeBottomPadding = max(0, controlsBottomPadding)
        let safeMarkerDiameter = max(0, markerDiameter)
        let safeAdditionalReserve = max(0, additionalBottomReservedHeight)
        let markerRadius = safeMarkerDiameter / 2
        let preferredY = safeHeight * preferredRiderScreenFraction
        let controlsTop = safeHeight
            - safeBottomPadding
            - safeControlSize
            - safeAdditionalReserve
        let maximumSafeY = controlsTop - minimumRiderControlGap - markerRadius
        return max(markerRadius, min(preferredY, maximumSafeY))
    }
}
