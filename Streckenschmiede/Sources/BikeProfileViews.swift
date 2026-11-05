import SwiftUI

@MainActor
final class BikeProfileManager: ObservableObject {
    @Published private(set) var library: BikeProfileLibrary
    @Published private(set) var lastError: String?

    private let storeURL: URL

    init(storeURL: URL? = nil) {
        self.storeURL = storeURL ?? BikeProfileStore.defaultURL()
        do {
            library = try BikeProfileStore.load(from: self.storeURL)
        } catch {
            library = BikeProfileLibrary()
            lastError = "Fahrradprofile konnten nicht geladen werden: \(error.localizedDescription)"
        }
    }

    var activeProfile: BikeProfile? { library.activeProfile }

    @discardableResult
    func upsert(_ profile: BikeProfile, makeActive: Bool = false) -> Bool {
        var candidate = library
        do {
            try candidate.upsert(profile, makeActive: makeActive)
            try BikeProfileStore.save(candidate, to: storeURL)
            library = candidate
            lastError = nil
            return true
        } catch {
            lastError = "Fahrradprofil konnte nicht gespeichert werden: \(error.localizedDescription)"
            return false
        }
    }

    func activate(_ id: UUID) {
        var candidate = library
        do {
            try candidate.activate(id)
            try BikeProfileStore.save(candidate, to: storeURL)
            library = candidate
            lastError = nil
        } catch {
            lastError = "Fahrrad konnte nicht aktiviert werden: \(error.localizedDescription)"
        }
    }

    func delete(_ id: UUID) {
        var candidate = library
        candidate.delete(id)
        do {
            try BikeProfileStore.save(candidate, to: storeURL)
            library = candidate
            lastError = nil
        } catch {
            lastError = "Fahrradprofil konnte nicht gelöscht werden: \(error.localizedDescription)"
        }
    }
}

struct BikeProfilesView: View {
    @ObservedObject var manager: BikeProfileManager
    @State private var pendingDeletion: BikeProfile?

    var body: some View {
        List {
            if let active = manager.activeProfile {
                Section("Aktives Fahrrad") {
                    BikeProfileCard(profile: active, isActive: true)
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "Noch kein Fahrrad",
                        systemImage: "bicycle",
                        description: Text("Lege dein erstes Rad mit Typ und Abroll-Durchmesser an.")
                    )
                }
            }

            Section("Alle Fahrräder") {
                ForEach(manager.library.profiles) { profile in
                    VStack(alignment: .leading, spacing: 10) {
                        BikeProfileCard(
                            profile: profile,
                            isActive: manager.library.activeProfileID == profile.id
                        )
                        HStack(spacing: 10) {
                            if manager.library.activeProfileID != profile.id {
                                Button {
                                    manager.activate(profile.id)
                                } label: {
                                    Label("Aktiv wählen", systemImage: "checkmark.circle")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                            }
                            NavigationLink {
                                BikeProfileEditorView(manager: manager, profile: profile)
                            } label: {
                                Label("Bearbeiten", systemImage: "slider.horizontal.3")
                            }
                            .buttonStyle(.bordered)
                            Spacer(minLength: 0)
                            Button(role: .destructive) {
                                pendingDeletion = profile
                            } label: {
                                Image(systemName: "trash")
                                    .frame(width: 34, height: 34)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("\(profile.name) löschen")
                        }
                    }
                    .padding(.vertical, 5)
                }

                NavigationLink {
                    BikeProfileEditorView(manager: manager, profile: nil)
                } label: {
                    Label("Fahrrad hinzufügen", systemImage: "plus.circle.fill")
                        .foregroundStyle(.orange)
                }
            }

            if let error = manager.lastError {
                Section("Speicherstatus") {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Fahrradprofile")
        .confirmationDialog(
            "Fahrradprofil löschen?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { profile in
            Button("\(profile.name) löschen", role: .destructive) {
                manager.delete(profile.id)
                pendingDeletion = nil
            }
            Button("Abbrechen", role: .cancel) { pendingDeletion = nil }
        } message: { profile in
            Text("Das Profil \(profile.name) wird lokal gelöscht. Bereits gespeicherte Fahrten bleiben erhalten.")
        }
    }
}

private struct BikeProfileCard: View {
    let profile: BikeProfile
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            BikeSilhouetteView(kind: profile.kind)
                .frame(height: 104)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.headline)
                    Text(profile.kind.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isActive {
                    Label("Aktiv", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                }
            }
            HStack(spacing: 12) {
                Label(
                    String(format: "%.0f mm · %.1f″", profile.wheelDiameterMillimeters, profile.wheelDiameterInches),
                    systemImage: "circle.dashed"
                )
                Label(
                    String(format: "%.0f mm Umfang", profile.wheelCircumferenceMillimeters),
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BikeProfileEditorView: View {
    @ObservedObject var manager: BikeProfileManager
    let existingProfile: BikeProfile?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var kind: BikeKind
    @State private var wheelDiameterMillimeters: Double
    @State private var validationMessage: String?

    init(manager: BikeProfileManager, profile: BikeProfile?) {
        self.manager = manager
        existingProfile = profile
        let initialKind = profile?.kind ?? .gravel
        _name = State(initialValue: profile?.name ?? "")
        _kind = State(initialValue: initialKind)
        _wheelDiameterMillimeters = State(
            initialValue: profile?.wheelDiameterMillimeters
                ?? initialKind.suggestedWheelDiameterMillimeters
        )
    }

    var body: some View {
        Form {
            Section {
                BikeSilhouetteView(kind: kind)
                    .frame(height: 156)
                    .listRowInsets(EdgeInsets())
                    .accessibilityLabel("Schattenbild für \(kind.title)")
            }

            Section("Fahrrad") {
                TextField("Name, zum Beispiel Mein Gravelbike", text: $name)
                    .textInputAutocapitalization(.words)
                Picker("Fahrradtyp", selection: $kind) {
                    ForEach(BikeKind.allCases) { bikeKind in
                        Text(bikeKind.title).tag(bikeKind)
                    }
                }
                Button("Empfohlenen Durchmesser für \(kind.title) übernehmen") {
                    wheelDiameterMillimeters = kind.suggestedWheelDiameterMillimeters
                }
                .font(.caption)
            }

            Section("Radgröße") {
                HStack {
                    Text("Abroll-Durchmesser")
                    Spacer()
                    TextField(
                        "mm",
                        value: $wheelDiameterMillimeters,
                        format: .number.precision(.fractionLength(0))
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 86)
                    Text("mm")
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: $wheelDiameterMillimeters,
                    in: BikeProfile.minimumWheelDiameterMillimeters...BikeProfile.maximumWheelDiameterMillimeters,
                    step: 1
                )
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        diameterPreset("20″", 508)
                        diameterPreset("24″", 610)
                        diameterPreset("26″", 660)
                        diameterPreset("27,5″", 699)
                        diameterPreset("28″ / 700C", 700)
                        diameterPreset("29″", 737)
                    }
                }
                LabeledContent(
                    "Berechneter Radumfang",
                    value: String(format: "%.0f mm", wheelDiameterMillimeters * .pi)
                )
                LabeledContent(
                    "Durchmesser in Zoll",
                    value: String(format: "%.1f″", wheelDiameterMillimeters / 25.4)
                )
                Text("Für einen Rad-Geschwindigkeitssensor zählt der echte Abroll-Durchmesser inklusive Reifen. Nachmessen verbessert Tempo und Distanz; Streckenschmiede berechnet daraus automatisch den Umfang.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let validationMessage {
                Section {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Button(existingProfile == nil ? "Fahrrad anlegen" : "Änderungen speichern") {
                    save()
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .navigationTitle(existingProfile == nil ? "Neues Fahrrad" : "Fahrrad bearbeiten")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func diameterPreset(_ title: String, _ value: Double) -> some View {
        Button(title) { wheelDiameterMillimeters = value }
            .buttonStyle(.bordered)
            .tint(abs(wheelDiameterMillimeters - value) < 0.5 ? .orange : .secondary)
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let profile = BikeProfile(
            id: existingProfile?.id ?? UUID(),
            name: cleanName,
            kind: kind,
            wheelDiameterMillimeters: wheelDiameterMillimeters,
            createdAt: existingProfile?.createdAt ?? now,
            updatedAt: now
        )
        guard profile.isValid else {
            validationMessage = "Bitte einen Namen und einen Abroll-Durchmesser zwischen 250 und 900 mm eingeben."
            return
        }
        let shouldActivate = existingProfile == nil && manager.library.profiles.isEmpty
        if manager.upsert(profile, makeActive: shouldActivate) {
            dismiss()
        } else {
            validationMessage = manager.lastError ?? "Fahrradprofil konnte nicht gespeichert werden."
        }
    }
}

struct BikeSilhouetteView: View {
    let kind: BikeKind

    var body: some View {
        Canvas { context, size in
            drawBike(context: &context, size: size)
        }
        .background(
            LinearGradient(
                colors: [Color(red: 1, green: 0.62, blue: 0.08), .orange],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
    }

    private func drawBike(context: inout GraphicsContext, size: CGSize) {
        let ink = GraphicsContext.Shading.color(.black.opacity(0.92))
        let groundY = size.height * 0.71
        let smallWheel = [.folding, .bmx, .handcycle, .kids].contains(kind)
        let tandem = kind == .tandem
        let cargo = kind == .cargo || kind == .electricCargo
        let recumbent = kind == .recumbent || kind == .handcycle
        let rearX = size.width * (tandem ? 0.13 : 0.22)
        let frontX = size.width * (cargo || tandem ? 0.86 : 0.78)
        let wheelRadius = min(
            size.height * (smallWheel ? 0.20 : 0.255),
            (frontX - rearX) * 0.28
        )
        let wheelLine = kind == .fatBike ? max(8, size.height * 0.065) : max(4, size.height * 0.034)
        let stroke = StrokeStyle(lineWidth: max(5, size.height * 0.043), lineCap: .round, lineJoin: .round)
        let detailStroke = StrokeStyle(lineWidth: max(3, size.height * 0.026), lineCap: .round, lineJoin: .round)

        context.stroke(circle(center: CGPoint(x: rearX, y: groundY), radius: wheelRadius), with: ink,
                       style: StrokeStyle(lineWidth: wheelLine))
        context.stroke(circle(center: CGPoint(x: frontX, y: groundY), radius: wheelRadius), with: ink,
                       style: StrokeStyle(lineWidth: wheelLine))

        let crank = CGPoint(x: size.width * (tandem ? 0.48 : 0.49), y: size.height * 0.66)
        let seatTop = CGPoint(x: size.width * (recumbent ? 0.39 : 0.40), y: size.height * (recumbent ? 0.58 : 0.31))
        let headTop = CGPoint(x: size.width * (cargo ? 0.70 : 0.66), y: size.height * (recumbent ? 0.50 : 0.34))
        let headBottom = CGPoint(x: size.width * (cargo ? 0.68 : 0.64), y: size.height * 0.53)

        var frame = Path()
        frame.move(to: CGPoint(x: rearX, y: groundY))
        frame.addLine(to: crank)
        frame.addLine(to: seatTop)
        frame.addLine(to: headTop)
        frame.addLine(to: headBottom)
        frame.addLine(to: crank)
        frame.addLine(to: CGPoint(x: rearX, y: groundY))
        context.stroke(frame, with: ink, style: stroke)

        context.stroke(
            line([headTop, CGPoint(x: frontX, y: groundY)]),
            with: ink,
            style: stroke
        )
        context.stroke(
            line([
                seatTop,
                CGPoint(x: seatTop.x - size.width * 0.018, y: seatTop.y - size.height * 0.10)
            ]),
            with: ink,
            style: detailStroke
        )
        let saddleY = seatTop.y - size.height * 0.105
        context.stroke(
            line([
                CGPoint(x: seatTop.x - size.width * 0.075, y: saddleY),
                CGPoint(x: seatTop.x + size.width * 0.035, y: saddleY)
            ]),
            with: ink,
            style: StrokeStyle(lineWidth: max(5, size.height * 0.04), lineCap: .round)
        )

        drawHandlebar(context: &context, size: size, headTop: headTop, ink: ink, detailStroke: detailStroke)
        drawKindDetails(
            context: &context,
            size: size,
            rearX: rearX,
            frontX: frontX,
            groundY: groundY,
            wheelRadius: wheelRadius,
            crank: crank,
            seatTop: seatTop,
            headTop: headTop,
            ink: ink,
            detailStroke: detailStroke
        )

        context.stroke(circle(center: crank, radius: max(5, size.height * 0.045)), with: ink,
                       style: detailStroke)
    }

    private func drawHandlebar(
        context: inout GraphicsContext,
        size: CGSize,
        headTop: CGPoint,
        ink: GraphicsContext.Shading,
        detailStroke: StrokeStyle
    ) {
        let dropBarKinds: Set<BikeKind> = [
            .road, .gravel, .cyclocross, .triathlon, .trackFixed,
            .electricRoad, .electricGravel
        ]
        if dropBarKinds.contains(kind) {
            var bar = Path()
            bar.move(to: headTop)
            bar.addLine(to: CGPoint(x: headTop.x + size.width * 0.035, y: headTop.y - size.height * 0.10))
            bar.addCurve(
                to: CGPoint(x: headTop.x + size.width * 0.14, y: headTop.y - size.height * 0.025),
                control1: CGPoint(x: headTop.x + size.width * 0.11, y: headTop.y - size.height * 0.12),
                control2: CGPoint(x: headTop.x + size.width * 0.16, y: headTop.y - size.height * 0.08)
            )
            bar.addLine(to: CGPoint(x: headTop.x + size.width * 0.10, y: headTop.y + size.height * 0.025))
            context.stroke(bar, with: ink, style: detailStroke)
            if kind == .triathlon {
                context.stroke(
                    line([
                        CGPoint(x: headTop.x + size.width * 0.03, y: headTop.y - size.height * 0.10),
                        CGPoint(x: headTop.x + size.width * 0.18, y: headTop.y - size.height * 0.10)
                    ]),
                    with: ink,
                    style: detailStroke
                )
            }
        } else {
            let stemTop = CGPoint(x: headTop.x + size.width * 0.025, y: headTop.y - size.height * 0.09)
            context.stroke(line([headTop, stemTop]), with: ink, style: detailStroke)
            context.stroke(
                line([
                    CGPoint(x: stemTop.x - size.width * 0.055, y: stemTop.y),
                    CGPoint(x: stemTop.x + size.width * 0.085, y: stemTop.y)
                ]),
                with: ink,
                style: detailStroke
            )
        }
    }

    private func drawKindDetails(
        context: inout GraphicsContext,
        size: CGSize,
        rearX: CGFloat,
        frontX: CGFloat,
        groundY: CGFloat,
        wheelRadius: CGFloat,
        crank: CGPoint,
        seatTop: CGPoint,
        headTop: CGPoint,
        ink: GraphicsContext.Shading,
        detailStroke: StrokeStyle
    ) {
        if kind.isElectric {
            let battery = CGRect(
                x: crank.x - size.width * 0.035,
                y: crank.y - size.height * 0.17,
                width: size.width * 0.07,
                height: size.height * 0.17
            )
            context.fill(Path(roundedRect: battery, cornerRadius: 5), with: ink)
        }
        if [.trekking, .touring, .city, .electricCityTrekking].contains(kind) {
            let rackY = groundY - wheelRadius - size.height * 0.035
            context.stroke(
                line([
                    CGPoint(x: rearX - size.width * 0.06, y: rackY),
                    CGPoint(x: rearX + size.width * 0.14, y: rackY)
                ]),
                with: ink,
                style: detailStroke
            )
        }
        if kind == .city || kind == .electricCityTrekking {
            let basket = CGRect(
                x: headTop.x + size.width * 0.05,
                y: headTop.y - size.height * 0.035,
                width: size.width * 0.12,
                height: size.height * 0.10
            )
            context.fill(Path(basket), with: ink)
        }
        if kind == .cargo || kind == .electricCargo {
            let box = CGRect(
                x: size.width * 0.53,
                y: size.height * 0.39,
                width: size.width * 0.23,
                height: size.height * 0.18
            )
            context.fill(Path(roundedRect: box, cornerRadius: 5), with: ink)
        }
        if kind == .tandem {
            let secondSeat = CGPoint(x: size.width * 0.57, y: size.height * 0.29)
            context.stroke(line([crank, secondSeat]), with: ink, style: detailStroke)
            context.stroke(
                line([
                    CGPoint(x: secondSeat.x - size.width * 0.06, y: secondSeat.y),
                    CGPoint(x: secondSeat.x + size.width * 0.04, y: secondSeat.y)
                ]),
                with: ink,
                style: StrokeStyle(lineWidth: detailStroke.lineWidth + 2, lineCap: .round)
            )
        }
        if kind == .folding {
            context.stroke(circle(center: CGPoint(x: size.width * 0.54, y: size.height * 0.48), radius: 5),
                           with: ink, style: detailStroke)
        }
        if [.mountainFullSuspension, .enduroDownhill, .electricMountain].contains(kind) {
            context.stroke(
                line([
                    CGPoint(x: size.width * 0.40, y: size.height * 0.46),
                    CGPoint(x: size.width * 0.52, y: size.height * 0.54)
                ]),
                with: ink,
                style: StrokeStyle(lineWidth: detailStroke.lineWidth + 2, lineCap: .round, dash: [5, 4])
            )
        }
        if kind == .recumbent || kind == .handcycle {
            context.stroke(
                line([
                    CGPoint(x: seatTop.x - size.width * 0.12, y: seatTop.y),
                    CGPoint(x: seatTop.x + size.width * 0.08, y: seatTop.y + size.height * 0.03)
                ]),
                with: ink,
                style: StrokeStyle(lineWidth: detailStroke.lineWidth + 4, lineCap: .round)
            )
        }
    }

    private func circle(center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
    }

    private func line(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }
}
