import Foundation

public enum ShiftDirection: Int, Codable, CaseIterable, Sendable {
    case down = -1, up = 1
    public var label: String { self == .up ? "Hochschalten" : "Herunterschalten" }
}

public struct ButtonBinding: Codable, Equatable, Sendable {
    public var button: ClickButton
    public var direction: ShiftDirection
    public init(button: ClickButton, direction: ShiftDirection) { self.button = button; self.direction = direction }
}

public enum GearError: Error, Equatable {
    case invalidCount, invalidRatios, invalidStart, invalidTiming, invalidBindings
    case noIntegration, busy, rateLimited, boundary, staleAcknowledgement
}

public struct GearConfiguration: Codable, Equatable, Sendable {
    public var ratios: [Double]
    public var startGear: Int
    public var shiftInterval: TimeInterval
    public var debounce: TimeInterval
    public var longPress: TimeInterval
    public var bindings: [ButtonBinding]
    public var count: Int { ratios.count }
    public static var standard: GearConfiguration {
        GearConfiguration(ratios: (0..<24).map { 0.75 * pow(6.0, Double($0) / 23.0) },
                          startGear: 12, shiftInterval: 0.12, debounce: 0.08, longPress: 0.6,
                          bindings: [.init(button: .minus, direction: .down), .init(button: .plus, direction: .up)])
    }
    public func validate() throws {
        guard (2...64).contains(count) else { throw GearError.invalidCount }
        guard ratios.allSatisfy({ $0.isFinite && (0.05...20).contains($0) }),
              zip(ratios, ratios.dropFirst()).allSatisfy({ $0.0 < $0.1 }) else { throw GearError.invalidRatios }
        guard (1...count).contains(startGear) else { throw GearError.invalidStart }
        guard shiftInterval.isFinite, (0...2).contains(shiftInterval),
              debounce.isFinite, (0.01...0.5).contains(debounce),
              longPress.isFinite, (0.3...3).contains(longPress) else { throw GearError.invalidTiming }
        guard Set(bindings.map(\.button)).count == bindings.count else { throw GearError.invalidBindings }
    }
    public func direction(for event: ButtonEvent) -> ShiftDirection? {
        guard event.phase == .down else { return nil }
        return bindings.first { $0.button == event.button }?.direction
    }
    public mutating func resize(_ count: Int) throws {
        guard (2...64).contains(count), let low = ratios.first, let high = ratios.last else { throw GearError.invalidCount }
        ratios = (0..<count).map { low * pow(high / low, Double($0) / Double(count - 1)) }
        startGear = min(count, max(1, startGear))
        try validate()
    }
}

public struct ShiftRequest: Equatable, Sendable {
    public let id: UUID
    public let gear: Int
    public let ratio: Double
    public let direction: ShiftDirection
}

/// A transport acceptance is not a measurement of physical trainer resistance.
public enum DeliveryEvidence: String, Codable, Sendable { case softwareAccepted }

public struct GearEngine: Sendable {
    public let configuration: GearConfiguration
    public private(set) var acceptedGear: Int?
    public private(set) var pending: ShiftRequest?
    private var lastAcceptedAt: TimeInterval?

    public init(configuration: GearConfiguration = .standard, lastAcceptedGear: Int? = nil) throws {
        try configuration.validate()
        self.configuration = configuration
        acceptedGear = lastAcceptedGear.flatMap { (1...configuration.count).contains($0) ? $0 : nil }
    }
    public mutating func request(_ direction: ShiftDirection, at now: TimeInterval, integrationAvailable: Bool) throws -> ShiftRequest {
        guard integrationAvailable else { throw GearError.noIntegration }
        guard pending == nil else { throw GearError.busy }
        if let lastAcceptedAt, now - lastAcceptedAt < configuration.shiftInterval { throw GearError.rateLimited }
        let gear = (acceptedGear ?? configuration.startGear) + direction.rawValue
        guard (1...configuration.count).contains(gear) else { throw GearError.boundary }
        let request = ShiftRequest(id: UUID(), gear: gear, ratio: configuration.ratios[gear - 1], direction: direction)
        pending = request
        return request
    }
    public mutating func acknowledge(_ request: ShiftRequest, evidence: DeliveryEvidence, at now: TimeInterval) throws {
        guard pending == request else { throw GearError.staleAcknowledgement }
        acceptedGear = request.gear; lastAcceptedAt = now; pending = nil
    }
    public mutating func reject(_ request: ShiftRequest) {
        if pending?.id == request.id { pending = nil }
    }
}

public struct SavedSettings: Codable, Equatable, Sendable {
    public var gearing: GearConfiguration = .standard
    /// Last software-accepted gear; it is never presented as a live trainer readout.
    public var lastAcceptedGear: Int?
    public init() {}
    public static func restore(from data: Data?) -> SavedSettings {
        guard let data, var result = try? JSONDecoder().decode(SavedSettings.self, from: data),
              (try? result.gearing.validate()) != nil else { return SavedSettings() }
        if let gear = result.lastAcceptedGear, !(1...result.gearing.count).contains(gear) { result.lastAcceptedGear = nil }
        return result
    }
}
