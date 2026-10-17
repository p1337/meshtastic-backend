import Foundation
import Compression
import CoreFoundation

enum ImportFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}
enum ContactField: String, CaseIterable, Identifiable {
    case ignore, name, person, externalID, street, postalCode, city, country, email, phone, taxID, notes, address
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ignore: return L.t("Nicht übernehmen", "Ignore", "Pomiń")
        case .name: return L.t("Name / Firma", "Name / company", "Nazwa / firma")
        case .person: return L.t("Ansprechpartner", "Contact person", "Osoba kontaktowa")
        case .externalID: return L.t("Kundennummer", "Customer number", "Numer klienta")
        case .street: return L.t("Straße / Hausnummer", "Street / number", "Ulica / numer")
        case .postalCode: return L.t("Postleitzahl", "Postal code", "Kod pocztowy")
        case .city: return L.t("Ort", "City", "Miejscowość")
        case .country: return L.t("Land", "Country", "Kraj")
        case .email: return "E-Mail"
        case .phone: return L.t("Telefon", "Phone", "Telefon")
        case .taxID: return "USt-ID / UID / NIP"
        case .notes: return L.t("Notizen", "Notes", "Notatki")
        case .address: return L.t("Vollständige Adresse", "Full address", "Pełny adres")
        }
    }
    static func guess(_ title: String) -> ContactField {
        let t = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).filter { $0.isLetter || $0.isNumber }
        let aliases: [ContactField: [String]] = [
            .name: ["name", "firma", "firmenname", "company", "companyname", "displayname", "nazwa", "nazwafirmy", "kontaktname", "organisation", "organization"],
            .person: ["ansprechpartner", "contactperson", "firstname", "vorname", "imie", "lastname", "nachname", "nazwisko", "fullname"],
            .externalID: ["kundennummer", "kundennr", "customernumber", "customerid", "contactnumber", "numerklienta", "nrklienta", "number"],
            .street: ["strasse", "street", "streetaddress", "ulica", "billingstreet", "strassehausnummer"],
            .postalCode: ["plz", "postleitzahl", "zip", "zipcode", "postalcode", "kodpocztowy", "billingzip"],
            .city: ["ort", "stadt", "city", "miasto", "miejscowosc", "billingcity"],
            .country: ["land", "country", "kraj", "countrycode"],
            .email: ["email", "emailaddress", "email1value", "emailadresse", "mail"],
            .phone: ["telefon", "phone", "phone1value", "phonenumber", "telefonnummer", "mobile", "mobil", "telefonkomorkowy"],
            .taxID: ["ustid", "ustidnr", "vatid", "vatnumber", "uid", "nip", "ustidentifikationsnummer"],
            .notes: ["notizen", "notes", "uwagi", "bemerkung", "bemerkungen"],
            .address: ["adresse", "address", "adres", "anschrift"]]
        return aliases.first(where: { $0.value.contains(t) })?.key ?? .ignore
    }
}
struct ContactTable: Identifiable {
    let id = UUID()
    var title: String
    var headers: [String]
    var rows: [[String]]
}
struct ImportCandidate: Identifiable {
    var id: Int // source row, stable during review
    var customer: Customer
    var issue: String?
    var duplicate: Bool
}
struct ImportReceipt: Codable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    var source: String
    var customers: [Customer]
}
enum ContactImporter {
    static let fileLimit = 10 * 1024 * 1024
    static let rowLimit = 10000
    static func parse(_ data: Data, filename: String, encoding: String = "utf8") throws -> [ContactTable] {
        guard !data.isEmpty, data.count <= fileLimit else { throw ImportFailure.message(L.t("Datei leer oder größer als 10 MB.", "File empty or larger than 10 MB.", "Plik pusty lub większy niż 10 MB.")) }
        let ext = (filename as NSString).pathExtension.lowercased()
        if ext == "xlsx" { return try SpreadsheetReader.read(data) }
        if ext == "xls" || ext == "xlsm" { throw ImportFailure.message(L.t("Bitte in Excel, Numbers oder LibreOffice als CSV oder XLSX speichern. Alte XLS-Dateien und Makrodateien werden nicht geöffnet.", "Save as CSV or XLSX in Excel, Numbers or LibreOffice. Legacy XLS and macro files are not opened.", "Zapisz jako CSV lub XLSX w Excel, Numbers lub LibreOffice. Stare XLS i pliki makr nie są otwierane.")) }
        let selected: String.Encoding
        switch encoding {
        case "cp1252": selected = .windowsCP1252
        case "cp1250": selected = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsLatin2.rawValue)))
        case "utf16": selected = .utf16
        default: selected = .utf8
        }
        guard var text = String(data: data, encoding: selected) else { throw ImportFailure.message(L.t("Zeichensatz passt nicht. Wähle unter Optionen einen anderen Zeichensatz.", "Encoding mismatch. Choose another encoding under Options.", "Niezgodne kodowanie. Wybierz inne w Opcjach.")) }
        if text.first == "\u{feff}" { text.removeFirst() }
        if ext == "vcf" { return [try vcard(text, title: filename)] }
        guard ["csv", "tsv", "txt"].contains(ext) else { throw ImportFailure.message(L.t("Bitte CSV, XLSX oder vCard (.vcf) auswählen.", "Choose CSV, XLSX or vCard (.vcf).", "Wybierz CSV, XLSX lub vCard (.vcf).")) }
        return [try csv(text, title: filename, delimiter: ext == "tsv" ? "\t" : nil)]
    }
    static func csv(_ input: String, title: String, delimiter: Character? = nil) throws -> ContactTable {
        let text = input.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let chars = Array(text)
        var delim = delimiter ?? ";"
        if delimiter == nil {
            var counts: [Character: Int] = [";": 0, ",": 0, "\t": 0]; var quoted = false
            for c in chars { if c == "\"" { quoted.toggle() }; if c == "\n" && !quoted { break }; if !quoted && counts[c] != nil { counts[c, default: 0] += 1 } }
            delim = [Character(";"), Character(","), Character("\t")].max(by: { counts[$0, default: 0] < counts[$1, default: 0] }) ?? ";"
        }
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false, closed = false, i = 0
        func appendField() throws {
            guard field.count <= 4096, row.count < 80 else { throw ImportFailure.message("Max. 80 Spalten und 4096 Zeichen je Feld / Max. 80 columns and 4096 characters per field") }
            row.append(field); field = ""; closed = false
        }
        func appendRow() throws {
            try appendField()
            if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { rows.append(row) }
            row = []
            guard rows.count <= rowLimit + 1 else { throw ImportFailure.message("Max. 10.000 Kunden / Max. 10,000 customers") }
        }
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(c) }
            } else if c == delim { try appendField() }
            else if c == "\n" { try appendRow() }
            else if c == "\"" && field.isEmpty && !closed { quoted = true }
            else {
                guard !closed, c != "\"", c != "\0" else { throw ImportFailure.message(L.t("Ungültige CSV-Anführungszeichen oder Steuerzeichen.", "Invalid CSV quotes or control character.", "Nieprawidłowy CSV lub znak sterujący.")) }
                field.append(c)
            }
            guard field.count <= 4096 else { throw ImportFailure.message("Feld zu lang / Field too long") }
            i += 1
        }
        guard !quoted else { throw ImportFailure.message("CSV: Anführungszeichen nicht geschlossen / Unclosed quote") }
        if !field.isEmpty || !row.isEmpty || closed { try appendRow() }
        guard let header = rows.first, rows.count > 1 else { throw ImportFailure.message(L.t("Kopfzeile und mindestens einen Kunden benötigt.", "A header and at least one customer are required.", "Wymagany nagłówek i co najmniej jeden klient.")) }
        guard rows.dropFirst().allSatisfy({ $0.count == header.count }) else { throw ImportFailure.message(L.t("Die Anzahl der Spalten stimmt nicht in jeder Zeile. Bitte Export prüfen.", "Column counts differ between rows. Check the export.", "Różna liczba kolumn w wierszach. Sprawdź eksport.")) }
        return ContactTable(title: title, headers: header, rows: Array(rows.dropFirst()))
    }
    static func vcard(_ input: String, title: String) throws -> ContactTable {
        let text = input.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\n ", with: "").replacingOccurrences(of: "\n\t", with: "")
        var cards: [[String]] = [], values: [String: [String]] = [:], inside = false
        func value(_ key: String) -> String { (values[key] ?? []).joined(separator: "\n") }
        func unescape(_ s: String) -> String { s.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\N", with: "\n").replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";").replacingOccurrences(of: "\\\\", with: "\\") }
        for line in text.components(separatedBy: "\n") {
            if line.uppercased() == "BEGIN:VCARD" { guard !inside else { throw ModelError.invalid }; inside = true; values = [:]; continue }
            if line.uppercased() == "END:VCARD" {
                guard inside else { throw ModelError.invalid }; inside = false
                let person = value("FN").isEmpty ? value("N").replacingOccurrences(of: ";", with: " ") : value("FN")
                cards.append([value("ORG").isEmpty ? person : value("ORG"), person, value("UID"), value("ADR").replacingOccurrences(of: ";", with: "\n"), value("EMAIL"), value("TEL"), value("NOTE")])
                guard cards.count <= rowLimit else { throw ModelError.tooLarge }; continue
            }
            guard inside, let colon = line.firstIndex(of: ":") else { continue }
            let property = String(line[..<colon]); let key = (property.components(separatedBy: ";").first ?? "").components(separatedBy: ".").last!.uppercased()
            guard !property.uppercased().contains("ENCODING=QUOTED-PRINTABLE") else { throw ImportFailure.message("vCard bitte als UTF-8 exportieren / Export vCard as UTF-8") }
            if ["FN", "N", "ORG", "UID", "ADR", "EMAIL", "TEL", "NOTE"].contains(key) {
                let v = unescape(String(line[line.index(after: colon)...])); guard v.count <= 4096 else { throw ModelError.tooLarge }; values[key, default: []].append(v)
            }
        }
        guard !inside, !cards.isEmpty else { throw ImportFailure.message("Ungültige/leere vCard / Invalid or empty vCard") }
        return ContactTable(title: title, headers: ["Name", "Contact person", "Customer number", "Address", "Email", "Phone", "Notes"], rows: cards)
    }
    static func candidates(table: ContactTable, mapping: [ContactField], source: String, existing: [Customer]) -> [ImportCandidate] {
        var external = Set(existing.filter { !$0.details.externalID.isEmpty && $0.details.source == source }.map { $0.details.externalID })
        var names = Set(existing.map { normalized($0.name) })
        var emails = Set(existing.flatMap { $0.details.email.components(separatedBy: "\n") }.filter { !$0.isEmpty }.map(normalized))
        var phones = Set(existing.flatMap { $0.details.phone.components(separatedBy: "\n") }.map { $0.filter(\.isNumber) }.filter { !$0.isEmpty })
        return table.rows.enumerated().map { index, row in
            var fields: [ContactField: String] = [:]
            for (column, field) in mapping.enumerated() where field != .ignore && column < row.count {
                let v = row[column].trimmingCharacters(in: .whitespacesAndNewlines)
                if !v.isEmpty { fields[field] = [fields[field], v].compactMap { $0 }.joined(separator: field == .person ? " " : "\n") }
            }
            var c = Customer(name: fields[.name] ?? fields[.person] ?? "")
            c.details = CustomerDetails(externalID: fields[.externalID] ?? "", source: source, person: fields[.person] ?? "", street: fields[.street] ?? "", postalCode: fields[.postalCode] ?? "", city: fields[.city] ?? "", country: fields[.country] ?? "", email: fields[.email] ?? "", phone: fields[.phone] ?? "", taxID: fields[.taxID] ?? "", notes: fields[.notes] ?? "")
            c.address = fields[.address] ?? [c.details.street, [c.details.postalCode, c.details.city].filter { !$0.isEmpty }.joined(separator: " "), c.details.country].filter { !$0.isEmpty }.joined(separator: "\n")
            c.contact = [c.details.person, c.details.email, c.details.phone].filter { !$0.isEmpty }.joined(separator: "\n")
            let emailValues = c.details.email.components(separatedBy: "\n").filter { !$0.isEmpty }.map(normalized)
            let phoneValues = c.details.phone.components(separatedBy: "\n").map { $0.filter(\.isNumber) }.filter { !$0.isEmpty }
            let duplicate = (!c.details.externalID.isEmpty && external.contains(c.details.externalID)) || names.contains(normalized(c.name)) || emailValues.contains(where: { emails.contains($0) }) || phoneValues.contains(where: { phones.contains($0) })
            let issue = c.name.isEmpty ? L.t("Name fehlt", "Name missing", "Brak nazwy") : c.name.count > 160 ? L.t("Name länger als 160 Zeichen", "Name exceeds 160 characters", "Nazwa przekracza 160 znaków") : nil
            if issue == nil {
                if !c.details.externalID.isEmpty { external.insert(c.details.externalID) }; names.insert(normalized(c.name)); emails.formUnion(emailValues); phones.formUnion(phoneValues)
            }
            return ImportCandidate(id: index, customer: c, issue: issue, duplicate: duplicate)
        }
    }
    static func normalized(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
}

// Bounded, in-memory OOXML reader. No extraction to disk, macros, links or formula execution.
enum SpreadsheetReader {
    static func read(_ data: Data) throws -> [ContactTable] {
        let files = try unzip(data)
        guard files["[Content_Types].xml"] != nil, let workbook = files["xl/workbook.xml"], let rels = files["xl/_rels/workbook.xml.rels"] else { throw ImportFailure.message("Keine gültige XLSX-Datei / Invalid XLSX file") }
        guard !files.keys.contains(where: { $0.lowercased().contains("vbaproject") || $0.hasPrefix("xl/externalLinks/") }) else { throw ImportFailure.message("Makros / externe Verknüpfungen nicht unterstützt / Macros or external links unsupported") }
        let shared = try files["xl/sharedStrings.xml"].map { try SheetXML.parse($0, kind: "strings").strings } ?? []
        let relationships = try SheetXML.parse(rels, kind: "relationships").links
        let sheets = try SheetXML.parse(workbook, kind: "workbook").sheets
        var result: [ContactTable] = []
        for (name, id) in sheets {
            guard let target = relationships[id], !target.contains(".."), !target.contains(":") else { throw ModelError.invalid }
            let path = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
            guard path.hasPrefix("xl/worksheets/"), let bytes = files[path] else { throw ModelError.invalid }
            let parsed = try SheetXML.parse(bytes, kind: "worksheet", shared: shared)
            if parsed.rows.count > 1 { result.append(ContactTable(title: name, headers: parsed.rows[0], rows: Array(parsed.rows.dropFirst()))) }
        }
        guard !result.isEmpty else { throw ImportFailure.message("Keine Kundentabelle mit Kopfzeile gefunden / No customer sheet with a header found") }; return result
    }
    static func unzip(_ data: Data) throws -> [String: Data] {
        let b = [UInt8](data)
        func u16(_ n: Int) throws -> Int { guard n >= 0, n + 2 <= b.count else { throw ModelError.invalid }; return Int(b[n]) | Int(b[n+1]) << 8 }
        func u32(_ n: Int) throws -> Int { try u16(n) | (u16(n+2) << 16) }
        guard b.count >= 22 else { throw ModelError.invalid }
        var end: Int? = nil
        for i in stride(from: b.count - 22, through: max(0, b.count - 65557), by: -1) {
            if try u32(i) == 0x06054b50, try u16(i+20) == b.count-i-22 { end = i; break }
        }
        guard let e = end, try u16(e+4) == 0, try u16(e+6) == 0, try u16(e+8) == u16(e+10) else { throw ModelError.invalid }
        let count = try u16(e+10), centralSize = try u32(e+12); var pos = try u32(e+16), total = 0
        guard count <= 500, pos + centralSize == e else { throw ModelError.tooLarge }
        var files: [String: Data] = [:]
        for _ in 0..<count {
            guard try u32(pos) == 0x02014b50 else { throw ModelError.invalid }
            let flags = try u16(pos+8), method = try u16(pos+10), crc = try u32(pos+16), size = try u32(pos+20), expanded = try u32(pos+24)
            let nameSize = try u16(pos+28), extra = try u16(pos+30), comment = try u16(pos+32), offset = try u32(pos+42)
            guard flags & 1 == 0, [0,8].contains(method), expanded <= 20*1024*1024, pos+46+nameSize+extra+comment <= e else { throw ModelError.invalid }
            total += expanded; guard total <= 40*1024*1024 else { throw ModelError.tooLarge }
            guard let name = String(bytes: b[(pos+46)..<(pos+46+nameSize)], encoding: .utf8), !name.contains(".."), !name.hasPrefix("/"), files[name] == nil else { throw ModelError.invalid }
            guard try u32(offset) == 0x04034b50, try u16(offset+8) == method else { throw ModelError.invalid }
            let localNameSize = try u16(offset+26), localExtra = try u16(offset+28), start = offset+30+localNameSize+localExtra
            guard start >= 0, start+size <= e, String(bytes: b[(offset+30)..<(offset+30+localNameSize)], encoding: .utf8) == name else { throw ModelError.invalid }
            let compressed = Array(b[start..<(start+size)]); let decoded: [UInt8]
            if method == 0 { guard size == expanded else { throw ModelError.invalid }; decoded = compressed }
            else if expanded == 0 { decoded = [] }
            else {
                guard !compressed.isEmpty else { throw ModelError.invalid }
                var buffer = [UInt8](repeating: 0, count: expanded+1)
                let length = compressed.withUnsafeBufferPointer { src in buffer.withUnsafeMutableBufferPointer { dst in compression_decode_buffer(dst.baseAddress!, dst.count, src.baseAddress!, src.count, nil, COMPRESSION_ZLIB) } }
                guard length == expanded else { throw ModelError.invalid }; decoded = Array(buffer.prefix(length))
            }
            var checksum: UInt32 = 0xffffffff
            for byte in decoded { checksum ^= UInt32(byte); for _ in 0..<8 { checksum = (checksum >> 1) ^ ((checksum & 1) == 1 ? 0xedb88320 : 0) } }
            guard Int(checksum ^ 0xffffffff) == crc else { throw ModelError.invalid }
            files[name] = Data(decoded); pos += 46+nameSize+extra+comment
        }
        guard pos == e else { throw ModelError.invalid }; return files
    }
}
final class SheetXML: NSObject, XMLParserDelegate {
    let kind: String; let shared: [String]
    var strings: [String] = [], links: [String: String] = [:], sheets: [(String,String)] = [], rows: [[String]] = []
    var row: [Int: String] = [:], value = "", cellType = "", column = 0, text = "", collecting = false, inCell = false, invalid = false
    init(kind: String, shared: [String]) { self.kind = kind; self.shared = shared }
    static func parse(_ data: Data, kind: String, shared: [String] = []) throws -> SheetXML {
        guard data.count <= 20*1024*1024, let xml = String(data: data, encoding: .utf8), !xml.uppercased().contains("<!DOCTYPE"), !xml.uppercased().contains("<!ENTITY") else { throw ModelError.invalid }
        let reader = SheetXML(kind: kind, shared: shared), parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false; parser.delegate = reader
        guard parser.parse(), !reader.invalid else { throw ImportFailure.message(L.t("Excel-Datei enthält Formeln, ungültige Daten oder überschreitet die Importgrenzen. Bitte als CSV exportieren.", "Spreadsheet contains formulas, invalid data or exceeds import limits. Export as CSV.", "Arkusz zawiera formuły, nieprawidłowe dane lub przekracza limity. Wyeksportuj jako CSV.")) }; return reader
    }
    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName qName: String?, attributes a: [String: String] = [:]) {
        switch element {
        case "si": text = ""
        case "Relationship" where kind == "relationships":
            if a["TargetMode"] != "External", let id = a["Id"], let target = a["Target"] { links[id] = target }
        case "sheet" where kind == "workbook": if let name = a["name"], let id = a["r:id"] { sheets.append((name,id)) }
        case "row" where kind == "worksheet": row = [:]
        case "c" where kind == "worksheet":
            let reference = a["r"] ?? ""; let letters = reference.prefix(while: { $0.isLetter })
            guard !letters.isEmpty, letters.count <= 2, letters.utf8.allSatisfy({ (65...90).contains($0) }) else { invalid = true; parser.abortParsing(); return }
            column = letters.utf8.reduce(0) { $0*26+Int($1)-64 }-1
            if column < 0 || column >= 80 { invalid = true; parser.abortParsing(); return }
            cellType = a["t"] ?? ""; value = ""; inCell = true
        case "f" where kind == "worksheet": invalid = true; parser.abortParsing()
        case "t", "v": collecting = true
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collecting { if kind == "strings" { text += string } else if inCell { value += string } }
        if value.count > 4096 || text.count > 4096 { invalid = true; parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName qName: String?) {
        if element == "t" || element == "v" { collecting = false }
        if element == "si" && kind == "strings" { strings.append(text); if strings.count > 800000 { invalid = true; parser.abortParsing() } }
        if element == "c" && kind == "worksheet" {
            if cellType == "s" { if let n = Int(value), shared.indices.contains(n) { value = shared[n] } else { invalid = true; parser.abortParsing(); return } }
            row[column] = value; inCell = false
        }
        if element == "row" && kind == "worksheet" {
            if let last = row.keys.max(), row.values.contains(where: { !$0.isEmpty }) {
                rows.append((0...last).map { row[$0] ?? "" })
                if rows.count > ContactImporter.rowLimit+1 { invalid = true; parser.abortParsing() }
            }
        }
        if element == "worksheet" && kind == "worksheet", let header = rows.first {
            if rows.dropFirst().contains(where: { $0.count > header.count }) { invalid = true; parser.abortParsing(); return }
            rows = rows.map { $0 + Array(repeating: "", count: max(0, header.count-$0.count)) }
        }
    }
}

// Undo never touches customers changed since import or referenced by a project.
enum ImportUndo {
    static func removable(receipt: ImportReceipt, workspace: Workspace) -> Set<UUID> {
        let used = Set(workspace.jobs.map(\.customerID))
        let original = receipt.customers.reduce(into: [UUID: Customer]()) { $0[$1.id] = $1 }
        return Set(workspace.customers.filter { !used.contains($0.id) && original[$0.id] == $0 }.map(\.id))
    }
}
