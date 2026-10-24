import Foundation
import CoreFoundation
#if os(iOS)
import Darwin
#endif

struct AccessProbe: Codable, Identifiable {
    var id: String
    var name: String
    var status: String
    var detail: String
    var code: String? = nil
    var observations: [String] = []
}

struct RuntimeAuditReport: Codable {
    var createdUTC: String
    var environment: LabEnvironment
    var osBuild: String
    var milliseconds: Double
    var probes: [AccessProbe]
    var source = "read-only-runtime-observations"
    var rfIQSourceVerified = false
    var rfIQSamples = 0
    var driverConnectionsOpened = 0
    var modemCommandsSent = 0

    var text: String {
        var lines = ["Geräteprüfung · \(createdUTC)", "OS-Build: \(osBuild)",
                     "Echte I/Q-Samples: 0 · kein RF-Aufnahmepfad nachgewiesen."]
        for p in probes {
            lines.append("[\(p.status)] \(p.name)\(p.code.map { " · " + $0 } ?? ""): \(p.detail)")
            lines += p.observations.map { "  " + $0 }
        }
        return lines.joined(separator: "\n")
    }
}

/// Bounded interpretation of selected metadata, never RF data or arbitrary dictionaries.
enum TracePropertyDecoder {
    static let keys = ["TracePipes", "SnapshotBufferSize", "IOClass", "IOProviderClass", "IOUserClientClass"]
    static let maximumPipes = 64

    private static func unsignedInteger(_ value: Any?) -> UInt32? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let d = number.doubleValue
        guard d.isFinite, d >= 0, d <= Double(UInt32.max), d.rounded(.towardZero) == d else { return nil }
        return UInt32(d)
    }
    private static func safeName(_ value: String) -> String {
        let scalars = value.unicodeScalars.prefix(160).filter { !CharacterSet.controlCharacters.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }
    static func decode(key: String, value: Any?, instance: Int = 0) -> AccessProbe {
        var p = AccessProbe(id: "trace:\(instance):\(key)", name: "\(key) · Dienst \(instance + 1)",
                            status: "type_mismatch", detail: "Unerwarteter Datentyp; Inhalt wird nicht gespeichert.")
        guard keys.contains(key) else { p.status = "unsupported"; p.detail = "Eigenschaft nicht auf der erlaubten Liste."; return p }
        guard let value else {
            p.status = "not_returned"
            p.detail = "Kein Wert zurückgegeben. Diese API unterscheidet fehlende Eigenschaft und Zugriffsbeschränkung nicht. Kein erfundener Fehlercode."
            return p
        }
        if key == "SnapshotBufferSize" {
            guard let bytes = unsignedInteger(value) else { return p }
            p.status = "observed"; p.detail = "Trace-Puffergrößenwert: \(bytes). Einheit und Datenformat nicht verifiziert; keine RF-Samplerate oder Aufnahmedauer daraus ableitbar."
            p.observations = ["\(bytes)"]
        } else if key == "TracePipes" {
            guard let values = value as? NSArray else { return p }
            if values.count == 0 { p.status = "empty"; p.detail = "Leere Pipe-Metadatenliste zurückgegeben."; return p }
            var invalid = 0
            for i in 0..<min(values.count, maximumPipes) {
                guard let row = values[i] as? NSDictionary,
                      let code = unsignedInteger(row["Code"]), let name = row["Name"] as? String else { invalid += 1; continue }
                let cleaned = safeName(name)
                p.observations.append("#\(i) · Code \(code) · \(cleaned.isEmpty ? "(ohne Name)" : cleaned)")
            }
            p.status = invalid > 0 || values.count > maximumPipes ? "partial" : "observed"
            p.detail = "\(values.count) Einträge; \(p.observations.count) gültige Code-/Name-Paare gespeichert; \(invalid) ungültige unter den höchstens \(maximumPipes) geprüften Einträgen.\(values.count > maximumPipes ? " Liste begrenzt." : "") Keine Pipe geöffnet; Namen belegen keine RF-Samplequelle."
        } else if let name = value as? String {
            p.status = "observed"; p.detail = "Ausgewählte Klassenmetadaten; keine Aussage über App-Zugriffsrechte."
            p.observations = [safeName(name)]
        } else if let names = value as? NSArray {
            var invalid = 0
            for i in 0..<min(names.count, 32) {
                if let name = names[i] as? String { p.observations.append("#\(i) · " + safeName(name)) }
                else { invalid += 1 }
            }
            p.status = names.count == 0 ? "empty" : invalid > 0 || names.count > 32 ? "partial" : "observed"
            p.detail = "Ausgewählte Klassenliste, maximal32 Namen. Ungültige Einträge: \(invalid). Keine App-Berechtigung daraus ableitbar."
        }
        return p
    }
}

struct RadioObservation: Codable {
    var elapsedSeconds: Double
    var utc: String
    var radioTechnologies: [String]
}

/// A timed record of public telephony metadata. This type cannot capture RF.
struct AccessSession: Codable {
    var runID = UUID().uuidString
    var startedUTC: String
    var requestedSeconds: Double
    private(set) var state = "running"
    private(set) var reason: String? = nil
    private(set) var observations: [RadioObservation] = []
    var source = "public-telephony-metadata-only"
    var rfIQSamples = 0
    var rfCaptureAvailable = false
    var rfCenterFrequencyHz: Double? = nil

    enum SessionError: Error { case invalidDuration, invalidTime, ended }

    init(seconds: Double, startedUTC: String) throws {
        guard seconds.isFinite, seconds >= 1, seconds <= 300 else { throw SessionError.invalidDuration }
        requestedSeconds = seconds; self.startedUTC = startedUTC
    }
    mutating func record(elapsed: Double, utc: String, technologies: [String]) throws {
        guard state == "running" else { throw SessionError.ended }
        guard elapsed.isFinite, elapsed >= 0,
              observations.last.map({ elapsed > $0.elapsedSeconds }) ?? true else { throw SessionError.invalidTime }
        observations.append(RadioObservation(elapsedSeconds: elapsed, utc: utc,
                                             radioTechnologies: Array(Set(technologies)).sorted()))
        if elapsed >= requestedSeconds { state = "completed" }
    }
    mutating func stop(interrupted: Bool) {
        guard state == "running" else { return }
        state = interrupted ? "interrupted" : "cancelled"
        reason = interrupted ? "App wurde in den Hintergrund versetzt; Beobachtung beendet." : "Vom Nutzer beendet."
    }
    var elapsed: Double { observations.last?.elapsedSeconds ?? 0 }
    var maximumMetadataGap: Double {
        zip(observations, observations.dropFirst()).map { $1.elapsedSeconds - $0.elapsedSeconds }.max() ?? 0
    }
    var metadataGaps: Int {
        zip(observations, observations.dropFirst()).filter { $1.elapsedSeconds - $0.elapsedSeconds > 2.5 }.count
    }
    var text: String {
        """
        Zeitdiagnose · \(startedUTC)
        Zustand: \(state) · \(String(format: "%.2f", elapsed)) / \(Int(requestedSeconds)) s
        Statusabfragen: \(observations.count) · größte Metadatenlücke: \(String(format: "%.2f", maximumMetadataGap)) s
        Quelle: \(source)
        Echte I/Q-Samples: 0. Keine Funkaufnahme und keine Frequenzmessung.
        \(reason ?? "")
        """
    }
}

enum RuntimeAudit {
    // Sources and exact ABI references: RUNTIME_RESEARCH.md. No guessed RF selectors.
    static let entitlementKeys = [
        "get-task-allow", "platform-application",
        "com.apple.private.security.no-sandbox", "com.apple.private.security.no-container",
        "com.apple.private.skip-library-validation", "com.apple.security.iokit-user-client-class",
        "com.apple.CommCenter.fine-grained",
        "com.apple.driver.AppleBasebandPCI.user-access",
        "com.apple.driver.AppleBasebandPCIControl.user-access"
    ]
    // Candidate paths, not a claim that all these libraries exist on every iOS.
    static let libraryPaths = [
        "/usr/lib/libPCITransport.dylib",
        "/usr/lib/libmav_ipc_router_dynamic.dylib",
        "/usr/lib/libQMIParserDynamic.dylib",
        "/usr/lib/libBasebandManager.dylib",
        "/usr/lib/libATCommandStudioDynamic.dylib",
        "/System/Library/Frameworks/CoreTelephony.framework/Support/libCommCenterCommandDrivers.dylib"
    ]

    static func run(environment: LabEnvironment) -> RuntimeAuditReport {
        let began = ProcessInfo.processInfo.systemUptime
        var probes: [AccessProbe] = []
        var build = "nicht abgefragt"
        #if os(iOS)
        build = sysctlString("kern.osversion") ?? "nicht lesbar"
        probes.append(AccessProbe(id: "process", name: "Eigener Prozess", status: "observed",
                                  detail: "Effektive UID \(geteuid()); prüft den App-Prozess, nicht CommCenter."))
        probes += entitlements()
        probes += libraries()
        #if targetEnvironment(simulator)
        probes.append(AccessProbe(id: "registry", name: "Baseband-Dienste im IORegistry", status: "unavailable",
                                  detail: "Simulator: keine Aussage über das iPhone-Baseband; Host-Registry wird nicht untersucht."))
        probes.append(AccessProbe(id: "paths", name: "Geräte- und Carrier-Pfade", status: "unavailable",
                                  detail: "Simulator: kein Test des physischen iPhone-Dateisystems."))
        #else
        probes.append(registry())
        probes += traceProperties()
        probes += paths()
        #endif
        #if targetEnvironment(simulator)
        probes.append(AccessProbe(id: "trace:inventory", name: "Trace-Eigenschaften", status: "unavailable",
                                  detail: "Simulator: physischer Trace-Dienst wird nicht untersucht."))
        #endif
        #else
        probes.append(AccessProbe(id: "host", name: "Geräteprüfung", status: "unavailable",
                                  detail: "Nativer Host-Test; keine iPhone-Laufzeit und keine RF-Aufnahme."))
        probes.append(AccessProbe(id: "trace:inventory", name: "Trace-Eigenschaften", status: "unavailable",
                                  detail: "Host-Test: Parser wird separat geprüft, kein iPhone-Trace-Zugriff."))
        #endif
        probes.append(AccessProbe(id: "iq", name: "I/Q-Aufnahme", status: "unverified",
                                  detail: "Kein nachgewiesener Samplelieferant. Sichtbare Bibliotheken, Dienste oder Rechte allein sind kein RF-Datenstrom."))
        return RuntimeAuditReport(createdUTC: ISO8601DateFormatter().string(from: Date()), environment: environment,
                                  osBuild: build, milliseconds: (ProcessInfo.processInfo.systemUptime - began) * 1000,
                                  probes: probes)
    }

    #if os(iOS)
    private static func sysctlString(_ key: String) -> String? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0, size < 4096 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
    private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String, as type: T.Type) -> T? {
        guard let address = dlsym(handle, name) else { return nil }
        return unsafeBitCast(address, to: type)
    }

    private static func entitlements() -> [AccessProbe] {
        // Read only the current task; never request or add these entitlements.
        typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
        typealias Copy = @convention(c) (CFTypeRef, CFString, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFTypeRef>?
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY | RTLD_LOCAL) else {
            return [AccessProbe(id: "entitlements", name: "Eigene Entitlements", status: "unavailable", detail: "Security konnte nicht geladen werden.")]
        }
        defer { dlclose(handle) }
        guard let create = symbol(handle, "SecTaskCreateFromSelf", as: Create.self),
              let copy = symbol(handle, "SecTaskCopyValueForEntitlement", as: Copy.self),
              let task = create(nil)?.takeRetainedValue() else {
            return [AccessProbe(id: "entitlements", name: "Eigene Entitlements", status: "unavailable", detail: "SecTask-Abfrage nicht verfügbar.")]
        }
        return entitlementKeys.map { key in
            var failure: Unmanaged<CFError>?
            let value = copy(task, key as CFString, &failure)?.takeRetainedValue()
            let error = failure?.takeRetainedValue()
            var code: String? = nil
            if let error { code = "\(CFErrorGetDomain(error) as String):\(CFErrorGetCode(error))" }
            guard let value else {
                return AccessProbe(id: "entitlement:" + key, name: key, status: error == nil ? "absent" : "unavailable",
                                   detail: error == nil ? "Für den eigenen Prozess nicht gesetzt." : "Kein Wert zurückgegeben; Fehlercode erhalten.", code: code)
            }
            let summary: String
            let status: String
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                let flag = (value as? NSNumber)?.boolValue ?? false
                summary = flag ? "true" : "false"; status = flag ? "observed" : "absent"
            } else if let values = value as? [String] {
                summary = values.prefix(32).map { String($0.prefix(120)) }.joined(separator: ", "); status = "observed"
            } else { summary = "Wert vorhanden; Inhalt wird nicht gespeichert."; status = "observed" }
            return AccessProbe(id: "entitlement:" + key, name: key, status: status,
                               detail: summary + " · Keine Berechtigung geändert.", code: code)
        }
    }

    private static func libraries() -> [AccessProbe] {
        // Check cache membership/loaded images without loading private modem libraries.
        typealias Contains = @convention(c) (UnsafePointer<CChar>) -> Bool
        typealias Count = @convention(c) () -> UInt32
        typealias Name = @convention(c) (UInt32) -> UnsafePointer<CChar>?
        guard let process = dlopen(nil, RTLD_LAZY) else { return [] }
        defer { dlclose(process) }
        let contains = symbol(process, "_dyld_shared_cache_contains_path", as: Contains.self)
        let count = symbol(process, "_dyld_image_count", as: Count.self)
        let imageName = symbol(process, "_dyld_get_image_name", as: Name.self)
        var loaded = Set<String>()
        if let count, let imageName {
            for i in 0..<min(count(), 4096) { if let name = imageName(i) { loaded.insert(String(cString: name)) } }
        }
        return libraryPaths.map { path in
            let cached = contains.map { fn in path.withCString { fn($0) } }
            let inProcess = loaded.contains(path)
            return AccessProbe(id: "library:" + path, name: URL(fileURLWithPath: path).lastPathComponent,
                               status: cached == true || inProcess ? "observed" : contains == nil ? "unavailable" : "not_observed",
                               detail: "Shared Cache: \(cached.map { $0 ? "ja" : "nein" } ?? "unbekannt"); im App-Prozess geladen: \(inProcess ? "ja" : "nein"). Keine Transportfunktion aufgerufen.")
        }
    }

    private static func registry() -> AccessProbe {
        typealias Matching = @convention(c) (UnsafePointer<CChar>) -> Unmanaged<CFMutableDictionary>?
        typealias Services = @convention(c) (UInt32, CFDictionary, UnsafeMutablePointer<UInt32>) -> Int32
        typealias Next = @convention(c) (UInt32) -> UInt32
        typealias GetClass = @convention(c) (UInt32, UnsafeMutablePointer<CChar>) -> Int32
        typealias Release = @convention(c) (UInt32) -> Int32
        let base = AccessProbe(id: "registry", name: "Baseband-Dienste im IORegistry", status: "unavailable", detail: "IOKit-Abfrage nicht verfügbar.")
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL) else { return base }
        defer { dlclose(handle) }
        guard let matching = symbol(handle, "IOServiceMatching", as: Matching.self),
              let services = symbol(handle, "IOServiceGetMatchingServices", as: Services.self),
              let next = symbol(handle, "IOIteratorNext", as: Next.self),
              let getClass = symbol(handle, "IOObjectGetClass", as: GetClass.self),
              let release = symbol(handle, "IOObjectRelease", as: Release.self),
              let match = "IOService".withCString({ matching($0) }) else { return base }
        var iterator: UInt32 = 0
        // Matching returns +1. GetMatchingServices consumes that reference even on failure.
        let code = services(0, match.takeUnretainedValue(), &iterator)
        defer { if iterator != 0 { _ = release(iterator) } }
        guard code == 0 else {
            return AccessProbe(id: "registry", name: base.name, status: "error",
                               detail: "Registry-Abfrage liefert Fehler. Das belegt keine fehlende HF-Hardware.",
                               code: String(format: "0x%08x", UInt32(bitPattern: code)))
        }
        var names = Set<String>(), inspected = 0
        while iterator != 0 && inspected < 2048 {
            let object = next(iterator)
            if object == 0 { break }
            var buffer = [CChar](repeating: 0, count: 128)
            if getClass(object, &buffer) == 0 {
                let name = String(cString: buffer)
                if ["baseband", "qmi", "convergedipc", "telephony"].contains(where: { name.lowercased().contains($0) }) {
                    names.insert(name)
                }
            }
            _ = release(object); inspected += 1
        }
        return AccessProbe(id: "registry", name: base.name, status: names.isEmpty ? "not_observed" : "observed",
                           detail: "\(inspected) sichtbare Einträge untersucht\(inspected == 2048 ? " (Limit erreicht)" : ""). Nur Klassennamen; kein UserClient geöffnet und keine Register gelesen.",
                           code: "0x00000000", observations: Array(names).sorted().prefix(64).map { $0 })
    }

    /// Only selected metadata from a known service. Never opens a user client.
    private static func traceProperties() -> [AccessProbe] {
        typealias Matching = @convention(c) (UnsafePointer<CChar>) -> Unmanaged<CFMutableDictionary>?
        typealias Services = @convention(c) (UInt32, CFDictionary, UnsafeMutablePointer<UInt32>) -> Int32
        typealias Next = @convention(c) (UInt32) -> UInt32
        typealias Release = @convention(c) (UInt32) -> Int32
        typealias Property = @convention(c) (UInt32, CFString, CFAllocator?, UInt32) -> Unmanaged<CFTypeRef>?
        let base = AccessProbe(id: "trace:inventory", name: "Trace-Eigenschaften", status: "unavailable",
                               detail: "Gezielte Registry-Eigenschaftsabfrage nicht verfügbar.")
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL) else { return [base] }
        defer { dlclose(handle) }
        guard let matching = symbol(handle, "IOServiceMatching", as: Matching.self),
              let services = symbol(handle, "IOServiceGetMatchingServices", as: Services.self),
              let next = symbol(handle, "IOIteratorNext", as: Next.self),
              let release = symbol(handle, "IOObjectRelease", as: Release.self),
              let property = symbol(handle, "IORegistryEntryCreateCFProperty", as: Property.self),
              let match = "AppleBasebandPCITraceBackendRaw".withCString({ matching($0) }) else { return [base] }
        var iterator: UInt32 = 0
        let result = services(0, match.takeUnretainedValue(), &iterator)
        defer { if iterator != 0 { _ = release(iterator) } }
        guard result == 0 else {
            return [AccessProbe(id: base.id, name: base.name, status: "error",
                                detail: "Gezielte Dienstsuche fehlgeschlagen; keine Verbindung versucht.",
                                code: String(format: "0x%08x", UInt32(bitPattern: result)))]
        }
        var probes: [AccessProbe] = [], count = 0
        while iterator != 0 && count < 16 {
            let object = next(iterator)
            if object == 0 { break }
            for key in TracePropertyDecoder.keys {
                let value = property(object, key as CFString, nil, 0)?.takeRetainedValue()
                probes.append(TracePropertyDecoder.decode(key: key, value: value, instance: count))
            }
            _ = release(object)
            count += 1
        }
        probes.insert(AccessProbe(id: base.id, name: base.name, status: count == 0 ? "not_observed" : "observed",
                                  detail: "\(count) passende Trace-Dienste\(count == 16 ? " (Abfragelimit erreicht)" : ""). Nur fünf benannte Eigenschaften; kein UserClient geöffnet, kein Log gelesen und keine Modemsteuerung.",
                                  code: "0x00000000"), at: 0)
        return probes
    }

    private static func paths() -> [AccessProbe] {
        var probes: [AccessProbe] = []
        for path in ["/System/Library/Carrier Bundles", "/var/mobile/Library/Carrier Bundles"] {
            var info = stat()
            let result = lstat(path, &info); let code = errno
            probes.append(AccessProbe(id: "path:" + path, name: path,
                                      status: result == 0 ? "observed" : code == EACCES || code == EPERM ? "restricted" : "not_observed",
                                      detail: result == 0 ? "Pfad-Metadaten sichtbar. Keine Carrier-Konfiguration gelesen oder verändert." : "Pfad aus dieser App nicht nachgewiesen; Dateinamensraum und Sandbox berücksichtigen.",
                                      code: result == 0 ? nil : "errno:\(code)"))
        }
        guard let directory = opendir("/dev") else {
            probes.append(AccessProbe(id: "devices", name: "Baseband-nahe Gerätenamen", status: "restricted", detail: "/dev nicht auflistbar.", code: "errno:\(errno)")); return probes
        }
        defer { closedir(directory) }
        var names: [String] = [], visited = 0
        errno = 0
        while visited < 2048, let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if ["baseband", "qmi", "diag", "bb."].contains(where: { name.lowercased().contains($0) }) { names.append(name) }
            visited += 1
        }
        let failure = errno
        probes.append(AccessProbe(id: "devices", name: "Baseband-nahe Gerätenamen",
                                  status: failure != 0 ? "restricted" : names.isEmpty ? "not_observed" : "observed",
                                  detail: "Nur Namen gefiltert; kein Geräteknoten geöffnet, kein Byte gelesen. Eine leere Liste widerlegt keinen PCIe-Pfad.",
                                  code: failure == 0 ? nil : "errno:\(failure)", observations: Array(names.prefix(64))))
        return probes
    }
    #endif
}
