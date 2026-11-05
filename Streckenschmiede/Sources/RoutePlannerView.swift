import CoreLocation
import MapKit
import SwiftUI

struct RoutePlannerView: View {
    let origin: CLLocationCoordinate2D?
    let onSelectRoute: (RideRoutePlan) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var routes: [MKRoute] = []
    @State private var selectedRouteIndex = 0
    @State private var destination: MKMapItem?
    @State private var isSearching = false
    @State private var isRouting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Ziel") {
                    HStack(spacing: 10) {
                        TextField("Adresse oder Ort suchen", text: $query)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.search)
                            .onSubmit { startSearch() }
                        Button { startSearch() } label: {
                            if isSearching {
                                ProgressView()
                            } else {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(searchText.isEmpty || isSearching)
                        .accessibilityLabel("Ziel suchen")
                    }

                    if origin == nil {
                        Label("GPS-Startposition wird gesucht", systemImage: "location.slash")
                            .foregroundStyle(.orange)
                    } else {
                        Label("Start: aktuelle GPS-Position", systemImage: "location.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                if !searchResults.isEmpty {
                    Section("Suchergebnisse") {
                        ForEach(Array(searchResults.enumerated()), id: \.offset) { _, item in
                            Button {
                                calculateRoutes(to: item)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name ?? "Ziel")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    if let address = item.placemark.title, address != item.name {
                                        Text(address)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .disabled(origin == nil || isRouting)
                        }
                    }
                }

                if isRouting {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Apple-Fahrradrouten werden berechnet …")
                        }
                    }
                }

                if !routes.isEmpty, let destination {
                    Section("Routen auf der Karte auswählen") {
                        RoutePlannerPreview(
                            origin: origin,
                            destination: destination.placemark.coordinate,
                            routes: routes.indices.map { index in
                                RoutePreviewLine(
                                    id: index,
                                    coordinates: coordinates(of: routes[index])
                                )
                            },
                            selectedIndex: $selectedRouteIndex
                        )
                        if routes.indices.contains(selectedRouteIndex) {
                            let route = routes[selectedRouteIndex]
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(routeTitle(route, index: selectedRouteIndex))
                                        .font(.headline)
                                    Text("\(formatDistance(route.distance)) · \(formatDuration(route.expectedTravelTime))")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Übernehmen") {
                                    use(route: route, index: selectedRouteIndex)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                            }
                        }
                    }
                }

                if !routes.isEmpty {
                    Section("Routendetails") {
                        ForEach(routes.indices, id: \.self) { index in
                            let route = routes[index]
                            Button {
                                selectedRouteIndex = index
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("\(index + 1)")
                                            .font(.caption.weight(.black))
                                            .frame(width: 26, height: 26)
                                            .background(
                                                selectedRouteIndex == index ? Color.orange : Color.secondary.opacity(0.25),
                                                in: Circle()
                                            )
                                            .foregroundStyle(selectedRouteIndex == index ? Color.black : Color.primary)
                                        Text(routeTitle(route, index: index))
                                            .font(.headline)
                                        Spacer()
                                        Image(systemName: selectedRouteIndex == index
                                              ? "checkmark.circle.fill"
                                              : "circle")
                                            .foregroundStyle(selectedRouteIndex == index ? Color.orange : Color.secondary)
                                    }
                                    Text("\(formatDistance(route.distance)) · \(formatDuration(route.expectedTravelTime))")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    if !route.advisoryNotices.isEmpty {
                                        Text(route.advisoryNotices.joined(separator: " · "))
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                            .lineLimit(3)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }

                Section {
                    Text("Apple MapKit liefert ein Fahrradprofil. Radweg-, Untergrund-, Gravel- und Straßenanteil-Regler folgen über den getrennten OSM/Valhalla-Provider.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ziel planen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var searchText: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startSearch() {
        guard !searchText.isEmpty else { return }
        Task { await search() }
    }

    @MainActor
    private func search() async {
        isSearching = true
        errorMessage = nil
        searchResults = []
        routes = []
        destination = nil
        defer { isSearching = false }
        do {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = searchText
            request.resultTypes = [.address, .pointOfInterest]
            if let origin {
                request.region = MKCoordinateRegion(
                    center: origin,
                    latitudinalMeters: 100_000,
                    longitudinalMeters: 100_000
                )
            }
            let response = try await MKLocalSearch(request: request).start()
            searchResults = Array(response.mapItems.prefix(8))
            if searchResults.isEmpty { errorMessage = "Kein passendes Ziel gefunden" }
        } catch {
            errorMessage = "Zielsuche fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func calculateRoutes(to item: MKMapItem) {
        Task { await calculateRoutesAsync(to: item) }
    }

    @MainActor
    private func calculateRoutesAsync(to item: MKMapItem) async {
        guard let origin else {
            errorMessage = "GPS-Startposition fehlt"
            return
        }
        isRouting = true
        errorMessage = nil
        routes = []
        selectedRouteIndex = 0
        destination = item
        defer { isRouting = false }
        do {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
            request.destination = item
            // Apple added the Swift `.cycling` spelling to the Xcode 26 SDK,
            // while the option itself is available from iOS 14. Keep the
            // release pipeline on its proven Xcode 16 signing image and use
            // the documented option bit so the same request works there.
            request.transportType = MKDirectionsTransportType(rawValue: 1 << 3)
            request.requestsAlternateRoutes = true
            request.departureDate = Date()
            let response = try await MKDirections(request: request).calculate()
            routes = response.routes
            selectedRouteIndex = 0
            if routes.isEmpty {
                errorMessage = "Apple hat für dieses Ziel keine Fahrradroute geliefert"
            }
        } catch {
            errorMessage = "Fahrradroute fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func use(route: MKRoute, index: Int) {
        let routeCoordinates = coordinates(of: route)
        guard routeCoordinates.count > 1 else {
            errorMessage = "Die Route enthält keine nutzbare Geometrie"
            return
        }
        let destinationName = destination?.name ?? "Ziel"
        let summary = "\(destinationName) · Apple Fahrrad · \(formatDistance(route.distance)) · \(formatDuration(route.expectedTravelTime))"
        let points = routeCoordinates.map {
            RoutePoint(latitude: $0.latitude, longitude: $0.longitude)
        }
        var fallbackDistance = 0.0
        let maneuvers = route.steps.compactMap { step -> RouteManeuver? in
            defer { fallbackDistance += step.distance }
            let instruction = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !instruction.isEmpty else { return nil }
            let stepStart = coordinates(of: step.polyline).first.map {
                RoutePoint(latitude: $0.latitude, longitude: $0.longitude)
            }
            let distanceAlong = stepStart.flatMap {
                NavigationProgressEngine.distanceAlongRoute(to: $0, route: points)
            } ?? fallbackDistance
            return RouteManeuver(
                instruction: instruction,
                distanceAlongRouteMeters: distanceAlong
            )
        }
        onSelectRoute(RideRoutePlan(
            destinationName: destinationName,
            providerName: "Apple Fahrrad",
            summary: summary,
            distanceMeters: route.distance,
            expectedTravelTime: route.expectedTravelTime,
            points: points,
            maneuvers: maneuvers
        ))
        dismiss()
    }

    private func coordinates(of route: MKRoute) -> [CLLocationCoordinate2D] {
        coordinates(of: route.polyline)
    }

    private func coordinates(of polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        guard polyline.pointCount > 0 else { return [] }
        var values = Array(
            repeating: CLLocationCoordinate2D(),
            count: polyline.pointCount
        )
        polyline.getCoordinates(
            &values,
            range: NSRange(location: 0, length: polyline.pointCount)
        )
        return values
    }

    private func routeTitle(_ route: MKRoute, index: Int) -> String {
        let name = route.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Route \(index + 1)" : name
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        meters >= 1_000
            ? String(format: "%.1f km", meters / 1_000)
            : String(format: "%.0f m", meters)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes >= 60 { return "\(minutes / 60) Std \(minutes % 60) Min" }
        return "\(minutes) Min"
    }
}

private struct RoutePreviewLine: Identifiable {
    let id: Int
    let coordinates: [CLLocationCoordinate2D]
}

private struct RoutePlannerPreview: View {
    let origin: CLLocationCoordinate2D?
    let destination: CLLocationCoordinate2D
    let routes: [RoutePreviewLine]
    @Binding var selectedIndex: Int

    private var initialPosition: MapCameraPosition {
        let coordinates = routes.flatMap(\.coordinates)
        guard coordinates.count > 1 else {
            return .region(MKCoordinateRegion(
                center: destination,
                latitudinalMeters: 2_000,
                longitudinalMeters: 2_000
            ))
        }
        let line = MKPolyline(coordinates: coordinates, count: coordinates.count)
        return .rect(line.boundingMapRect)
    }

    var body: some View {
        Map(initialPosition: initialPosition, interactionModes: [.pan, .zoom]) {
            ForEach(routes.filter { $0.id != selectedIndex }) { route in
                if route.coordinates.count > 1 {
                    MapPolyline(coordinates: route.coordinates)
                        .stroke(
                            .white.opacity(0.58),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                        )
                }
            }
            ForEach(routes.filter { $0.id == selectedIndex }) { route in
                if route.coordinates.count > 1 {
                    MapPolyline(coordinates: route.coordinates)
                        .stroke(
                            .orange,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
                        )
                }
            }
            ForEach(routes) { route in
                if let coordinate = route.coordinates.dropFirst(route.coordinates.count / 2).first {
                    Annotation("Route \(route.id + 1)", coordinate: coordinate) {
                        Button {
                            selectedIndex = route.id
                        } label: {
                            Text("\(route.id + 1)")
                                .font(.headline.weight(.black))
                                .frame(width: 42, height: 42)
                                .foregroundStyle(selectedIndex == route.id ? Color.black : Color.white)
                                .background(
                                    selectedIndex == route.id ? Color.orange : Color.black.opacity(0.82),
                                    in: Circle()
                                )
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                                .shadow(color: .black.opacity(0.6), radius: 5, y: 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Route \(route.id + 1) auswählen")
                    }
                }
            }
            if let origin {
                Marker("Start", systemImage: "location.fill", coordinate: origin)
                    .tint(.orange)
            }
            Marker("Ziel", systemImage: "flag.checkered", coordinate: destination)
                .tint(.green)
        }
        .mapStyle(.standard(elevation: .realistic))
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityLabel("Karte mit allen berechneten Fahrradrouten")
    }
}
