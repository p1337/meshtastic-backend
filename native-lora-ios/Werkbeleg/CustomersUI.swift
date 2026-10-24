import SwiftUI
import UniformTypeIdentifiers

extension WorkStore {
    var lastImport: ImportReceipt? { try? JSONDecoder().decode(ImportReceipt.self, from: Data(contentsOf: root.appendingPathComponent("last-import.json"))) }
    func importCustomers(_ customers: [Customer], source: String, context: String, reviewed: [Customer]) throws -> ImportReceipt {
        guard context == contextID, canEdit, canBulkManage, reviewed == data.customers, !customers.isEmpty else { throw TeamError.message(L.t("Kundenbestand oder Berechtigung geändert. Bitte Vorschau neu laden.", "Customers or permissions changed. Reload the preview.", "Dane lub uprawnienia zmienione. Odśwież podgląd.")) }
        var receipt = ImportReceipt(source: source, customers: customers)
        for i in receipt.customers.indices { receipt.customers[i].details.importID = receipt.id }
        let url = root.appendingPathComponent("last-import.json")
        let previous = try? Data(contentsOf: url)
        try JSONEncoder().encode(receipt).write(to: url, options: [.atomic, .completeFileProtection])
        data.customers.append(contentsOf: receipt.customers)
        guard save() else {
            if let previous { try? previous.write(to: url, options: [.atomic, .completeFileProtection]) } else { try? FileManager.default.removeItem(at: url) }
            throw TeamError.message(error ?? "Speichern fehlgeschlagen / Save failed")
        }
        return receipt
    }
    func undoLastImport() throws -> Int {
        guard canEdit, canBulkManage, let receipt = lastImport else { throw ModelError.invalid }
        let removable = ImportUndo.removable(receipt: receipt, workspace: data)
        guard !removable.isEmpty else { throw TeamError.message(L.t("Diese Kunden wurden inzwischen geändert oder in Projekten verwendet. Sie bleiben erhalten.", "These customers have been changed or used in projects and are retained.", "Klienci zostali zmienieni lub użyci w projektach i zostają zachowani.")) }
        data.customers.removeAll { removable.contains($0.id) }
        guard save() else { throw TeamError.message(error ?? "Save failed") }
        let remaining = ImportReceipt(id: receipt.id, createdAt: receipt.createdAt, source: receipt.source, customers: receipt.customers.filter { !removable.contains($0.id) })
        try JSONEncoder().encode(remaining).write(to: root.appendingPathComponent("last-import.json"), options: [.atomic, .completeFileProtection])
        return removable.count
    }
}

struct CustomersView: View {
    @EnvironmentObject var store: WorkStore
    @State private var add = false
    @State private var importing = false
    @State private var selected: Customer? = nil
    @State private var search = ""
    @State private var undo = false
    @State private var notice = ""
    var filtered: [Customer] { store.data.customers.filter { search.isEmpty || [$0.name, $0.address, $0.contact, $0.details.externalID, $0.details.taxID].joined(separator: " ").localizedCaseInsensitiveContains(search) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { importing = true } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "square.and.arrow.down.fill").font(.title2).foregroundStyle(.orange).frame(width: 42, height: 48).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 4) { Text(L.t("Kunden übernehmen", "Import customers", "Importuj klientów")).font(.headline).foregroundStyle(.primary); Text("CSV · Excel · vCard").font(.subheadline).foregroundStyle(.secondary) }
                            Spacer(); Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                        }.padding(.vertical, 5)
                    }.disabled(!store.canEdit || !store.canBulkManage)
                } footer: { Text(store.contextID == "local" ? L.t("Privater Bereich auf diesem iPhone", "Private area on this iPhone", "Prywatny obszar na tym iPhonie") : L.t("Nur der aktuell verbundene Teambereich", "Current connected team only", "Tylko aktualnie połączony zespół")) }
                Section("\(filtered.count) " + L.t("Kunden", "customers", "klientów")) {
                    if filtered.isEmpty { ContentUnavailableView(search.isEmpty ? L.t("Deine Kunden. Ein Ort.", "Your customers. One place.", "Twoi klienci. Jedno miejsce.") : L.t("Keine Treffer", "No results", "Brak wyników"), systemImage: "person.crop.rectangle.stack", description: Text(L.t("Liste übernehmen oder ersten Kunden anlegen.", "Import a list or add your first customer.", "Zaimportuj listę lub dodaj pierwszego klienta."))) }
                    ForEach(filtered) { c in
                        NavigationLink { CustomerDetailView(customerID: c.id) } label: {
                            HStack(spacing: 12) {
                                Text(String(c.name.prefix(1)).uppercased()).font(.headline).frame(width: 40, height: 40).background(Color.yellow.opacity(0.25), in: Circle())
                                VStack(alignment: .leading, spacing: 4) { Text(c.name).font(.headline); if !c.address.isEmpty { Text(c.address.replacingOccurrences(of: "\n", with: ", ")).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }; if !c.details.externalID.isEmpty { Text(c.details.externalID).font(.caption).foregroundStyle(.secondary) } }
                            }.padding(.vertical, 4)
                        }
                    }
                }
                if let last = store.lastImport, !last.customers.isEmpty, store.canBulkManage {
                    Section {
                        Label("\(last.customers.count) · \(last.source)", systemImage: "checkmark.circle").font(.subheadline)
                        Button(L.t("Letzte Übernahme rückgängig", "Undo last import", "Cofnij ostatni import"), role: .destructive) { undo = true }.disabled(!store.canEdit)
                    } footer: { Text(L.t("Geänderte oder bereits in Projekten verwendete Kunden bleiben erhalten.", "Customers changed or used in projects are retained.", "Zmienieni klienci i klienci użyci w projektach zostają zachowani.")) }
                }
            }.navigationTitle(L.t("Kunden", "Customers", "Klienci"))
                .searchable(text: $search, prompt: L.t("Name, Ort oder Kundennummer", "Name, city or customer number", "Nazwa, miasto lub numer klienta"))
                .toolbar { Button { add = true } label: { Image(systemName: "plus.circle.fill") }.disabled(!store.canEdit) }
                .sheet(isPresented: $add) { NewCustomerView() }
                .sheet(isPresented: $importing) { CustomerImportView() }
                .confirmationDialog(L.t("Letzte Übernahme rückgängig machen?", "Undo last import?", "Cofnąć ostatni import?"), isPresented: $undo, titleVisibility: .visible) { Button(L.t("Unveränderte Kunden entfernen", "Remove unchanged customers", "Usuń niezmienionych klientów"), role: .destructive) { do { let count = try store.undoLastImport(); notice = "\(count) " + L.t("Kunden entfernt. Andere Daten bleiben erhalten.", "customers removed. Other data retained.", "klientów usuniętych. Pozostałe dane zachowane.") } catch { notice = error.localizedDescription } } }
                .alert(L.t("Übernahme", "Import", "Import"), isPresented: Binding(get: { !notice.isEmpty }, set: { if !$0 { notice = "" } })) { Button("OK") { notice = "" } } message: { Text(notice) }
                .task { if store.contextID != "local" { try? await store.refreshTeam() } }
        }
    }
}
struct CustomerDetailView: View {
    @EnvironmentObject var store: WorkStore
    let customerID: UUID
    @State private var editing = false
    var customer: Customer? { store.data.customers.first { $0.id == customerID } }
    var body: some View {
        List {
            if let c = customer {
                Section { Text(c.name).font(.title2.bold()); if !c.details.externalID.isEmpty { LabeledContent(L.t("Kundennummer", "Customer number", "Numer klienta"), value: c.details.externalID) }; if !c.address.isEmpty { Label(c.address, systemImage: "mappin.and.ellipse").textSelection(.enabled) } }
                if !c.contact.isEmpty { Section(L.t("Kontakt", "Contact", "Kontakt")) { Text(c.contact).textSelection(.enabled) } }
                if !c.details.notes.isEmpty { Section(L.t("Notizen", "Notes", "Notatki")) { Text(c.details.notes).textSelection(.enabled) } }
                if !c.details.taxID.isEmpty { Section { LabeledContent("USt-ID / UID / NIP", value: c.details.taxID) } }
                Section(L.t("Projekte", "Projects", "Projekty")) {
                    let jobs = store.data.jobs.filter { $0.customerID == c.id }
                    if jobs.isEmpty { Text(L.t("Noch keine Projekte", "No projects yet", "Brak projektów")).foregroundStyle(.secondary) }
                    ForEach(jobs) { job in NavigationLink(job.title) { JobView(jobID: job.id) } }
                }
                if !c.details.source.isEmpty { Section { LabeledContent(L.t("Übernommen aus", "Imported from", "Zaimportowano z"), value: c.details.source) } }
            }
        }.navigationTitle(L.t("Kundendetails", "Customer details", "Szczegóły klienta"))
            .toolbar { Button(L.t("Bearbeiten", "Edit", "Edytuj")) { editing = true }.disabled(!store.canEdit) }
            .sheet(isPresented: $editing) { if let c = customer { NewCustomerView(editing: c) } }
    }
}
struct NewCustomerView: View {
    var editing: Customer? = nil
    @EnvironmentObject var store: WorkStore
    @Environment(\.dismiss) var dismiss
    @State private var customer = Customer(name: "")
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField(L.t("Name / Firma", "Name / company", "Nazwa / firma"), text: $customer.name); TextField(L.t("Kundennummer (optional)", "Customer number (optional)", "Numer klienta (opcjonalnie)"), text: $customer.details.externalID) }
                Section(L.t("Adresse", "Address", "Adres")) { TextField(L.t("Straße / Hausnummer", "Street / number", "Ulica / numer"), text: $customer.details.street); TextField(L.t("Postleitzahl", "Postal code", "Kod pocztowy"), text: $customer.details.postalCode); TextField(L.t("Ort", "City", "Miejscowość"), text: $customer.details.city); TextField(L.t("Land", "Country", "Kraj"), text: $customer.details.country); if !customer.address.isEmpty && customer.details.street.isEmpty { TextField(L.t("Bisherige Adresse", "Existing address", "Dotychczasowy adres"), text: $customer.address, axis: .vertical) } }
                Section(L.t("Kontakt", "Contact", "Kontakt")) {
                    TextField(L.t("Ansprechpartner", "Contact person", "Osoba kontaktowa"), text: $customer.details.person)
                    TextField("E-Mail", text: $customer.details.email, axis: .vertical).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField(L.t("Telefon", "Phone", "Telefon"), text: $customer.details.phone, axis: .vertical).keyboardType(.phonePad)
                    if !customer.contact.isEmpty && customer.details.email.isEmpty && customer.details.phone.isEmpty { TextField(L.t("Bisheriger Kontakt", "Existing contact", "Dotychczasowy kontakt"), text: $customer.contact, axis: .vertical) }
                }
                Section(L.t("Weitere Angaben", "More details", "Więcej danych")) { TextField("USt-ID / UID / NIP", text: $customer.details.taxID); TextField(L.t("Notizen", "Notes", "Notatki"), text: $customer.details.notes, axis: .vertical).lineLimit(3...8) }
            }.navigationTitle(editing == nil ? L.t("Neuer Kunde", "New customer", "Nowy klient") : L.t("Kunde bearbeiten", "Edit customer", "Edytuj klienta"))
                .onAppear { if let editing { customer = editing } }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L.t("Abbrechen", "Cancel", "Anuluj")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(L.t("Speichern", "Save", "Zapisz")) {
                        customer.name = customer.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let d = customer.details
                        let address = [d.street, [d.postalCode, d.city].filter { !$0.isEmpty }.joined(separator: " "), d.country].filter { !$0.isEmpty }.joined(separator: "\n")
                        if !address.isEmpty || (editing?.details.street.isEmpty == false || editing?.details.city.isEmpty == false || editing?.details.postalCode.isEmpty == false) { customer.address = address }
                        let contact = [d.person, d.email, d.phone].filter { !$0.isEmpty }.joined(separator: "\n")
                        if !contact.isEmpty || (editing?.details.email.isEmpty == false || editing?.details.phone.isEmpty == false || editing?.details.person.isEmpty == false) { customer.contact = contact }
                        if let i = store.data.customers.firstIndex(where: { $0.id == customer.id }) { store.data.customers[i] = customer } else { store.data.customers.append(customer) }
                        if store.save() { dismiss() }
                    }.disabled(customer.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || customer.name.count > 160 || !store.canEdit) }
                }
        }
    }
}

struct CustomerImportView: View {
    @EnvironmentObject var store: WorkStore
    @Environment(\.dismiss) private var dismiss
    @State private var stage = 0
    @State private var choose = false
    @State private var busy = false
    @State private var error = ""
    @State private var filename = ""
    @State private var fileData: Data? = nil
    @State private var encoding = "utf8"
    @State private var tables: [ContactTable] = []
    @State private var sheet = 0
    @State private var mapping: [ContactField] = []
    @State private var source = ""
    @State private var candidates: [ImportCandidate] = []
    @State private var selected: Set<Int> = []
    @State private var reviewed: [Customer] = []
    @State private var context = ""
    @State private var count = 0
    var table: ContactTable? { tables.indices.contains(sheet) ? tables[sheet] : nil }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: stage == 3 ? "checkmark.circle.fill" : "person.crop.rectangle.stack.fill").font(.largeTitle).foregroundStyle(stage == 3 ? Color.green : Color.orange)
                        Text(title).font(.title2.bold())
                        Text(subtitle).foregroundStyle(.secondary)
                        if stage < 3 { ProgressView(value: Double(stage+1), total: 3).tint(.orange) }
                    }.padding(.vertical, 10)
                }
                if stage == 0 { startSection }
                if stage == 1 { mappingSection }
                if stage == 2 { reviewSection }
                if stage == 3 { Section { Text("\(count) " + L.t("Kunden übernommen", "customers imported", "klientów zaimportowanych")).font(.headline); Text(L.t("Bestehende Kunden wurden nicht überschrieben. Die letzte Übernahme kannst du in der Kundenliste rückgängig machen.", "Existing customers were not overwritten. Undo the last import from the customer list.", "Istniejący klienci nie zostali nadpisani. Ostatni import możesz cofnąć na liście klientów.")); Button(L.t("Fertig", "Done", "Gotowe")) { dismiss() }.buttonStyle(.borderedProminent) } }
                if !error.isEmpty { Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red) } }
                if busy { Section { ProgressView(L.t("Datei wird geprüft …", "Checking file …", "Sprawdzanie pliku …")) } }
            }.navigationTitle(L.t("Kunden übernehmen", "Import customers", "Importuj klientów"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(stage == 0 || stage == 3 ? L.t("Schließen", "Close", "Zamknij") : L.t("Zurück", "Back", "Wstecz")) { if stage == 0 || stage == 3 { dismiss() } else { stage -= 1; error = "" } }.disabled(busy) } }
                .fileImporter(isPresented: $choose, allowedContentTypes: [.data]) { result in
                    do {
                        let url = try result.get(), access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? ContactImporter.fileLimit+1) <= ContactImporter.fileLimit else { throw ModelError.tooLarge }
                        fileData = try Data(contentsOf: url); filename = url.lastPathComponent
                        source = url.deletingPathExtension().lastPathComponent; parse()
                    } catch { if (error as NSError).code != NSUserCancelledError { self.error = error.localizedDescription } }
                }
                .interactiveDismissDisabled(busy)
                .onAppear { context = store.contextID }
        }
    }
    var title: String { stage == 0 ? L.t("Deine Kunden ziehen ein.", "Bring your customers along.", "Przenieś swoich klientów.") : stage == 1 ? L.t("Passt alles zusammen?", "Does everything match?", "Czy wszystko pasuje?") : stage == 2 ? L.t("Ein letzter Blick.", "One last look.", "Ostatnie spojrzenie.") : L.t("Alles an seinem Platz.", "Everything in place.", "Wszystko na miejscu.") }
    var subtitle: String { stage == 0 ? L.t("Datei auswählen. Prüfen. Übernehmen.", "Choose a file. Review. Import.", "Wybierz plik. Sprawdź. Importuj.") : stage == 1 ? L.t("Wir schlagen passende Felder vor. Du entscheidest.", "We suggest matching fields. You decide.", "Proponujemy pasujące pola. Ty decydujesz.") : stage == 2 ? L.t("Mögliche Dubletten sind abgewählt. Es wird nichts überschrieben.", "Possible duplicates are deselected. Nothing is overwritten.", "Możliwe duplikaty są odznaczone. Nic nie nadpisujemy.") : L.t("Dein Kundenbestand ist bereit.", "Your customer list is ready.", "Lista klientów jest gotowa.") }
    var startSection: some View {
        Section {
            Button { choose = true } label: { Label(L.t("Datei auswählen", "Choose file", "Wybierz plik"), systemImage: "folder.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8) }.buttonStyle(.borderedProminent).disabled(busy)
            Text(L.t("CSV, Excel (.xlsx) oder vCard (.vcf) – aus Dateien, iCloud oder einem verbundenen Cloudordner. Bis zu 10.000 Kunden und 10 MB pro Datei.", "CSV, Excel (.xlsx) or vCard (.vcf) from Files, iCloud or a connected cloud folder. Up to 10,000 customers and 10 MB per file.", "CSV, Excel (.xlsx) lub vCard (.vcf) z Plików, iCloud lub połączonej chmury. Do 10 000 klientów i 10 MB na plik.")).font(.subheadline).foregroundStyle(.secondary)
            DisclosureGroup(L.t("Optionen für ältere Exporte", "Options for older exports", "Opcje starszych eksportów")) {
                Picker(L.t("Zeichensatz", "Encoding", "Kodowanie"), selection: $encoding) { Text("UTF-8").tag("utf8"); Text("Windows 1252 (DE)").tag("cp1252"); Text("Windows 1250 (PL)").tag("cp1250"); Text("UTF-16").tag("utf16") }
                if fileData != nil { Button(L.t("Datei erneut prüfen", "Check file again", "Sprawdź ponownie")) { parse() }.disabled(busy) }
            }
            Label(L.t("Die Datei wird auf deinem iPhone gelesen. Kein automatischer Upload.", "The file is read on your iPhone. No automatic upload.", "Plik jest odczytywany na iPhonie. Bez automatycznego wysyłania."), systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
        }
    }
    var mappingSection: some View {
        Group {
            if let table {
                Section {
                    LabeledContent(L.t("Datei", "File", "Plik"), value: filename)
                    if tables.count > 1 { Picker(L.t("Tabellenblatt", "Worksheet", "Arkusz"), selection: $sheet) { ForEach(tables.indices, id: \.self) { Text(tables[$0].title).tag($0) } }.onChange(of: sheet) { _, _ in mapping = self.table?.headers.map(ContactField.guess) ?? [] } }
                    TextField(L.t("Herkunft / bisheriges Programm", "Source / previous program", "Źródło / poprzedni program"), text: $source)
                    Text("\(table.rows.count) " + L.t("Kundenzeilen gefunden", "customer rows found", "znalezionych wierszy klientów")).font(.subheadline)
                }
                Section(L.t("Felder zuordnen", "Match fields", "Dopasuj pola")) {
                    ForEach(table.headers.indices, id: \.self) { i in
                        if mapping.indices.contains(i) {
                            VStack(alignment: .leading, spacing: 3) {
                                Picker(table.headers[i].isEmpty ? "\(i+1)" : table.headers[i], selection: $mapping[i]) { ForEach(ContactField.allCases) { Text($0.title).tag($0) } }
                                Text(table.rows.first?[i] ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
                Section { Button(L.t("Vorschau anzeigen", "Show preview", "Pokaż podgląd")) { preview() }.buttonStyle(.borderedProminent).disabled(!mapping.contains(.name) && !mapping.contains(.person) || source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }
    var reviewSection: some View {
        Group {
            Section {
                LabeledContent(L.t("Ziel", "Destination", "Cel"), value: store.data.company.isEmpty ? L.t("Aktueller Bereich", "Current area", "Bieżący obszar") : store.data.company)
                LabeledContent(L.t("Ausgewählt", "Selected", "Wybrano"), value: "\(selected.count) / \(candidates.count)")
                Text(L.t("Gleicher Name, E-Mail, Telefon oder gleiche Quell-Kundennummer: bitte prüfen. Wählst du eine Dublette trotzdem, entsteht ein zusätzlicher Kunde.", "Same name, email, phone or source customer number: review first. Selecting a possible duplicate creates another customer.", "Ta sama nazwa, e-mail, telefon lub numer źródłowy: sprawdź. Wybranie duplikatu utworzy kolejnego klienta.")).font(.caption).foregroundStyle(.secondary)
                Button(L.t("\(selected.count) Kunden übernehmen", "Import \(selected.count) customers", "Importuj \(selected.count) klientów")) { commit() }.buttonStyle(.borderedProminent).disabled(selected.isEmpty || !store.canBulkManage || !store.canEdit || busy)
            }
            Section(L.t("Vorschau", "Preview", "Podgląd")) {
                ForEach(candidates) { candidate in
                    Toggle(isOn: Binding(get: { selected.contains(candidate.id) }, set: { if $0 { selected.insert(candidate.id) } else { selected.remove(candidate.id) } })) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.customer.name.isEmpty ? "—" : candidate.customer.name).font(.headline)
                            if !candidate.customer.address.isEmpty { Text(candidate.customer.address).font(.caption).foregroundStyle(.secondary) }
                            if !candidate.customer.contact.isEmpty { Text(candidate.customer.contact).font(.caption).foregroundStyle(.secondary) }
                            if let issue = candidate.issue { Label(issue, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.red) }
                            else if candidate.duplicate { Label(L.t("Mögliche Dublette", "Possible duplicate", "Możliwy duplikat"), systemImage: "person.2.badge.gearshape").font(.caption).foregroundStyle(.orange) }
                        }
                    }.disabled(candidate.issue != nil)
                }
            }
        }
    }
    func parse() {
        guard let bytes = fileData else { return }; busy = true; error = ""
        let name = filename, selectedEncoding = encoding
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { try ContactImporter.parse(bytes, filename: name, encoding: selectedEncoding) }.value
                tables = result; sheet = 0; mapping = result[0].headers.map(ContactField.guess); stage = 1
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
    func preview() {
        guard let table, context == store.contextID else { error = L.t("Bereich geändert. Import neu öffnen.", "Area changed. Reopen import.", "Obszar zmieniony. Otwórz import ponownie."); return }
        reviewed = store.data.customers
        candidates = ContactImporter.candidates(table: table, mapping: mapping, source: source.trimmingCharacters(in: .whitespacesAndNewlines), existing: reviewed)
        selected = Set(candidates.filter { $0.issue == nil && !$0.duplicate }.map(\.id)); stage = 2; error = ""
    }
    func commit() {
        do { let receipt = try store.importCustomers(candidates.filter { selected.contains($0.id) && $0.issue == nil }.map(\.customer), source: source, context: context, reviewed: reviewed); count = receipt.customers.count; stage = 3; error = ""; fileData = nil }
        catch { self.error = error.localizedDescription }
    }
}
