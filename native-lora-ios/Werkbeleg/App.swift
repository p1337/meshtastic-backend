import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

@main struct WerkbelegApp: App {
    @StateObject private var store = WorkStore()
    @AppStorage("language") private var language = "de"
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).tint(Color.orange)
                .environment(\.locale, Locale(identifier: language))
                .preferredColorScheme(.light)
                .task {
                    if ProcessInfo.processInfo.arguments.contains("--werkbeleg-smoke") { Smoke.run() }
                }
        }
    }
}
struct RootView: View {
    @EnvironmentObject var store: WorkStore
    @AppStorage("language") var language = "de"
    var body: some View {
        TabView {
            JobsView().tabItem { Label(L.t("Aufträge", "Jobs", "Zlecenia"), systemImage: "hammer.fill") }
            CustomersView().tabItem { Label(L.t("Kunden", "Customers", "Klienci"), systemImage: "person.2.fill") }
            SettingsView().tabItem { Label(L.t("Büro", "Office", "Biuro"), systemImage: "building.2.fill") }
        }
        .id(language)
        .disabled(store.syncing)
        .alert(L.t("Hinweis", "Notice", "Informacja"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
}
struct BrandHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(systemName: "checkmark.seal.fill").foregroundStyle(.orange); Text("WERKBELEG").font(.caption.bold()).tracking(3); Spacer(); Text("PILOT").font(.caption2.bold()).padding(6).background(.yellow, in: Capsule()).foregroundStyle(.black) }
            Text(L.t("Arbeit erledigt.\nSauber dokumentiert.", "Job done.\nClearly documented.", "Praca wykonana.\nDobrze udokumentowana.")).font(.largeTitle.bold()).foregroundStyle(.white)
            Text(L.t("Fotos. Sprache. Bericht.", "Photos. Voice. Report.", "Zdjęcia. Głos. Raport.")).foregroundStyle(.white.opacity(0.75))
        }.padding(22).background(.black, in: RoundedRectangle(cornerRadius: 24))
    }
}
struct JobsView: View {
    @EnvironmentObject var store: WorkStore
    @State private var add = false
    @State private var search = ""
    var body: some View {
        NavigationStack {
            List {
                Section { BrandHeader().listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
                Section(L.t("Deine Aufträge", "Your jobs", "Twoje zlecenia")) {
                    if store.data.jobs.isEmpty {
                        ContentUnavailableView(L.t("Ersten Auftrag anlegen", "Create your first job", "Dodaj pierwsze zlecenie"), systemImage: "hammer", description: Text(L.t("Kunden anlegen, Auftrag öffnen und die Arbeit festhalten.", "Add a customer, open a job and document your work.", "Dodaj klienta, otwórz zlecenie i dokumentuj pracę.")))
                    }
                    ForEach(store.data.jobs.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { job in
                        NavigationLink { JobView(jobID: job.id) } label: {
                            HStack {
                                Image(systemName: job.completed ? "checkmark.circle.fill" : "hammer.fill").foregroundStyle(job.completed ? Color.green : Color.orange)
                                VStack(alignment: .leading) {
                                    Text(job.title).font(.headline)
                                    Text(store.data.customers.first(where: { $0.id == job.customerID })?.name ?? "").font(.subheadline).foregroundStyle(.secondary)
                                    if !job.assignedTo.isEmpty { Text(job.assignedTo).font(.caption).foregroundStyle(.secondary) }
                                }; Spacer()
                                Text("\(store.data.reports.filter { $0.jobID == job.id }.count)").font(.caption.bold()).padding(7).background(.yellow.opacity(0.4), in: Circle())
                            }.padding(.vertical, 6)
                        }
                    }
                }
            }.navigationTitle("Werkbeleg").searchable(text: $search)
                .toolbar { Button { add = true } label: { Image(systemName: "plus.circle.fill") }.disabled(!store.canEdit) }
                .sheet(isPresented: $add) { NewJobView() }
        }
    }
}
struct CustomersView: View {
    @EnvironmentObject var store: WorkStore
    @State private var add = false
    @State private var selected: Customer? = nil
    var body: some View {
        NavigationStack {
            List {
                if store.data.customers.isEmpty { ContentUnavailableView(L.t("Noch keine Kunden", "No customers yet", "Brak klientów"), systemImage: "person.crop.circle.badge.plus") }
                ForEach(store.data.customers) { c in
                    Button { selected = c } label: { VStack(alignment: .leading, spacing: 5) { Text(c.name).font(.headline).foregroundStyle(.primary); Text(c.address).foregroundStyle(.primary); if !c.contact.isEmpty { Text(c.contact).foregroundStyle(.secondary) } } }
                }
            }.navigationTitle(L.t("Kunden", "Customers", "Klienci"))
                .toolbar { Button { add = true } label: { Image(systemName: "plus") }.disabled(!store.canEdit) }
                .sheet(isPresented: $add) { NewCustomerView() }
                .sheet(item: $selected) { NewCustomerView(editing: $0) }
        }
    }
}
struct NewCustomerView: View {
    var editing: Customer? = nil
    @EnvironmentObject var store: WorkStore
    @Environment(\.dismiss) var dismiss
    @State var name = ""
    @State var address = ""
    @State var contact = ""
    var body: some View {
        NavigationStack {
            Form { TextField(L.t("Name / Firma", "Name / company", "Nazwa / firma"), text: $name); TextField(L.t("Adresse", "Address", "Adres"), text: $address, axis: .vertical); TextField(L.t("Telefon / E-Mail", "Phone / email", "Telefon / e-mail"), text: $contact) }
                .navigationTitle(editing == nil ? L.t("Neuer Kunde", "New customer", "Nowy klient") : L.t("Kunde bearbeiten", "Edit customer", "Edytuj klienta"))
                .onAppear { if let c = editing { name = c.name; address = c.address; contact = c.contact } }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("Abbrechen", "Cancel", "Anuluj")) { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(L.t("Speichern", "Save", "Zapisz")) { let c = Customer(id: editing?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), address: address, contact: contact); if let i = store.data.customers.firstIndex(where: { $0.id == c.id }) { store.data.customers[i] = c } else { store.data.customers.append(c) }; if store.save() { dismiss() } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.canEdit) } }
        }
    }
}
struct NewJobView: View {
    var editing: Job? = nil
    @EnvironmentObject var store: WorkStore
    @Environment(\.dismiss) var dismiss
    @State var title = ""
    @State var address = ""
    @State var person = ""
    @State var customer: UUID? = nil
    @State var newCustomer = false
    var body: some View {
        NavigationStack {
            Form {
                Picker(L.t("Kunde", "Customer", "Klient"), selection: $customer) { Text(L.t("Bitte wählen", "Choose", "Wybierz")).tag(nil as UUID?); ForEach(store.data.customers) { Text($0.name).tag(Optional($0.id)) } }
                Button(L.t("Kunden hinzufügen", "Add customer", "Dodaj klienta")) { newCustomer = true }
                TextField(L.t("Auftrag / Baustelle", "Job / site", "Zlecenie / budowa"), text: $title)
                TextField(L.t("Baustellenadresse", "Site address", "Adres budowy"), text: $address, axis: .vertical)
                TextField(L.t("Zuständig (Name)", "Assigned to (name)", "Osoba odpowiedzialna"), text: $person)
            }.navigationTitle(editing == nil ? L.t("Neuer Auftrag", "New job", "Nowe zlecenie") : L.t("Auftrag bearbeiten", "Edit job", "Edytuj zlecenie"))
                .onAppear { if let j = editing { title = j.title; address = j.address; person = j.assignedTo; customer = j.customerID } }
                .sheet(isPresented: $newCustomer) { NewCustomerView() }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("Abbrechen", "Cancel", "Anuluj")) { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(L.t("Anlegen", "Create", "Utwórz")) {
                    if let c = customer { let j = Job(id: editing?.id ?? UUID(), customerID: c, title: title, address: address.isEmpty ? store.data.customers.first(where: { $0.id == c })?.address ?? "" : address, assignedTo: person, completed: editing?.completed ?? false); if let i = store.data.jobs.firstIndex(where: { $0.id == j.id }) { store.data.jobs[i] = j } else { store.data.jobs.append(j) }; if store.save() { dismiss() } }
                }.disabled(customer == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.canEdit) } }
        }
    }
}
struct JobView: View {
    @EnvironmentObject var store: WorkStore
    let jobID: UUID
    @State var add = false
    @State var editJob = false
    var job: Job? { store.data.jobs.first { $0.id == jobID } }
    var body: some View {
        List {
            if let j = job {
                Section { Text(j.address); if !j.assignedTo.isEmpty { Label(j.assignedTo, systemImage: "person") }
                    Button { if let i = store.data.jobs.firstIndex(where: { $0.id == jobID }) { store.data.jobs[i].completed.toggle(); store.save() } } label: { Label(j.completed ? L.t("Abgeschlossen", "Completed", "Zakończone") : L.t("Als erledigt markieren", "Mark completed", "Oznacz jako zakończone"), systemImage: j.completed ? "checkmark.circle.fill" : "circle") }.disabled(!store.canEdit)
                }
                Section(L.t("Berichte", "Reports", "Raporty")) {
                    ForEach(store.data.reports.filter { $0.jobID == jobID }.sorted { $0.createdAt > $1.createdAt }) { report in
                        NavigationLink { ReportDetail(reportID: report.id) } label: {
                            VStack(alignment: .leading) { Text(report.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.headline); Text(report.text.isEmpty ? L.t("Fotobericht", "Photo report", "Raport zdjęciowy") : report.text).lineLimit(2); Label("\(report.photos.count)", systemImage: "photo").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    Button { add = true } label: { Label(L.t("Bericht aufnehmen", "Create report", "Dodaj raport"), systemImage: "plus.circle.fill") }.disabled(!store.canEdit)
                }
            }
        }.navigationTitle(job?.title ?? "").sheet(isPresented: $add) { NewReportView(jobID: jobID) }
            .toolbar { Button { editJob = true } label: { Image(systemName: "pencil") }.disabled(!store.canEdit) }
            .sheet(isPresented: $editJob) { if let j = job { NewJobView(editing: j) } }
    }
}
struct NewReportView: View {
    @EnvironmentObject var store: WorkStore
    @Environment(\.dismiss) var dismiss
    @StateObject var capture = Capture()
    let jobID: UUID
    @State var bodyText = ""
    @State var weather = ""
    @AppStorage("author") var author = ""
    @State var photos: [Evidence] = []
    @State var selection: [PhotosPickerItem] = []
    @State var camera = false
    var body: some View {
        NavigationStack {
            Form {
                Section(L.t("Bericht", "Report", "Raport")) {
                    TextField(L.t("Dein Name", "Your name", "Twoje imię"), text: $author)
                    TextEditor(text: $bodyText).frame(minHeight: 140)
                    Button { Task { await capture.toggleRecording() } } label: { Label(capture.recording ? L.t("Aufnahme beenden", "Stop recording", "Zakończ nagrywanie") : L.t("Bericht einsprechen", "Dictate report", "Nagraj raport"), systemImage: capture.recording ? "stop.circle.fill" : "mic.fill") }
                    Text(L.t("Spracherkennung kann Apple-Server verwenden. Aufnahme bleibt im Bericht; erkannten Text prüfen.", "Speech recognition may use Apple servers. Audio stays in the report; review the transcription.", "Rozpoznawanie może korzystać z serwerów Apple. Dźwięk jest w raporcie; sprawdź tekst.")).font(.caption).foregroundStyle(.secondary)
                }
                Section(L.t("Fotos", "Photos", "Zdjęcia")) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) { Button { camera = true } label: { Label(L.t("Foto aufnehmen", "Take photo", "Zrób zdjęcie"), systemImage: "camera.fill") }.disabled(photos.count >= 12) }
                    PhotosPicker(selection: $selection, maxSelectionCount: max(1, 12 - photos.count), matching: .images) { Label(L.t("Fotos importieren", "Import photos", "Importuj zdjęcia"), systemImage: "photo.on.rectangle") }.disabled(photos.count >= 12)
                    ForEach(photos) { photo in
                        HStack { if let image = UIImage(data: photo.data) { Image(uiImage: image).resizable().scaledToFill().frame(width: 70, height: 60).clipped().cornerRadius(8) }; Text(photo.source == "camera" ? L.t("Kamera", "Camera", "Aparat") : L.t("Import", "Import", "Import")); Spacer(); Button(role: .destructive) { photos.removeAll { $0.id == photo.id } } label: { Image(systemName: "trash") } }
                    }
                    Text(L.t("Bis zu 12 Fotos, optimiert auf 1800 px. Importzeit und Aufnahmezeit werden unterschieden.", "Up to 12 photos, resized to 1800 px. Import and capture times are distinguished.", "Do 12 zdjęć, skalowanych do 1800 px. Czas importu odróżniamy od wykonania.")).font(.caption).foregroundStyle(.secondary)
                }
                Section(L.t("Ort & Wetter", "Location & weather", "Miejsce i pogoda")) {
                    Button { capture.locate() } label: { Label(L.t("Standort jetzt erfassen", "Capture location now", "Pobierz lokalizację"), systemImage: "location.fill") }
                    Text(capture.status).font(.caption)
                    TextField(L.t("Wetterbeobachtung (manuell)", "Weather observation (manual)", "Pogoda (ręcznie)"), text: $weather)
                    Text(L.t("Automatisches Wetter ist in dieser Testversion noch nicht verbunden.", "Automatic weather is not connected in this pilot.", "Automatyczna pogoda nie jest połączona w wersji testowej.")).font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle(L.t("Neuer Bericht", "New report", "Nowy raport"))
                .interactiveDismissDisabled(capture.recording)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("Abbrechen", "Cancel", "Anuluj")) { capture.stop(); dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(L.t("Speichern", "Save", "Zapisz")) {
                    let loc = capture.location
                    let r = Report(jobID: jobID, author: author, text: bodyText, photos: photos, audio: capture.audio, latitude: loc?.coordinate.latitude, longitude: loc?.coordinate.longitude, accuracy: loc?.horizontalAccuracy, locationAt: loc?.timestamp, weather: weather)
                    store.data.reports.append(r); if store.save() { capture.stop(); dismiss() }
                }.disabled(capture.recording || !store.canEdit || (bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photos.isEmpty && capture.audio == nil)) } }
                .onChange(of: capture.text) { _, text in if !text.isEmpty { bodyText += (bodyText.isEmpty ? "" : "\n") + text } }
                .onChange(of: selection) { _, items in Task {
                    for item in items {
                        if photos.count < 12, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data), let jpg = image.reportJPEG() { photos.append(Evidence(data: jpg, source: "imported")) }
                    }; selection = []
                } }
                .sheet(isPresented: $camera) { Camera { image in if let bytes = image.reportJPEG(), photos.count < 12 { photos.append(Evidence(data: bytes, source: "camera")) } } }
                .onDisappear { capture.stop() }
        }
    }
}
struct ReportDetail: View {
    @EnvironmentObject var store: WorkStore
    let reportID: UUID
    @State var pdf: URL? = nil
    @State var audioURL: URL? = nil
    @State var editing = false
    @State var revisedText = ""
    var report: Report? { store.data.reports.first { $0.id == reportID } }
    var body: some View {
        List {
            if let r = report {
                Section { Text(r.createdAt.formatted()); Text(r.author); Text(r.text)
                    Button(L.t("Text korrigieren", "Edit text", "Popraw tekst")) { revisedText = r.text; editing = true }.disabled(!store.canEdit)
                    if let lat = r.latitude, let lon = r.longitude { Text(String(format: "GPS %.6f, %.6f · ±%.0f m", lat, lon, r.accuracy ?? 0)).font(.caption) }
                    if !r.weather.isEmpty { Text(L.t("Wetter (manuell): ", "Weather (manual): ", "Pogoda (ręcznie): ") + r.weather) }
                }
                ForEach(r.photos) { p in if let img = UIImage(data: p.data) { Section { Image(uiImage: img).resizable().scaledToFit(); Text((p.source == "camera" ? L.t("Aufgenommen: ", "Captured: ", "Zdjęcie: ") : L.t("Importiert: ", "Imported: ", "Import: ")) + p.capturedAt.formatted()).font(.caption) } } }
                Section {
                    Button { makePDF(r) } label: { Label(L.t("PDF erstellen", "Create PDF", "Utwórz PDF"), systemImage: "doc.richtext") }
                    if let url = pdf { ShareLink(item: url) { Label(L.t("PDF teilen / in Dateien sichern", "Share PDF / Save to Files", "Udostępnij PDF / Zapisz w Plikach"), systemImage: "square.and.arrow.up") } }
                    if let url = audioURL { ShareLink(item: url) { Label(L.t("Sprachaufnahme öffnen / teilen", "Open / share recording", "Otwórz / udostępnij nagranie"), systemImage: "waveform") } }
                }
            }
        }.navigationTitle(L.t("Arbeitsbericht", "Work report", "Raport z prac"))
            .task { if let bytes = report?.audio { let u = FileManager.default.temporaryDirectory.appendingPathComponent(reportID.uuidString + ".m4a"); do { try bytes.write(to: u, options: [.atomic, .completeFileProtection]); audioURL = u } catch { store.error = error.localizedDescription } } }
            .sheet(isPresented: $editing) { NavigationStack { TextEditor(text: $revisedText).padding().navigationTitle(L.t("Text korrigieren", "Edit text", "Popraw tekst")).toolbar { Button(L.t("Speichern", "Save", "Zapisz")) { if let i = store.data.reports.firstIndex(where: { $0.id == reportID }) { store.data.reports[i].text = revisedText; if store.save() { pdf = nil; editing = false } } } } } }
    }
    func makePDF(_ r: Report) {
        guard let job = store.data.jobs.first(where: { $0.id == r.jobID }), let c = store.data.customers.first(where: { $0.id == job.customerID }) else { return }
        do { pdf = try ReportPDF.make(r, job: job, customer: c, company: store.data.company) } catch { store.error = error.localizedDescription }
    }
}
struct SettingsView: View {
    @EnvironmentObject var store: WorkStore
    @AppStorage("author") var author = ""
    @AppStorage("language") var language = "de"
    @AppStorage("teamURL") var teamURL = ""
    @State var company = ""
    @State var token = ""
    @State var backupURL: URL? = nil
    @State var importing = false
    @State var pendingImport: URL? = nil
    @State var replace = false
    @State var loadRemote = false
    var body: some View {
        NavigationStack {
            Form {
                Section(L.t("Dein Betrieb", "Your business", "Twoja firma")) {
                    TextField(L.t("Firmenname im PDF", "Company name on PDF", "Nazwa firmy w PDF"), text: $company)
                    Button(L.t("Firma speichern", "Save company", "Zapisz firmę")) { store.data.company = company; store.save() }.disabled(!store.canEdit)
                    TextField(L.t("Dein Name", "Your name", "Twoje imię"), text: $author)
                    Picker(L.t("Sprache", "Language", "Język"), selection: $language) { Text("Deutsch").tag("de"); Text("English").tag("en"); Text("Polski").tag("pl") }
                }
                Section(L.t("Sicherung & eigene Cloud", "Backup & your cloud", "Kopia i własna chmura")) {
                    Button(L.t("Vollständige Sicherung erstellen", "Create full backup", "Utwórz pełną kopię")) { do { backupURL = try store.backup() } catch { store.error = error.localizedDescription } }
                    if let url = backupURL { ShareLink(item: url) { Label(L.t("In Dateien / iCloud / Cloud sichern", "Save to Files / iCloud / cloud", "Zapisz w Plikach / iCloud / chmurze"), systemImage: "square.and.arrow.up") } }
                    Button(L.t("Sicherung wiederherstellen", "Restore backup", "Przywróć kopię")) { importing = true }.disabled(!store.canEdit)
                    Text(L.t("Enthält Kunden, Aufträge, Fotos und Audio. Wähle im Teilen-Menü ›In Dateien sichern‹ und deinen Cloudordner. Das ist eine Sicherung, keine automatische iCloud-Synchronisation.", "Includes customers, jobs, photos and audio. Choose Save to Files and your cloud folder. This is a backup, not automatic iCloud sync.", "Zawiera klientów, zlecenia, zdjęcia i dźwięk. Wybierz Zapisz w Plikach i folder chmury. To kopia, nie automatyczna synchronizacja iCloud.")).font(.caption)
                }
                Section(L.t("Team bis 20 Personen · Pilot", "Team up to 20 · Pilot", "Zespół do 20 osób · Pilot")) {
                    TextField("https://team.example.com", text: $teamURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField(L.t("Persönlicher Zugangstoken", "Personal access token", "Osobisty token dostępu"), text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(L.t("Zugang sicher speichern", "Save access securely", "Zapisz dostęp bezpiecznie")) { do { try KeychainToken.save(token); store.syncStatus = L.t("Token im Schlüsselbund gespeichert", "Token saved in Keychain", "Token zapisany w pęku kluczy") } catch { store.error = error.localizedDescription } }
                    Button { Task { await store.sync() } } label: { Label(store.syncing ? L.t("Synchronisiert …", "Syncing …", "Synchronizacja …") : L.t("Team synchronisieren", "Sync team", "Synchronizuj zespół"), systemImage: "arrow.triangle.2.circlepath") }.disabled(store.syncing)
                    Text(store.syncStatus.isEmpty ? L.t("Kein Teamserver verbunden. Daten liegen lokal auf diesem iPhone.", "No team server connected. Data is local to this iPhone.", "Nie połączono serwera. Dane są lokalne na tym iPhonie.") : store.syncStatus).font(.caption)
                    Button(L.t("Teamstand laden (lokalen Stand ersetzen)", "Load team version (replace local)", "Pobierz wersję zespołu (zastąp lokalną)"), role: .destructive) { loadRemote = true }.disabled(store.syncing)
                    Text(L.t("Gemeinsame Kunden, Aufträge und Berichte über eigenen HTTPS-Server. Lese-/Schreibrechte je Token. Manueller Abgleich, Versionskonflikte werden blockiert. Noch kein Server eingerichtet.", "Shared customers, jobs and reports on your own HTTPS server. Read/write roles per token. Manual sync; version conflicts are blocked. No server provisioned yet.", "Wspólni klienci, zlecenia i raporty na własnym serwerze HTTPS. Role odczytu/zapisu. Ręczna synchronizacja, konflikty wersji blokowane. Serwer nie jest jeszcze skonfigurowany.")).font(.caption)
                }
                Section("Werkbeleg 0.1 · Testversion") {
                    Text(L.t("Testphase ohne Abrechnung. Geplant: 9,99 €/Monat. Abo und App-Store-Veröffentlichung sind noch nicht aktiv.", "Free pilot. Planned: €9.99/month. Subscription and App Store launch are not active yet.", "Darmowy pilotaż. Plan: 9,99 €/mies. Subskrypcja i publikacja w App Store nie są jeszcze aktywne."))
                    Link(L.t("Neue Testversion installieren", "Install latest test version", "Zainstaluj nową wersję testową"), destination: URL(string: "https://p1337.github.io/meshtastic-backend/")!)
                }
            }.navigationTitle(L.t("Büro", "Office", "Biuro"))
                .onAppear { company = store.data.company; token = KeychainToken.read() ?? "" }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .json]) { result in
                    do { pendingImport = try result.get(); replace = true } catch { store.error = error.localizedDescription }
                }
                .confirmationDialog(L.t("Lokale Daten durch Sicherung ersetzen?", "Replace local data with backup?", "Zastąpić lokalne dane kopią?"), isPresented: $replace) {
                    Button(L.t("Ersetzen", "Replace", "Zastąp"), role: .destructive) { if let url = pendingImport { do { try store.restore(url) } catch { store.error = error.localizedDescription } } }
                }
                .confirmationDialog(L.t("Vorher Sicherung exportieren! Lokale Änderungen werden ersetzt.", "Export a backup first! Local changes will be replaced.", "Najpierw wyeksportuj kopię! Lokalne zmiany zostaną zastąpione."), isPresented: $loadRemote) {
                    Button(L.t("Teamstand laden", "Load team version", "Pobierz wersję zespołu"), role: .destructive) { Task { await store.loadTeamVersion() } }
                }
        }
    }
}

enum Smoke {
    @MainActor static func run() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var output: [String: Any] = ["product": "Werkbeleg", "passed": false]
        do {
            let store = WorkStore(root: folder)
            let c = Customer(name: "SIMULATOR TEST", address: "Teststraße 1")
            let j = Job(customerID: c.id, title: "Testauftrag")
            let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { ctx in UIColor.orange.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100)) }
            let pixelFormat = UIGraphicsImageRendererFormat(); pixelFormat.scale = 1
            let wideImage = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 20), format: pixelFormat).image { ctx in UIColor.orange.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 2000, height: 20)) }
            guard let resizedData = wideImage.reportJPEG(), let resized = UIImage(data: resizedData),
                  resized.cgImage?.width == 1800, resized.cgImage?.height == 18 else { throw TeamError.message("Retina resize exceeded the 1800px limit") }
            output["photoPixelSizeVerified"] = true
            let r = Report(jobID: j.id, author: "Synthetic test", text: String(repeating: "Prüfung der PDF-Paginierung.\n", count: 150), photos: [Evidence(data: image.jpegData(compressionQuality: 0.8)!, source: "camera")])
            store.data = Workspace(company: "Testbetrieb", customers: [c], jobs: [j], reports: [r]); store.save()
            guard store.error == nil else { throw TeamError.message(store.error!) }
            let restored = WorkStore(root: folder); guard restored.data == store.data else { throw ModelError.invalid }
            let backup = try store.backup(); let decoded = try Workspace.decode(Data(contentsOf: backup)); guard decoded == store.data else { throw ModelError.invalid }
            let pdf = try ReportPDF.make(r, job: j, customer: c, company: "Testbetrieb")
            guard let document = CGPDFDocument(pdf as CFURL), document.numberOfPages >= 3 else { throw ModelError.invalid }
            output["passed"] = true; output["pdfPages"] = document.numberOfPages; output["persistence"] = true; output["backupRoundTrip"] = true
            output["testSource"] = "synthetic"; output["cameraOrMicrophoneTested"] = false; output["teamServerConnected"] = false
        } catch { output["error"] = error.localizedDescription }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]).write(to: docs.appendingPathComponent("Werkbeleg-Smoke.json"), options: .atomic)
        try? FileManager.default.removeItem(at: folder)
    }
}
