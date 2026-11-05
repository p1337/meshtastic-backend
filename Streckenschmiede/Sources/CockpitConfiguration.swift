import Foundation

enum RideDataField: String, CaseIterable, Identifiable {
    case speed
    case distance
    case averageSpeed
    case maximumSpeed
    case ridingTime
    case totalTime
    case pausedTime
    case elevation
    case ascent
    case descent
    case heartRate
    case cadence
    case power
    case powerBalance
    case temperature
    case sensorBattery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speed: "Tempo"
        case .distance: "Distanz"
        case .averageSpeed: "Ø Tempo"
        case .maximumSpeed: "Maximum"
        case .ridingTime: "Fahrtzeit"
        case .totalTime: "Gesamtzeit"
        case .pausedTime: "Pausenzeit"
        case .elevation: "Höhe"
        case .ascent: "Aufstieg"
        case .descent: "Abstieg"
        case .heartRate: "Puls"
        case .cadence: "Kadenz"
        case .power: "Leistung"
        case .powerBalance: "Balance"
        case .temperature: "Temperatur"
        case .sensorBattery: "Sensorakku"
        }
    }
}

enum CockpitTextSize: String, CaseIterable, Identifiable {
    case compact
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: "Klein"
        case .medium: "Mittel"
        case .large: "Groß"
        }
    }
}

enum CockpitConfiguration {
    static let allowedFieldCounts = [1, 2, 4, 6, 8]
    static let maximumFieldCount = 8
    static let defaultFields: [RideDataField] = [
        .speed,
        .distance,
        .averageSpeed,
        .maximumSpeed,
        .ridingTime,
        .elevation,
        .heartRate,
        .power
    ]

    static func normalizedFieldCount(_ count: Int) -> Int {
        allowedFieldCounts.contains(count) ? count : 6
    }

    static func field(rawValue: String, slot: Int) -> RideDataField {
        if let field = RideDataField(rawValue: rawValue) { return field }
        let safeSlot = min(max(slot, 0), defaultFields.count - 1)
        return defaultFields[safeSlot]
    }

    static func suggestedTextSize(fieldCount: Int) -> CockpitTextSize {
        switch normalizedFieldCount(fieldCount) {
        case 1: .large
        case 2, 4: .medium
        default: .compact
        }
    }

    static func textSize(rawValue: String, fieldCount: Int) -> CockpitTextSize {
        CockpitTextSize(rawValue: rawValue) ?? suggestedTextSize(fieldCount: fieldCount)
    }
}
