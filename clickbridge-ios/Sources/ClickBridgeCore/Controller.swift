import Foundation

public enum ControllerSide: String, Codable, CaseIterable, Sendable {
    case left, right
    public var label: String { self == .left ? "Links" : "Rechts" }
}

public enum ClickButton: UInt32, Codable, CaseIterable, Sendable {
    case left = 1, up = 2, right = 4, down = 8
    case a = 16, b = 32, y = 64, z = 128
    case minus = 256, plus = 4096

    public var label: String {
        switch self {
        case .left: return "←"
        case .up: return "↑"
        case .right: return "→"
        case .down: return "↓"
        case .a: return "A"
        case .b: return "B"
        case .y: return "Y"
        case .z: return "Z"
        case .minus: return "−"
        case .plus: return "+"
        }
    }
    public var side: ControllerSide {
        switch self {
        case .left, .up, .right, .down, .minus: return .left
        default: return .right
        }
    }
}

public struct ManufacturerIdentity: Equatable, Sendable {
    public let side: ControllerSide
    public init?(data: Data) {
        let bytes = Array(data)
        guard bytes.count >= 3, bytes[0] == 0x4A, bytes[1] == 0x09 else { return nil }
        switch bytes[2] {
        case 0x0A: side = .right
        case 0x0B: side = .left
        default: return nil
        }
    }
}

public enum AssignmentError: Error, Equatable { case sideOccupied, deviceAlreadyAssigned }

public struct ControllerRegistry: Codable, Equatable, Sendable {
    public private(set) var left: UUID?
    public private(set) var right: UUID?
    public init() {}
    public func id(for side: ControllerSide) -> UUID? { side == .left ? left : right }
    public func side(for id: UUID) -> ControllerSide? {
        if left == id { return .left }
        if right == id { return .right }
        return nil
    }
    public mutating func assign(_ id: UUID, to side: ControllerSide) throws {
        if let current = self.side(for: id), current != side { throw AssignmentError.deviceAlreadyAssigned }
        if let current = self.id(for: side), current != id { throw AssignmentError.sideOccupied }
        if side == .left { left = id } else { right = id }
    }
    public mutating func remove(_ side: ControllerSide) {
        if side == .left { left = nil } else { right = nil }
    }
}

public enum ButtonPhase: String, Codable, Sendable { case down, up, longPress }
public struct ButtonEvent: Equatable, Sendable {
    public let button: ClickButton
    public let phase: ButtonPhase
    public let duration: TimeInterval
}

/// Leading-edge presses, duplicate-frame suppression and long press on release.
/// No timer or guessed release: a missing release is not a second press.
public struct ButtonTracker: Sendable {
    public var debounce: TimeInterval = 0.08
    public var longPress: TimeInterval = 0.6
    private var held: [ClickButton: TimeInterval] = [:]
    private var lastAccepted: [ClickButton: TimeInterval] = [:]
    private var previous: Set<ClickButton> = []
    public init() {}

    public mutating func update(_ pressed: Set<ClickButton>, at now: TimeInterval) -> [ButtonEvent] {
        var events: [ButtonEvent] = []
        for button in previous.subtracting(pressed).sorted(by: { $0.rawValue < $1.rawValue }) {
            if let start = held.removeValue(forKey: button) {
                let duration = max(0, now - start)
                events.append(ButtonEvent(button: button, phase: .up, duration: duration))
                if duration >= longPress {
                    events.append(ButtonEvent(button: button, phase: .longPress, duration: duration))
                }
            }
        }
        for button in pressed.subtracting(previous).sorted(by: { $0.rawValue < $1.rawValue }) {
            guard now - (lastAccepted[button] ?? -.infinity) >= debounce else { continue }
            held[button] = now
            lastAccepted[button] = now
            events.append(ButtonEvent(button: button, phase: .down, duration: 0))
        }
        previous = pressed
        return events
    }
    public mutating func reset() {
        held.removeAll(); previous.removeAll(); lastAccepted.removeAll()
    }
}

public struct ReconnectPolicy: Equatable, Sendable {
    public private(set) var failures = 0
    public let maximumAttempts: Int
    public init(maximumAttempts: Int = 8) { self.maximumAttempts = max(1, maximumAttempts) }
    public mutating func nextDelay() -> TimeInterval? {
        guard failures < maximumAttempts else { return nil }
        let delay = min(60.0, pow(2.0, Double(failures)))
        failures += 1
        return delay
    }
    public mutating func succeeded() { failures = 0 }
}

public enum SessionPhase: String, Codable, Sendable {
    case discovered, connecting, discovering, subscribing, initializing
    case awaitingInput, receiving, attention, disconnected
    public var label: String {
        switch self {
        case .discovered: return "Gefunden"
        case .connecting: return "Verbinden"
        case .discovering: return "GATT prüfen"
        case .subscribing: return "Notifications aktivieren"
        case .initializing: return "Initialisieren"
        case .awaitingInput: return "Handshake erhalten · Taste drücken"
        case .receiving: return "Tasten empfangen"
        case .attention: return "Prüfung erforderlich"
        case .disconnected: return "Getrennt"
        }
    }
}

public struct SessionMachine: Sendable {
    public private(set) var phase: SessionPhase = .discovered
    public private(set) var reason: String?
    public init() {}
    @discardableResult public mutating func advance(to next: SessionPhase) -> Bool {
        let permitted: Bool
        switch (phase, next) {
        case (_, .disconnected), (_, .attention): permitted = true
        case (.discovered, .connecting), (.disconnected, .connecting), (.attention, .connecting),
             (.connecting, .discovering), (.discovering, .subscribing),
             (.subscribing, .initializing), (.initializing, .awaitingInput),
             (.awaitingInput, .receiving), (.receiving, .receiving): permitted = true
        default: permitted = false
        }
        if permitted { phase = next; reason = nil }
        return permitted
    }
    public mutating func fail(_ message: String) { phase = .attention; reason = message }
}
