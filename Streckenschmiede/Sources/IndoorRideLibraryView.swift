import SwiftUI
import CoreLocation

struct IndoorRideLibraryView: View {
    @ObservedObject var ride: RideTracker
    @State private var pendingDeletion: RideArchiveEntry?

    var body: some View {
        Group {
            if ride.rideHistory.isEmpty {
                ContentUnavailableView(
                    "Noch keine gefahrene Strecke",
                    systemImage: "map",
                    description: Text("Aufgezeichnete Tagesfahrten erscheinen hier mit Kartenlinie und Daten.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(ride.rideHistory) { entry in
                            IndoorRideCard(
                                ride: ride,
                                entry: entry,
                                requestDeletion: { pendingDeletion = entry }
                            )
                        }
                    }
                    .padding(14)
                }
                .background(Color.black)
            }
        }
        .navigationTitle("Gefahrene Strecken")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { ride.refreshRideHistory(includeCurrentDay: true) }
        .safeAreaInset(edge: .bottom) {
            if ride.status.contains("konnte nicht") || ride.status.contains("erst nach") {
                Text(ride.status)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .confirmationDialog(
            "Fahrt und GPX löschen?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { entry in
            Button("Fahrt endgültig löschen", role: .destructive) {
                ride.deleteHistoryEntry(entry)
                pendingDeletion = nil
            }
            Button("Abbrechen", role: .cancel) { pendingDeletion = nil }
        } message: { entry in
            Text("Der Historieneintrag vom \(entry.startedAt.formatted(date: .long, time: .omitted)) und seine lokale GPX-Datei werden gelöscht.")
        }
    }
}

private struct IndoorRideCard: View {
    @ObservedObject var ride: RideTracker
    let entry: RideArchiveEntry
    let requestDeletion: () -> Void
    @State private var previewCoordinates: [CLLocationCoordinate2D] = []
    @State private var previewError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if previewCoordinates.count >= 2 {
                RouteMap(
                    coordinates: previewCoordinates,
                    height: 164,
                    isInteractive: false
                )
            } else if let previewError {
                ContentUnavailableView(
                    "Karte nicht verfügbar",
                    systemImage: "map",
                    description: Text(previewError)
                )
                .frame(height: 164)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white.opacity(0.06))
                    ProgressView("Strecke wird geladen")
                }
                .frame(height: 164)
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.startedAt, format: .dateTime.weekday(.wide).day().month(.wide).year())
                        .font(.headline)
                    Text("Tagesfahrt · \(entry.pointCount) GPS-Punkte")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let url = ride.historyGPXURL(for: entry) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .accessibilityLabel("GPX teilen")
                }
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                metric(String(format: "%.1f km", entry.distanceMeters / 1_000), "Distanz")
                metric(formatIndoorDuration(entry.ridingSeconds), "Fahrt")
                metric(formatIndoorDuration(entry.pausedSeconds), "Pause")
                metric(String(format: "%.1f km/h", entry.averageSpeedKmh), "Ø Tempo")
                metric(String(format: "%.1f km/h", entry.maximumSpeedKmh), "Maximum")
                metric(String(format: "↑%.0f · ↓%.0f m", entry.ascentMeters, entry.descentMeters), "Höhe")
            }

            Button(role: .destructive, action: requestDeletion) {
                Label("Fahrt und GPX löschen", systemImage: "trash")
                    .frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.12)))
        .task(id: entry.id) { await loadPreview() }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func loadPreview() async {
        guard let url = ride.historyGPXURL(for: entry) else {
            previewError = "GPX-Datei fehlt"
            return
        }
        do {
            let coordinates = try await Task.detached(priority: .utility) {
                try GPXParser.load(url)
            }.value
            previewCoordinates = downsample(coordinates, maximumCount: 2_000)
            previewError = nil
        } catch {
            previewCoordinates = []
            previewError = error.localizedDescription
        }
    }

    private func downsample(
        _ coordinates: [CLLocationCoordinate2D],
        maximumCount: Int
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count > maximumCount else { return coordinates }
        let strideLength = Int(ceil(Double(coordinates.count) / Double(maximumCount)))
        var result = Swift.stride(from: 0, to: coordinates.count, by: strideLength)
            .map { coordinates[$0] }
        if let last = coordinates.last,
           (result.last?.latitude != last.latitude || result.last?.longitude != last.longitude) {
            result.append(last)
        }
        return result
    }
}

private func formatIndoorDuration(_ seconds: Int) -> String {
    let hours = seconds / 3_600
    let minutes = (seconds % 3_600) / 60
    return hours > 0 ? String(format: "%d:%02d h", hours, minutes) : "\(minutes) min"
}
