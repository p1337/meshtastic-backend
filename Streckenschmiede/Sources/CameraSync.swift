import CoreImage
import CoreImage.CIFilterBuiltins
import CoreLocation
import Foundation
import SwiftUI
import UIKit

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
            latitude: ride.currentCoordinate?.latitude,
            longitude: ride.currentCoordinate?.longitude,
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

