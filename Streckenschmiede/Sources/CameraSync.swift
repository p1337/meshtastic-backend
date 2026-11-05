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
    @AppStorage("cameraSyncBoostBrightness") private var boostBrightness = true
    @State private var event: CameraSyncEvent = .start
    @State private var sequence = 0
    @State private var payload: CameraSyncPayload?
    @State private var qrImage: UIImage?
    @State private var showingFullscreenCode = false

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
                            .frame(maxHeight: 320)
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

                    Toggle("Für den Vollbild-Code maximale Helligkeit", isOn: $boostBrightness)
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
                        if qrImage != nil {
                            showingFullscreenCode = true
                        }
                    } label: {
                        Label("Vollbild-Code 5 Sekunden filmen", systemImage: "viewfinder")
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
            .fullScreenCover(isPresented: $showingFullscreenCode) {
                if let payload, let qrImage {
                    CameraSyncFullscreenView(
                        payload: payload,
                        qrImage: qrImage,
                        boostBrightness: boostBrightness
                    )
                } else {
                    ContentUnavailableView("QR-Code nicht verfügbar", systemImage: "qrcode")
                        .preferredColorScheme(.dark)
                }
            }
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

private struct CameraSyncFullscreenView: View {
    let payload: CameraSyncPayload
    let qrImage: UIImage
    let boostBrightness: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var elapsedSeconds = 0
    @State private var runID = UUID()
    @State private var originalBrightness: CGFloat?
    @State private var originalIdleTimerDisabled: Bool?

    private var stage: CameraSyncCaptureStage {
        CameraSyncCaptureTimeline.stage(at: elapsedSeconds)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                Color.black

                VStack(spacing: 14) {
                    Spacer(minLength: 24)

                    switch stage {
                    case let .preparing(secondsRemaining):
                        Image(systemName: "viewfinder")
                            .font(.system(size: 72, weight: .ultraLight))
                            .foregroundStyle(.orange)
                        Text("KAMERA AUSRICHTEN")
                            .font(.headline.weight(.black))
                            .foregroundStyle(.orange)
                        Text("\(secondsRemaining)")
                            .font(.system(size: 120, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())

                    case let .exposing(secondsRemaining):
                        qrPanel(maximumSize: min(geometry.size.width - 24, geometry.size.height * 0.66))
                        Text("\(secondsRemaining) s RUHIG HALTEN")
                            .font(.headline.weight(.black))
                            .foregroundStyle(.orange)
                            .monospacedDigit()
                        ProgressView(
                            value: Double(elapsedSeconds - CameraSyncCaptureTimeline.preparationSeconds),
                            total: Double(CameraSyncCaptureTimeline.minimumExposureSeconds)
                        )
                        .tint(.orange)
                        .padding(.horizontal, 32)

                    case .complete:
                        qrPanel(maximumSize: min(geometry.size.width - 24, geometry.size.height * 0.66))
                        Label("Mindestens 5 Sekunden erfasst", systemImage: "checkmark.circle.fill")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.green)
                        Button {
                            runID = UUID()
                        } label: {
                            Label("Noch einmal filmen", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }

                    VStack(spacing: 4) {
                        Text(payload.event.title.uppercased())
                            .font(.headline.weight(.black))
                            .foregroundStyle(.orange)
                        Text("Fahrt \(payload.rideID.prefix(8)) · Code \(payload.sequence)")
                            .font(.caption.monospaced())
                        Text("\(payload.utc) · \(formatCameraDuration(payload.rideElapsedMilliseconds))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.bold))
                        .frame(width: 52, height: 52)
                        .background(.black.opacity(0.72), in: Circle())
                }
                .tint(.white)
                .padding(12)
                .accessibilityLabel("Vollbild-Code schließen")
            }
        }
        .ignoresSafeArea()
        .background(.black)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task(id: runID) {
            elapsedSeconds = 0
            for _ in 0..<CameraSyncCaptureTimeline.totalSeconds {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
                elapsedSeconds += 1
            }
        }
        .onAppear(perform: applyDisplayOverrides)
        .onDisappear(perform: restoreDisplayOverrides)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                applyDisplayOverrides()
                if elapsedSeconds > 0 {
                    runID = UUID()
                }
            } else {
                restoreDisplayOverrides()
            }
        }
    }

    private func qrPanel(maximumSize: CGFloat) -> some View {
        Image(uiImage: qrImage)
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .frame(width: maximumSize, height: maximumSize)
            .padding(12)
            .background(.white)
            .accessibilityLabel("QR-Code \(payload.event.title) für die Kamera")
    }

    private func applyDisplayOverrides() {
        if originalIdleTimerDisabled == nil {
            originalIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        }
        UIApplication.shared.isIdleTimerDisabled = true
        if boostBrightness {
            if originalBrightness == nil {
                originalBrightness = UIScreen.main.brightness
            }
            UIScreen.main.brightness = 1
        }
    }

    private func restoreDisplayOverrides() {
        if let originalIdleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = originalIdleTimerDisabled
            self.originalIdleTimerDisabled = nil
        }
        if let originalBrightness {
            UIScreen.main.brightness = originalBrightness
            self.originalBrightness = nil
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

