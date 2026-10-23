#if canImport(CoreBluetooth)
import Foundation
import Combine

public struct DiagnosticEntry: Identifiable, Codable, Sendable {
    public let id: UUID
    public let time: Date
    public let category: String
    public let message: String
}

@MainActor public final class DiagnosticLog: ObservableObject {
    @Published public private(set) var entries: [DiagnosticEntry] = []
    public private(set) var storageError: String?
    private let directory: URL
    private let file: URL
    private let maximumBytes = 2 * 1024 * 1024

    public init(namespace: String) {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(namespace, isDirectory: true)
        file = directory.appendingPathComponent("ble.jsonl")
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { storageError = error.localizedDescription }
    }

    public func record(_ category: String, _ message: String) {
        let entry = DiagnosticEntry(id: UUID(), time: Date(), category: category,
                                    message: String(message.prefix(3000)))
        entries.append(entry)
        if entries.count > 600 { entries.removeFirst(entries.count - 600) }
        do {
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size >= maximumBytes {
                let previous = directory.appendingPathComponent("ble.previous.jsonl")
                try? FileManager.default.removeItem(at: previous)
                try FileManager.default.moveItem(at: file, to: previous)
            }
            if !FileManager.default.fileExists(atPath: file.path) {
                try Data().write(to: file, options: .atomic)
                #if os(iOS)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
                #endif
            }
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            var data = try encoder.encode(entry); data.append(0x0A)
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd(); try handle.write(contentsOf: data)
        } catch { storageError = error.localizedDescription }
    }

    public func export() throws -> URL {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("ClickBridge-Diagnose.jsonl")
        var output = Data("{\"notice\":\"BLE software observations only; no hardware acceptance claim\"}\n".utf8)
        let previous = directory.appendingPathComponent("ble.previous.jsonl")
        if let old = try? Data(contentsOf: previous) { output.append(old) }
        if FileManager.default.fileExists(atPath: file.path) { output.append(try Data(contentsOf: file)) }
        try output.write(to: destination, options: .atomic)
        return destination
    }
}
#endif
