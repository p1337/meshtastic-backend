import Foundation

private func bikeExpect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("Bike profile test failed: \(message)\n".utf8))
        exit(1)
    }
}

@main
enum BikeProfileSelfTest {
    static func main() throws {
        bikeExpect(BikeKind.allCases.count >= 25, "common bike categories must be represented")
        bikeExpect(
            Set(BikeKind.allCases.map(\.title)).count == BikeKind.allCases.count,
            "bike type titles must be unique"
        )
        bikeExpect(
            BikeKind.allCases.allSatisfy {
                (BikeProfile.minimumWheelDiameterMillimeters...BikeProfile.maximumWheelDiameterMillimeters)
                    .contains($0.suggestedWheelDiameterMillimeters)
            },
            "every bike type needs a plausible diameter suggestion"
        )

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bike-profile-\(UUID().uuidString)", isDirectory: true)
        let storeURL = root.appendingPathComponent("profiles.json")
        defer { try? FileManager.default.removeItem(at: root) }

        let firstID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let gravel = BikeProfile(
            id: firstID,
            name: "Gravel",
            kind: .gravel,
            wheelDiameterMillimeters: 700,
            createdAt: now,
            updatedAt: now
        )
        bikeExpect(gravel.isValid, "normal gravel profile must be valid")
        bikeExpect(abs(gravel.wheelCircumferenceMillimeters - 2_199.11) < 0.1,
                   "diameter must derive sensor circumference")

        var library = BikeProfileLibrary()
        try library.upsert(gravel)
        bikeExpect(library.activeProfileID == firstID, "first profile becomes active")

        let roadID = UUID()
        let road = BikeProfile(
            id: roadID,
            name: "Rennrad",
            kind: .road,
            wheelDiameterMillimeters: 690,
            createdAt: now,
            updatedAt: now.addingTimeInterval(10)
        )
        try library.upsert(road)
        try library.activate(roadID)
        try BikeProfileStore.save(library, to: storeURL)

        let restored = try BikeProfileStore.load(from: storeURL)
        bikeExpect(restored == library, "atomic roundtrip must preserve profiles and active bike")
        bikeExpect(restored.activeProfile?.name == "Rennrad", "active profile must survive relaunch")

        var edited = road
        edited.name = "Aero-Rennrad"
        edited.updatedAt = now.addingTimeInterval(20)
        var editedLibrary = restored
        try editedLibrary.upsert(edited)
        bikeExpect(editedLibrary.profiles.count == 2, "editing must not duplicate a profile")
        bikeExpect(editedLibrary.activeProfile?.name == "Aero-Rennrad", "active profile edit must apply")

        editedLibrary.delete(roadID)
        bikeExpect(editedLibrary.activeProfileID == firstID, "deleting active bike selects a remaining bike")

        let invalid = BikeProfile(
            name: " ",
            kind: .custom,
            wheelDiameterMillimeters: 2_000,
            createdAt: now,
            updatedAt: now
        )
        bikeExpect(!invalid.isValid, "empty name and impossible wheel diameter must be rejected")

        try Data("not-json".utf8).write(to: storeURL, options: .atomic)
        do {
            _ = try BikeProfileStore.load(from: storeURL)
            bikeExpect(false, "corrupt profile data must be rejected")
        } catch {
            bikeExpect(true, "corrupt profile data rejected")
        }

        print("Bike profile self-test passed")
    }
}
