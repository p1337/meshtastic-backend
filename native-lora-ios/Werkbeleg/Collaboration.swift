import SwiftUI

extension WorkStore {
    func teamRequest(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard let base = URL(string: UserDefaults.standard.string(forKey: "teamURL") ?? ""), base.scheme == "https", base.host != nil,
              base.user == nil, base.password == nil, base.query == nil, base.fragment == nil,
              let token = KeychainToken.read(), !token.isEmpty else { throw TeamError.message(L.t("Bitte zuerst einen Teamserver verbinden.", "Connect a team server first.", "Najpierw połącz serwer zespołu.")) }
        let context = contextID
        guard Self.scope(server: base.absoluteString, token: token) == context else { throw ModelError.invalid }
        let url = URL(string: base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + path)!
        var req = URLRequest(url: url); req.timeoutInterval = 20; req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body); req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (bytes, response) = try await URLSession.shared.data(for: req)
        guard contextID == context else { throw ModelError.invalid }
        guard let code = (response as? HTTPURLResponse)?.statusCode, (200...299).contains(code) else {
            let message = (try? JSONSerialization.jsonObject(with: bytes) as? [String: Any])?["error"] as? String
            throw TeamError.message(message ?? "Teamserver nicht erreichbar / Team server unavailable")
        }
        return bytes
    }
    func persistChatCache() throws {
        let bytes = try data.encoded()
        guard bytes.count <= 30 * 1024 * 1024 else { throw ModelError.tooLarge }
        try bytes.write(to: root.appendingPathComponent("workspace.json"), options: [.atomic, .completeFileProtection]); persistedData = data
    }
    func refreshTeam() async throws {
        let bytes = try await teamRequest("team")
        teamInfo = try JSONDecoder().decode(TeamInfo.self, from: bytes)
        canEdit = teamInfo?.role != "reader"
    }
    func loadMessages(_ project: UUID) async throws {
        let bytes = try await teamRequest("messages?project=" + project.uuidString)
        let messages = try JSONDecoder().decode([ProjectMessage].self, from: bytes)
        guard messages.allSatisfy({ $0.jobID == project }) else { throw ModelError.invalid }
        let previous = data.messages
        data.messages.removeAll { $0.jobID == project }; data.messages.append(contentsOf: messages)
        do { try persistChatCache() } catch { data.messages = previous; throw error }
    }
    func sendMessage(_ project: UUID, text: String, id: UUID) async throws {
        let context = contextID
        if dirty { await sync(); guard !dirty, contextID == context else { throw TeamError.message(syncStatus) } }
        _ = try await teamRequest("messages", method: "POST", body: ["id": id.uuidString, "jobID": project.uuidString, "text": text])
        try await loadMessages(project)
    }
    func createInvite(name: String, reader: Bool) async throws -> URL {
        guard teamInfo?.recipientBoundInvites == true else { throw TeamError.message(L.t("Personengebundene Einladungen werden nach Einrichtung des sicheren Cloudzugangs freigeschaltet.", "Recipient-bound invitations are enabled after secure cloud access is configured.", "Zaproszenia przypisane do osoby zostaną włączone po konfiguracji bezpiecznej chmury.")) }
        let bytes = try await teamRequest("invites", method: "POST", body: ["name": name, "role": reader ? "reader" : "editor"])
        guard let response = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], let code = response["code"] as? String else { throw ModelError.invalid }
        var link = URLComponents(); link.scheme = "werkbeleg"; link.host = "join"
        link.queryItems = [URLQueryItem(name: "server", value: UserDefaults.standard.string(forKey: "teamURL")), URLQueryItem(name: "code", value: code)]
        var web = URLComponents(string: "https://p1337.github.io/meshtastic-backend/join.html")!
        var values = URLComponents(); values.queryItems = link.queryItems
        web.percentEncodedFragment = values.percentEncodedQuery
        guard let url = web.url else { throw ModelError.invalid }; return url
    }
    func receiveInvitation(_ url: URL) {
        guard url.scheme == "werkbeleg", url.host == "join", let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let address = parts.queryItems?.first(where: { $0.name == "server" })?.value,
              let base = URL(string: address), base.scheme == "https", base.host != nil, base.user == nil, base.password == nil,
              base.query == nil, base.fragment == nil,
              let code = parts.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty, code.count < 512 else { return }
        invitation = InvitationContext(server: base, code: code)
    }
    func acceptInvitation(_ invite: InvitationContext) async throws {
        // The old anonymous /join endpoint cannot prove the recipient. Fail closed until
        // the hosted authenticated-recipient flow is connected, rather than grant a bearer-link team.
        throw TeamError.message(L.t("Dieser Pilot kann Einladungen noch nicht personengebunden prüfen. Sicheren Cloudzugang zuerst einrichten.", "This pilot cannot verify invitation recipients yet. Configure secure cloud access first.", "Pilot nie potrafi jeszcze zweryfikować odbiorcy. Najpierw skonfiguruj bezpieczną chmurę."))
    }

}

struct ProjectChatView: View {
    @EnvironmentObject var store: WorkStore
    let jobID: UUID
    @State private var text = ""
    @State private var sending = false
    @State private var outgoing = UUID()
    @State private var status = ""
    var body: some View {
        VStack(spacing: 0) {
            List {
                if store.data.messages.filter({ $0.jobID == jobID }).isEmpty { Text(L.t("Noch keine Projektnachrichten", "No project messages yet", "Brak wiadomości w projekcie")).foregroundStyle(.secondary) }
                ForEach(store.data.messages.filter { $0.jobID == jobID }.sorted { $0.createdAt < $1.createdAt }) { m in
                    VStack(alignment: .leading, spacing: 7) { HStack { Text(m.author).font(.subheadline.bold()); Spacer(); Text(m.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }; Text(m.text).textSelection(.enabled) }.padding(.vertical, 5)
                }
            }
            Text(status).font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            HStack(alignment: .bottom) {
                TextField(L.t("Nachricht im Projekt", "Message in project", "Wiadomość w projekcie"), text: $text, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder)
                Button { Task { sending = true; defer { sending = false }; do { try await store.sendMessage(jobID, text: text, id: outgoing); text = ""; outgoing = UUID(); status = "" } catch { status = error.localizedDescription } } } label: { Image(systemName: "arrow.up.circle.fill").font(.largeTitle) }.disabled(sending || !store.canEdit || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 4000)
            }.padding()
        }.navigationTitle(L.t("Projektchat", "Project chat", "Czat projektu"))
            .toolbar { Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") } }
            .task { await refresh(); while !Task.isCancelled { do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { break }; await refresh() } }
    }
    func refresh() async {
        do { try await store.loadMessages(jobID); status = L.t("Teamserver · Abruf alle 10 Sekunden", "Team server · refresh every 10 seconds", "Serwer · odświeżanie co 10 sekund") }
        catch { status = error.localizedDescription }
    }
}

struct TeamView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject var store: WorkStore
    @State private var name = ""
    @State private var reader = false
    @State private var inviteLink: URL? = nil
    @State private var busy = false
    @State private var status = ""
    var body: some View {
        Form {
            Section(L.t("Team", "Team", "Zespół")) {
                if let team = store.teamInfo {
                    Text("\(team.memberCount) / \(team.seatLimit) " + L.t("Personen", "people", "osób"))
                    Text("\(team.pendingInvites) " + L.t("offene Einladungen", "pending invitations", "oczekujących zaproszeń")).font(.caption)
                    ForEach(team.members) { m in HStack { Text(m.name); Spacer(); Text(m.role).font(.caption).foregroundStyle(.secondary) } }
                } else { Text(L.t("Zuerst Teamserver verbinden. Die lokale App ist noch kein gemeinsamer Teamzugang.", "Connect a team server first. Local use does not create a shared team.", "Najpierw połącz serwer. Tryb lokalny nie tworzy wspólnego zespołu.")) }
                Button(L.t("Team laden", "Load team", "Wczytaj zespół")) { Task { do { try await store.refreshTeam(); status = "" } catch { status = error.localizedDescription } } }
            }
            Section(L.t("Person einladen", "Invite a person", "Zaproś osobę")) {
                if store.teamInfo?.recipientBoundInvites != true { Label(L.t("Sichere Einladungen folgen mit dem verbundenen Cloudzugang. Der alte Pilot-Link bleibt gesperrt.", "Secure invitations require the connected cloud service. Legacy pilot links are disabled.", "Bezpieczne zaproszenia wymagają połączonej chmury. Stare linki pilota są zablokowane."), systemImage: "lock.shield").font(.subheadline) }
                TextField(L.t("Name der Person", "Person's name", "Imię osoby"), text: $name)
                Toggle(L.t("Nur lesen", "Read only", "Tylko odczyt"), isOn: $reader)
                Button(L.t("Einladungslink erstellen", "Create invitation link", "Utwórz link zaproszenia")) { Task { busy = true; defer { busy = false }; do { inviteLink = try await store.createInvite(name: name, reader: reader); try await store.refreshTeam(); status = "" } catch { status = error.localizedDescription } } }.disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.teamInfo?.role != "admin" || store.teamInfo?.recipientBoundInvites != true)
                if let url = inviteLink {
                    Button { var wa = URLComponents(string: "https://wa.me/")!; wa.queryItems = [URLQueryItem(name: "text", value: L.t("Komm in unser Werkbeleg-Team: ", "Join our Werkbeleg team: ", "Dołącz do naszego zespołu Werkbeleg: ") + url.absoluteString)]; if let link = wa.url { openURL(link) } } label: { Label(L.t("Per WhatsApp einladen", "Invite via WhatsApp", "Zaproś przez WhatsApp"), systemImage: "message.fill") }
                    ShareLink(item: url) { Label(L.t("Einladung anders teilen", "Share invitation another way", "Udostępnij inaczej"), systemImage: "square.and.arrow.up") }
                }
                Text(L.t("Nur Inhaber/Admin. Der Link gilt 48 Stunden und kann einmal verwendet werden. Zuerst die App installieren, dann den Link öffnen. Offene Einladungen belegen einen Platz.", "Owner/admin only. Link expires in 48 hours and can be used once. Install the app before opening it. Pending invitations reserve a seat.", "Tylko właściciel/admin. Link ważny 48 godzin i jednorazowy. Najpierw zainstaluj aplikację. Oczekujące zaproszenia zajmują miejsce.")).font(.caption)
            }
            if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
            NavigationLink { PlansView() } label: { Label(L.t("Pakete & Teamgröße", "Plans & team size", "Pakiety i wielkość zespołu"), systemImage: "person.3.fill") }
        }.navigationTitle(L.t("Team & Einladungen", "Team & invitations", "Zespół i zaproszenia"))
            .task { do { try await store.refreshTeam() } catch { status = error.localizedDescription } }
    }
}
struct InvitationView: View {
    @EnvironmentObject var store: WorkStore
    let invite: InvitationContext
    @State private var busy = false
    @State private var error = ""
    var body: some View {
        NavigationStack { Form {
            Section(L.t("Teameinladung", "Team invitation", "Zaproszenie do zespołu")) {
                Text(invite.server.host ?? "").font(.headline)
                Text(L.t("Du verbindest dich mit diesem Server. Der bisherige Bereich bleibt getrennt erhalten. Der neue Zugang öffnet einen eigenen lokalen Datenbereich.", "You will connect to this server. Existing data remains separate. The new access opens its own local data area.", "Połączysz się z tym serwerem. Dotychczasowe dane pozostaną oddzielnie. Nowy dostęp otwiera własny obszar lokalny."))
                Button(L.t("Einladung annehmen", "Accept invitation", "Przyjmij zaproszenie")) { Task { busy = true; defer { busy = false }; do { try await store.acceptInvitation(invite) } catch { self.error = error.localizedDescription } } }.disabled(busy)
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }
        }.navigationTitle("Werkbeleg").toolbar { Button(L.t("Schließen", "Close", "Zamknij")) { store.invitation = nil }.disabled(busy) } }
    }
}
struct PlansView: View {
    var body: some View {
        List {
            Section { Text(L.t("Ein Betrieb. Ein Monatspreis.", "One business. One monthly price.", "Jedna firma. Jedna cena miesięczna.")).font(.title2.bold()) }
            ForEach([5, 10, 20], id: \.self) { seats in
                Section {
                    HStack { VStack(alignment: .leading) { Text("Werkbeleg \(seats)").font(.title2.bold()); Text(L.t("Bis zu \(seats) Personen inklusive Inhaber", "Up to \(seats) people including owner", "Do \(seats) osób łącznie z właścicielem")).font(.subheadline) }; Spacer(); Text(seats == 5 ? "9,99 €" : seats == 10 ? "14,99 €" : "19,99 €").font(.headline).foregroundStyle(.orange) }
                    Text(L.t("pro Monat / Betrieb", "per month / business", "miesięcznie / firma")).font(.caption)
                    Label(L.t("Projekte · Fotos · Sprache · PDF · Projektchat", "Projects · photos · voice · PDF · project chat", "Projekty · zdjęcia · głos · PDF · czat"), systemImage: "checkmark.circle.fill")
                }
            }
            Section { Text(L.t("Preismodell für die geplante Veröffentlichung. Im Pilot keine Käufe und keine Abrechnung. Teamgröße wird am eigenen Server freigeschaltet; App-Store-Abos sind noch nicht eingerichtet.", "Pricing for the planned launch. No purchases or billing during the pilot. Seats are configured on your server; App Store subscriptions are not configured yet.", "Cennik planowanej publikacji. Brak zakupów i opłat w pilotażu. Liczba miejsc ustawiana na serwerze; subskrypcje App Store nie są skonfigurowane.")).font(.caption) }
        }.navigationTitle(L.t("Pakete", "Plans", "Pakiety"))
    }
}
