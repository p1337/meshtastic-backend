import CoreImage
import CoreImage.CIFilterBuiltins
import CoreLocation
import CryptoKit
import Foundation
import SwiftUI
import UIKit

enum CameraSyncEvent: String, Codable, CaseIterable, Identifiable {
    case start
    case checkpoint
    case end

    var id: String { rawValue }

    var title: String {
        switch self {
        case .start: return "Start"
        case .checkpoint: return "Checkpoint"
        case .end: return "Ende"
        }
    }
}

struct CameraSyncPayload: Codable, Equatable {
    let version: Int
    let rideID: String
    let event: CameraSyncEvent
    let sequence: Int
    let utc: String
    let rideElapsedMilliseconds: Int64
    let latitudeE7: Int?
    let longitudeE7: Int?
    let horizontalAccuracyCentimeters: Int?
    let payloadChecksum: String

    static func make(
        rideID: UUID,
        event: CameraSyncEvent,
        sequence: Int,
        date: Date,
        rideElapsedMilliseconds: Int64,
        coordinate: CLLocationCoordinate2D?,
        horizontalAccuracy: Double?,
        includeGPS: Bool
    ) -> CameraSyncPayload {
        let utc = cameraSyncDateFormatter.string(from: date)
        let latitudeE7 = includeGPS ? coordinate.map { Int(($0.latitude * 10_000_000).rounded()) } : nil
        let longitudeE7 = includeGPS ? coordinate.map { Int(($0.longitude * 10_000_000).rounded()) } : nil
        let accuracy = includeGPS ? horizontalAccuracy.flatMap { $0 >= 0 ? Int(($0 * 100).rounded()) : nil } : nil
        let rideIDText = rideID.uuidString.lowercased()
        let latitudeText = latitudeE7.map { String($0) } ?? ""
        let longitudeText = longitudeE7.map { String($0) } ?? ""
        let accuracyText = accuracy.map { String($0) } ?? ""
        let fields: [String] = [
            "1", rideIDText, event.rawValue, String(sequence), utc,
            String(rideElapsedMilliseconds), latitudeText, longitudeText, accuracyText
        ]
        let canonical = fields.joined(separator: "|")
        let digest = SHA256.hash(data: Data(canonical.utf8))
        let checksum = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return CameraSyncPayload(
            version: 1,
            rideID: rideIDText,
            event: event,
            sequence: sequence,
            utc: utc,
            rideElapsedMilliseconds: rideElapsedMilliseconds,
            latitudeE7: latitudeE7,
            longitudeE7: longitudeE7,
            horizontalAccuracyCentimeters: accuracy,
            payloadChecksum: checksum
        )
    }

    func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

private let cameraSyncDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private enum CameraQRCodeGenerator {
    static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func image(for data: Data) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "H"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct CameraSyncView: View {
    @ObservedObject var ride: RideTracker
    @Environment(\.dismiss) private var dismiss
    @AppStorage("cameraSyncIncludeGPS") private var includeGPS = false
    @State private var event: CameraSyncEvent = .start
    @State private var sequence = 0
    @State private var payload: CameraSyncPayload?
    @State private var qrImage: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("DJI OSMO ACTION 5 PRO")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)

                    Picker("Sync-Punkt", selection: $event) {
                        ForEach(CameraSyncEvent.allCases) { event in
                            Text(event.title).tag(event)
                        }
                    }
                    .pickerStyle(.segmented)

                    if let qrImage {
                        Image(uiImage: qrImage)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .padding(14)
                            .background(.white, in: RoundedRectangle(cornerRadius: 20))
                            .accessibilityLabel("QR-Code zur Synchronisierung der Action 5 Pro")
                    } else {
                        ContentUnavailableView("QR-Code nicht verfügbar", systemImage: "qrcode")
                            .frame(minHeight: 280)
                    }

                    if let payload {
                        VStack(spacing: 6) {
                            Text(event.title.uppercased())
                                .font(.title2.weight(.black))
                                .foregroundStyle(.orange)
                            Text(payload.utc)
                                .font(.subheadline.monospacedDigit())
                            Text("Fahrtzeit \(formatCameraDuration(payload.rideElapsedMilliseconds))")
                                .font(.headline.monospacedDigit())
                            Text("Fahrt \(payload.rideID.prefix(8)) · Code \(payload.sequence)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Diesen Bildschirm 4–5 Sekunden mit der Action 5 Pro filmen. Für genaue Driftkorrektur einmal am Anfang und einmal am Ende aufnehmen.")
                        .font(.callout)
                        .multilineTextAlignment(.center)

                    Toggle("Aktuelle GPS-Position in den QR-Code schreiben", isOn: $includeGPS)
                        .tint(.orange)

                    if includeGPS {
                        Label(
                            "Der gefilmte QR-Code enthält den genauen Standort und die Aufnahmezeit. Beim Teilen des Videos kann diese Information ausgelesen werden.",
                            systemImage: "exclamationmark.shield"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    } else {
                        Label(
                            "Datenschutzmodus: Der Code verknüpft über Fahrt-ID und Zeit mit der lokalen GPS-Spur, enthält aber keine Koordinaten.",
                            systemImage: "shield.checkered"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Button {
                        sequence += 1
                        refreshCode()
                    } label: {
                        Label("Neuen Sync-Code erzeugen", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .padding()
            }
            .background(.black)
            .preferredColorScheme(.dark)
            .navigationTitle("Kamera-Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
            .onAppear {
                if ride.active, ride.elapsedSeconds < 30 {
                    event = .start
                } else if ride.active {
                    event = .checkpoint
                } else {
                    event = .end
                }
                refreshCode()
            }
            .onChange(of: event) { _, _ in refreshCode() }
            .onChange(of: includeGPS) { _, _ in refreshCode() }
        }
    }

    private func refreshCode() {
        let newPayload = CameraSyncPayload.make(
            rideID: ride.rideID,
            event: event,
            sequence: sequence,
            date: Date(),
            rideElapsedMilliseconds: ride.elapsedMilliseconds,
            coordinate: ride.currentCoordinate,
            horizontalAccuracy: ride.currentHorizontalAccuracy,
            includeGPS: includeGPS
        )
        payload = newPayload
        if let data = try? newPayload.encodedData() {
            qrImage = CameraQRCodeGenerator.image(for: data)
        } else {
            qrImage = nil
        }
    }
}

private func formatCameraDuration(_ milliseconds: Int64) -> String {
    let totalSeconds = max(0, milliseconds / 1_000)
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let seconds = totalSeconds % 60
    return String(format: "%02d:%02d:%02d", Int(hours), Int(minutes), Int(seconds))
}

