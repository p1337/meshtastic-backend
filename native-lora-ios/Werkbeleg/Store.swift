import SwiftUI
import Security
import CryptoKit

@MainActor final class WorkStore: ObservableObject {
    @Published var data = Workspace()
    @Published var error: String? = nil
    @Published var syncing = false
    @Published var syncStatus = ""
    @Published var dirty = false
    @Published var invitation: InvitationContext? = nil
    @Published var teamInfo: TeamInfo? = nil
    @Published var canEdit = true
    var version = 0
    @Published var contextID = "local"
    var root: URL
    let baseRoot: URL
    var canBulkManage: Bool { contextID == "local" || ["owner", "admin"].contains(teamInfo?.role ?? "") }
    static func scope(server: String, token: String) -> String {
        SHA256.hash(data: Data((server.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "\n" + token).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func activateTeam(server: String, token: String) throws {
        guard !syncing else { throw TeamError.message("Bitte Synchronisation abwarten / Wait for sync") }
        let address = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: address), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, !token.isEmpty else { throw TeamError.message("HTTPS-Server und Zugangstoken benötigt / HTTPS server and token required") }
        let key = Self.scope(server: address, token: token)
        if key == contextID { return }
        let nextRoot = baseRoot.appendingPathComponent("Contexts", isDirectory: true).appendingPathComponent(key, isDirectory: true)
        let next = WorkStore(root: nextRoot)
        guard next.loaded else { throw TeamError.message(next.error ?? "Betriebsbereich konnte nicht geladen werden") }
        try KeychainToken.save(token)
        UserDefaults.standard.set(address, forKey: "teamURL")
        root = nextRoot; data = next.data; persistedData = next.persistedData; version = next.version; dirty = next.dirty
        teamInfo = nil; canEdit = false; contextID = key; syncStatus = ""
    }
    func disconnectTeam() throws {
        guard !syncing else { throw TeamError.message("Bitte Synchronisation abwarten / Wait for sync") }
        let local = WorkStore(root: baseRoot)
        guard local.loaded else { throw ModelError.invalid }
        try KeychainToken.save(""); UserDefaults.standard.removeObject(forKey: "teamURL")
        root = baseRoot; data = local.data; persistedData = local.persistedData; version = local.version; dirty = local.dirty
        teamInfo = nil; canEdit = true; contextID = "local"; syncStatus = ""
    }
    private var loaded = false
    var persistedData = Workspace()
    init(root: URL? = nil, resumeTeam: Bool = false) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Werkbeleg", isDirectory: true)
        baseRoot = base; self.root = base
        if root == nil || resumeTeam, let server = UserDefaults.standard.string(forKey: "teamURL"), let token = KeychainToken.read(), !token.isEmpty {
            let key = Self.scope(server: server, token: token)
            let scoped = base.appendingPathComponent("Contexts", isDirectory: true).appendingPathComponent(key, isDirectory: true)
            if FileManager.default.fileExists(atPath: scoped.path) { contextID = key; self.root = scoped; canEdit = false }
            // Earlier pilot credentials must never silently move a local workspace into a team.
        }
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
        guard canBulkManage, contextID == "local" else { throw TeamError.message(L.t("Sicherungen nur im lokalen Bereich wiederherstellen. Kein Übertragen zwischen Teambereichen.", "Restore backups only in the local area. No transfer between teams.", "Przywracaj kopie tylko lokalnie, bez przenoszenia między zespołami.")) }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let restored = try Workspace.decode(Data(contentsOf: url))
        _ = try backup() // retain current snapshot locally before replacement
        data = restored; save()
    }
    func sync(discardLocal: Bool = false) async {
        guard !syncing else { return }
        let address = UserDefaults.standard.string(forKey: "teamURL") ?? ""
        guard let base = URL(string: address), base.scheme == "https", base.host != nil,
              base.user == nil, base.password == nil, base.query == nil, base.fragment == nil,
              let token = KeychainToken.read(), !token.isEmpty else {
            syncStatus = L.t("Kein Teamserver verbunden", "No team server connected", "Nie połączono serwera zespołu"); return
        }
        guard Self.scope(server: address, token: token) == contextID else { syncStatus = "Zugang zuerst verbinden / Connect access first"; return }
        let context = contextID
        syncing = true; defer { syncing = false }
        do {
            var get = URLRequest(url: base.appendingPathComponent("workspace")); get.timeoutInterval = 30
            get.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (bytes, response) = try await URLSession.shared.data(for: get)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw TeamError.message("Teamserver: Zugriff fehlgeschlagen / Access denied") }
            guard contextID == context else { throw ModelError.invalid }
            let remote = try JSONDecoder().decode(TeamSnapshot.self, from: bytes); try remote.workspace.validate()
            canEdit = http.value(forHTTPHeaderField: "X-Role") != "reader"
            if dirty && !discardLocal {
                guard canEdit else { throw TeamError.message("Nur Leserechte. Lokale Änderungen bleiben erhalten.") }
                guard remote.version == version else { throw TeamError.message("Versionskonflikt: lokale Daten bleiben erhalten. Sicherung exportieren; danach den Teamstand laden.") }
                var put = get; put.httpMethod = "PUT"; put.setValue("application/json", forHTTPHeaderField: "Content-Type")
                put.httpBody = try JSONEncoder().encode(TeamSnapshot(version: version, workspace: data))
                let (result, res) = try await URLSession.shared.data(for: put)
                guard (res as? HTTPURLResponse)?.statusCode == 200 else { throw TeamError.message("Team-Upload abgelehnt; lokale Daten bleiben erhalten (ggf. Versionskonflikt).") }
                let saved = try JSONDecoder().decode(TeamSnapshot.self, from: result); version = saved.version
                data.messages = saved.workspace.messages; try persistChatCache()
            } else {
                let bytes = try remote.workspace.encoded()
                try bytes.write(to: root.appendingPathComponent("workspace.json"), options: [.atomic, .completeFileProtection])
                data = remote.workspace; persistedData = data; version = remote.version
            }
            dirty = false; try saveMeta(); syncStatus = "✓ \(L.t("Synchronisiert", "Synced", "Zsynchronizowano")) · v\(version)"
        } catch { syncStatus = error.localizedDescription }
    }
    func loadTeamVersion() async {
        do { _ = try backup(); await sync(discardLocal: true) }
        catch { self.error = error.localizedDescription }
    }
}
enum TeamError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(s) = self { return s }; return nil }
}
enum KeychainToken {
    #if targetEnvironment(simulator)
    // Explicit test double: unsigned simulator apps cannot exercise device Keychain ACLs.
    static var testStorageEnabled = false
    static var testToken: String? = nil
    #endif
    static let service = "de.p1337.werkbeleg.team"
    static func read() -> String? {
        #if targetEnvironment(simulator)
        if testStorageEnabled { return testToken }
        #endif
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let bytes = item as? Data else { return nil }
        return String(data: bytes, encoding: .utf8)
    }
    static func save(_ token: String) throws {
        #if targetEnvironment(simulator)
        if testStorageEnabled { testToken = token.isEmpty ? nil : token; return }
        #endif
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(q as CFDictionary)
        guard !token.isEmpty else { return }
        var attributes = q; attributes[kSecValueData as String] = Data(token.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw TeamError.message("Token konnte nicht sicher gespeichert werden.") }
    }
}
