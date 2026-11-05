import Foundation

struct RoutePoint: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
}

struct RouteManeuver: Codable, Equatable, Sendable {
    let instruction: String
    let distanceAlongRouteMeters: Double
}

struct RideRoutePlan: Codable, Equatable, Sendable {
    let destinationName: String
    let providerName: String
    let summary: String
    let distanceMeters: Double
    let expectedTravelTime: TimeInterval
    let points: [RoutePoint]
    let maneuvers: [RouteManeuver]
}

struct NavigationProgress: Equatable, Sendable {
    let distanceAlongRouteMeters: Double
    let remainingDistanceMeters: Double
    let remainingTravelTime: TimeInterval?
    let distanceFromRouteMeters: Double
    let nextManeuver: RouteManeuver?
    let distanceToNextManeuverMeters: Double?
}

enum NavigationProgressEngine {
    private static let earthRadiusMeters = 6_371_000.0

    static func progress(
        position: RoutePoint,
        plan: RideRoutePlan
    ) -> NavigationProgress? {
        guard plan.points.count >= 2,
              let match = closestMatch(to: position, route: plan.points) else {
            return nil
        }
        let geometryLength = routeLengthMeters(plan.points)
        guard geometryLength > 0 else { return nil }
        let reportedLength = plan.distanceMeters > 0 ? plan.distanceMeters : geometryLength
        let completedFraction = min(1, max(0, match.alongMeters / geometryLength))
        let remaining = reportedLength * (1 - completedFraction)
        let next = plan.maneuvers
            .sorted { $0.distanceAlongRouteMeters < $1.distanceAlongRouteMeters }
            .first { $0.distanceAlongRouteMeters >= match.alongMeters - 10 }
        let nextDistance = next.map {
            max(0, $0.distanceAlongRouteMeters - match.alongMeters)
        }
        let remainingTime: TimeInterval?
        if plan.expectedTravelTime > 0 {
            remainingTime = plan.expectedTravelTime * (1 - completedFraction)
        } else {
            remainingTime = nil
        }
        return NavigationProgress(
            distanceAlongRouteMeters: match.alongMeters,
            remainingDistanceMeters: remaining,
            remainingTravelTime: remainingTime,
            distanceFromRouteMeters: match.crossTrackMeters,
            nextManeuver: next,
            distanceToNextManeuverMeters: nextDistance
        )
    }

    static func distanceAlongRoute(
        to position: RoutePoint,
        route: [RoutePoint]
    ) -> Double? {
        closestMatch(to: position, route: route)?.alongMeters
    }

    static func routeLengthMeters(_ route: [RoutePoint]) -> Double {
        guard route.count >= 2 else { return 0 }
        return zip(route, route.dropFirst()).reduce(0) {
            $0 + distanceMeters(from: $1.0, to: $1.1)
        }
    }

    private static func closestMatch(
        to position: RoutePoint,
        route: [RoutePoint]
    ) -> (alongMeters: Double, crossTrackMeters: Double)? {
        guard route.count >= 2 else { return nil }
        var cumulative = 0.0
        var best: (alongMeters: Double, crossTrackMeters: Double)?
        for index in 0..<(route.count - 1) {
            let start = route[index]
            let end = route[index + 1]
            let segmentLength = distanceMeters(from: start, to: end)
            guard segmentLength > 0 else { continue }
            let startVector = localVector(from: position, to: start)
            let endVector = localVector(from: position, to: end)
            let dx = endVector.x - startVector.x
            let dy = endVector.y - startVector.y
            let squaredLength = dx * dx + dy * dy
            guard squaredLength > 0 else { continue }
            let projection = min(1, max(0,
                -(startVector.x * dx + startVector.y * dy) / squaredLength
            ))
            let closestX = startVector.x + projection * dx
            let closestY = startVector.y + projection * dy
            let crossTrack = hypot(closestX, closestY)
            let along = cumulative + projection * segmentLength
            if best == nil || crossTrack < best!.crossTrackMeters {
                best = (along, crossTrack)
            }
            cumulative += segmentLength
        }
        return best
    }

    private static func localVector(
        from origin: RoutePoint,
        to point: RoutePoint
    ) -> (x: Double, y: Double) {
        let originLatitude = origin.latitude * .pi / 180
        let pointLatitude = point.latitude * .pi / 180
        let deltaLatitude = pointLatitude - originLatitude
        let deltaLongitude = (point.longitude - origin.longitude) * .pi / 180
        let meanLatitude = (originLatitude + pointLatitude) / 2
        return (
            deltaLongitude * cos(meanLatitude) * earthRadiusMeters,
            deltaLatitude * earthRadiusMeters
        )
    }

    private static func distanceMeters(from start: RoutePoint, to end: RoutePoint) -> Double {
        let latitude1 = start.latitude * .pi / 180
        let latitude2 = end.latitude * .pi / 180
        let latitudeDelta = (end.latitude - start.latitude) * .pi / 180
        let longitudeDelta = (end.longitude - start.longitude) * .pi / 180
        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(latitude1) * cos(latitude2)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return earthRadiusMeters * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
