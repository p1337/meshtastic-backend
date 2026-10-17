import SwiftUI
import Security

@MainActor final class WorkStore: ObservableObject {
    @Published var data = Workspace()
    @Published var error: String? = nil
    @Published var syncing = false
    @Published var syncStatus = ""
    @Published var dirty = false
    @Published var canEdit = true
    var version = 0
    private let root: URL
    private var loaded = false
    private var persistedData = Workspace()
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Werkbeleg", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
            let url = self.root.appendingPathComponent("workspace.json")
            if FileManager.default.fileExists(atPath: url.path) { data = try Workspace.decode(Data(contentsOf: url)) }
            let meta = self.root.appendingPathComponent("sync.json")
            if let m = try? JSONSerialization.jsonObject(with: Data(contentsOf: meta)) as? [String: Any] {
                version = m["version"] as? Int ?? 0; dirty = m["dirty"] as? Bool ?? false
            }
            persistedData = data; loaded = true
        } catch { self.error = error.localizedDescription }
    }
    @discardableResult func save() -> Bool {
        guard loaded else { return false }
        do {
            let bytes = try data.encoded()
            guard bytes.count <= 30 * 1024 * 1024 else { throw ModelError.tooLarge }
            try bytes.write(to: root.appendingPathComponent("workspace.json"), options: [.atomic, .completeFileProtection])
            persistedData = data; dirty = true; try saveMeta(); return true
        } catch { data = persistedData; self.error = error.localizedDescription; return false }
    }
    private func saveMeta() throws {
        try JSONSerialization.data(withJSONObject: ["version": version, "dirty": dirty]).write(to: root.appendingPathComponent("sync.json"), options: [.atomic, .completeFileProtection])
    }
    func backup() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Werkbeleg-\(Int(Date().timeIntervalSince1970)).werkbeleg")
        try data.encoded().write(to: url, options: [.atomic, .completeFileProtection]); return url
    }
    func restore(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let restored = try Workspace.decode(Data(contentsOf: url))
        _ = try backup() // retain current snapshot locally before replacement
        data = restored; save()
    }
    func sync() async {
        guard !syncing else { return }
        let address = UserDefaults.standard.string(forKey: "teamURL") ?? ""
        guard let base = URL(string: address), base.scheme == "https", base.host != nil,
              base.user == nil, base.password == nil, base.query == nil, base.fragment == nil,
              let token = KeychainToken.read(), !token.isEmpty else {
            syncStatus = L.t("Kein Teamserver verbunden", "No team server connected", "Nie połączono serwera zespołu"); return
        }
        syncing = true; defer { syncing = false }
        do {
            var get = URLRequest(url: base.appendingPathComponent("workspace")); get.timeoutInterval = 30
            get.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (bytes, response) = try await URLSession.shared.data(for: get)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw TeamError.message("Teamserver: Zugriff fehlgeschlagen / Access denied") }
            let remote = try JSONDecoder().decode(TeamSnapshot.self, from: bytes); try remote.workspace.validate()
            canEdit = http.value(forHTTPHeaderField: "X-Role") != "reader"
            if dirty {
                guard canEdit else { throw TeamError.message("Nur Leserechte. Lokale Änderungen bleiben erhalten.") }
                guard remote.version == version else { throw TeamError.message("Versionskonflikt: lokale Daten bleiben erhalten. Sicherung exportieren; danach den Teamstand laden.") }
                var put = get; put.httpMethod = "PUT"; put.setValue("application/json", forHTTPHeaderField: "Content-Type")
                put.httpBody = try JSONEncoder().encode(TeamSnapshot(version: version, workspace: data))
                let (result, res) = try await URLSession.shared.data(for: put)
                guard (res as? HTTPURLResponse)?.statusCode == 200 else { throw TeamError.message("Team-Upload abgelehnt; lokale Daten bleiben erhalten (ggf. Versionskonflikt).") }
                let saved = try JSONDecoder().decode(TeamSnapshot.self, from: result); version = saved.version
            } else {
                let bytes = try remote.workspace.encoded()
                try bytes.write(to: root.appendingPathComponent("workspace.json"), options: [.atomic, .completeFileProtection])
                data = remote.workspace; persistedData = data; version = remote.version
            }
            dirty = false; try saveMeta(); syncStatus = "✓ \(L.t("Synchronisiert", "Synced", "Zsynchronizowano")) · v\(version)"
        } catch { syncStatus = error.localizedDescription }
    }
    func loadTeamVersion() async {
        do { _ = try backup(); dirty = false; try saveMeta(); await sync() }
        catch { self.error = error.localizedDescription }
    }
}
enum TeamError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(s) = self { return s }; return nil }
}
enum KeychainToken {
    static let service = "de.p1337.werkbeleg.team"
    static func read() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let bytes = item as? Data else { return nil }
        return String(data: bytes, encoding: .utf8)
    }
    static func save(_ token: String) throws {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(q as CFDictionary)
        guard !token.isEmpty else { return }
        var attributes = q; attributes[kSecValueData as String] = Data(token.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw TeamError.message("Token konnte nicht sicher gespeichert werden.") }
    }
}
