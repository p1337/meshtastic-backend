import Foundation

enum BikeKind: String, Codable, CaseIterable, Identifiable {
    case road
    case gravel
    case cyclocross
    case triathlon
    case trackFixed
    case mountainHardtail
    case mountainFullSuspension
    case enduroDownhill
    case dirtJump
    case fatBike
    case trekking
    case city
    case touring
    case hybrid
    case cargo
    case folding
    case bmx
    case recumbent
    case tandem
    case handcycle
    case cruiser
    case kids
    case electricRoad
    case electricGravel
    case electricMountain
    case electricCityTrekking
    case electricCargo
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .road: "Rennrad"
        case .gravel: "Gravelbike"
        case .cyclocross: "Cyclocross"
        case .triathlon: "Triathlon / Zeitfahren"
        case .trackFixed: "Bahnrad / Fixie"
        case .mountainHardtail: "MTB Hardtail"
        case .mountainFullSuspension: "MTB Fully"
        case .enduroDownhill: "Enduro / Downhill"
        case .dirtJump: "Dirt Jump"
        case .fatBike: "Fatbike"
        case .trekking: "Trekkingrad"
        case .city: "Citybike"
        case .touring: "Reiserad"
        case .hybrid: "Cross- / Hybridrad"
        case .cargo: "Lastenrad"
        case .folding: "Faltrad"
        case .bmx: "BMX"
        case .recumbent: "Liegerad"
        case .tandem: "Tandem"
        case .handcycle: "Handbike"
        case .cruiser: "Cruiser"
        case .kids: "Kinderfahrrad"
        case .electricRoad: "E-Rennrad"
        case .electricGravel: "E-Gravelbike"
        case .electricMountain: "E-Mountainbike"
        case .electricCityTrekking: "E-City / E-Trekking"
        case .electricCargo: "E-Lastenrad"
        case .custom: "Andere / Benutzerdefiniert"
        }
    }

    var suggestedWheelDiameterMillimeters: Double {
        switch self {
        case .folding, .bmx, .handcycle, .kids:
            508
        case .dirtJump, .cargo, .electricCargo:
            660
        case .mountainHardtail, .mountainFullSuspension, .enduroDownhill,
             .fatBike, .electricMountain:
            737
        default:
            700
        }
    }

    var isElectric: Bool {
        switch self {
        case .electricRoad, .electricGravel, .electricMountain,
             .electricCityTrekking, .electricCargo:
            true
        default:
            false
        }
    }
}

struct BikeProfile: Codable, Equatable, Identifiable {
    static let minimumWheelDiameterMillimeters = 250.0
    static let maximumWheelDiameterMillimeters = 900.0

    let id: UUID
    var name: String
    var kind: BikeKind
    var wheelDiameterMillimeters: Double
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        kind: BikeKind,
        wheelDiameterMillimeters: Double,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.wheelDiameterMillimeters = wheelDiameterMillimeters
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var wheelCircumferenceMillimeters: Double {
        wheelDiameterMillimeters * .pi
    }

    var wheelCircumferenceMeters: Double {
        wheelCircumferenceMillimeters / 1_000
    }

    var wheelDiameterInches: Double {
        wheelDiameterMillimeters / 25.4
    }

    var isValid: Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleanName.isEmpty
            && cleanName.count <= 80
            && wheelDiameterMillimeters.isFinite
            && (Self.minimumWheelDiameterMillimeters...Self.maximumWheelDiameterMillimeters)
                .contains(wheelDiameterMillimeters)
            && createdAt.timeIntervalSince1970.isFinite
            && updatedAt.timeIntervalSince1970.isFinite
    }
}

struct BikeProfileLibrary: Codable, Equatable {
    private(set) var profiles: [BikeProfile]
    private(set) var activeProfileID: UUID?

    init(profiles: [BikeProfile] = [], activeProfileID: UUID? = nil) {
        self.profiles = profiles
        self.activeProfileID = activeProfileID
    }

    var activeProfile: BikeProfile? {
        guard let activeProfileID else { return nil }
        return profiles.first { $0.id == activeProfileID }
    }

    var isValid: Bool {
        profiles.count <= BikeProfileStore.maximumProfiles
            && profiles.allSatisfy(\.isValid)
            && Set(profiles.map(\.id)).count == profiles.count
            && ((profiles.isEmpty && activeProfileID == nil)
                || (!profiles.isEmpty && activeProfile != nil))
    }

    mutating func upsert(_ profile: BikeProfile, makeActive: Bool = false) throws {
        guard profile.isValid else { throw BikeProfileStore.profileError("Ungültiges Fahrradprofil") }
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            guard profiles.count < BikeProfileStore.maximumProfiles else {
                throw BikeProfileStore.profileError("Maximal \(BikeProfileStore.maximumProfiles) Fahrradprofile")
            }
            profiles.append(profile)
        }
        profiles.sort { $0.updatedAt > $1.updatedAt }
        if activeProfileID == nil || makeActive {
            activeProfileID = profile.id
        }
    }

    mutating func activate(_ id: UUID) throws {
        guard profiles.contains(where: { $0.id == id }) else {
            throw BikeProfileStore.profileError("Fahrradprofil nicht gefunden")
        }
        activeProfileID = id
    }

    mutating func delete(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        if activeProfileID == id {
            activeProfileID = profiles.first?.id
        }
    }
}

private struct StoredBikeProfileEnvelope: Codable {
    let schemaVersion: Int
    let library: BikeProfileLibrary
}

enum BikeProfileStore {
    static let maximumProfiles = 50
    private static let schemaVersion = 1
    private static let maximumFileBytes = 1_024 * 1_024

    static func load(from url: URL = defaultURL()) throws -> BikeProfileLibrary {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return BikeProfileLibrary()
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true,
              let size = values.fileSize,
              size > 0,
              size <= maximumFileBytes else {
            throw profileError("Ungültige oder zu große Fahrradprofildatei")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let envelope = try decoder.decode(
            StoredBikeProfileEnvelope.self,
            from: Data(contentsOf: url, options: [.mappedIfSafe])
        )
        guard envelope.schemaVersion == schemaVersion,
              envelope.library.isValid else {
            throw profileError("Ungültige Fahrradprofile")
        }
        return envelope.library
    }

    static func save(
        _ library: BikeProfileLibrary,
        to url: URL = defaultURL()
    ) throws {
        guard library.isValid else { throw profileError("Ungültige Fahrradprofile") }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(
            StoredBikeProfileEnvelope(schemaVersion: schemaVersion, library: library)
        )
        guard data.count <= maximumFileBytes else {
            throw profileError("Fahrradprofile sind zu groß zum sicheren Speichern")
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    static func defaultURL() -> URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("Streckenschmiede", isDirectory: true)
            .appendingPathComponent("bike-profiles-v1.json", isDirectory: false)
    }

    static func profileError(_ message: String) -> NSError {
        NSError(
            domain: "Streckenschmiede.BikeProfileStore",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
