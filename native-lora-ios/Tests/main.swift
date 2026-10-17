import Foundation
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    precondition(condition(), label); checks += 1
}
let customer = Customer(name: "Synthetic customer")
let job = Job(customerID: customer.id, title: "Synthetic job")
let photo = Evidence(data: Data([0, 1, 2, 255]), source: "imported")
let report = Report(jobID: job.id, text: "Zażółć gęślą jaźń · Prüfung", photos: [photo], audio: Data([1, 2, 3]))
let workspace = Workspace(company: "Test", customers: [customer], jobs: [job], reports: [report])
let bytes = try workspace.encoded()
let decoded = try Workspace.decode(bytes)
check(decoded == workspace, "Round trip including binary attachments and dates")
func reject(_ workspace: Workspace) {
    do { _ = try workspace.encoded(); fatalError("Invalid workspace accepted") } catch { checks += 1 }
}
var duplicate = workspace; duplicate.customers.append(customer); reject(duplicate)
var orphan = workspace; orphan.customers = []; reject(orphan)
var orphanReport = workspace; orphanReport.jobs = []; reject(orphanReport)
var schema = workspace; schema.schema = 99; reject(schema)
var gps = workspace; gps.reports[0].latitude = 91; reject(gps)
var lon = workspace; lon.reports[0].longitude = -181; reject(lon)
 do { _ = try Workspace.decode(Data("{bad json".utf8)); fatalError("Malformed JSON accepted") } catch { checks += 1 }
 do { _ = try Workspace.decode(Data(repeating: 0, count: 30 * 1024 * 1024 + 1)); fatalError("Oversize input accepted") } catch { checks += 1 }
check(report.photos[0].source == "imported", "Imported provenance survives")
let legacy = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
var withoutMessages = legacy; withoutMessages.removeValue(forKey: "messages")
let migrated = try Workspace.decode(JSONSerialization.data(withJSONObject: withoutMessages))
check(migrated.messages.isEmpty && migrated.customers == workspace.customers, "1.0 backups migrate without a messages field")
var withChat = workspace
withChat.messages.append(ProjectMessage(jobID: job.id, author: "Tester", text: "Project update"))
let chatDecoded = try Workspace.decode(withChat.encoded())
check(chatDecoded == withChat, "Chat metadata survives backup")

// Customer migration and real-world syntax boundaries.
check(decoded.customers[0].details == CustomerDetails(), "Legacy customers get empty structured details")
let csv = try ContactImporter.parse(Data("Name;PLZ;E-Mail;Telefon;Kundennummer\r\n\"Müller; Sohn\";00123;mail@example.invalid;+4930123;0007\r\n".utf8), filename: "lexware.csv")[0]
let mappings = csv.headers.map(ContactField.guess)
check(csv.rows[0][0] == "Müller; Sohn", "Quoted CSV delimiter")
let candidates = ContactImporter.candidates(table: csv, mapping: mappings, source: "Export", existing: [])
check(candidates[0].customer.details.postalCode == "00123" && candidates[0].customer.details.externalID == "0007", "Leading zeros survive CSV mapping")
check(candidates[0].customer.details.phone == "+4930123", "Plus phone numbers are text")
let duplicates = ContactImporter.candidates(table: csv, mapping: mappings, source: "Export", existing: [candidates[0].customer])
check(duplicates[0].duplicate, "Existing customer flagged without overwriting")
check(ContactImporter.candidates(table: csv, mapping: mappings, source: "Export", existing: [])[0].duplicate == false, "A separate workspace has an independent duplicate index")
let multiline = try ContactImporter.csv("Name,Notes\nAcme,\"Line one\nLine two \"\"quoted\"\"\"\n", title: "test")
check(multiline.rows[0][1] == "Line one\nLine two \"quoted\"", "Quoted multiline CSV and escaped quotes")
func rejectImport(_ label: String, _ action: () throws -> Void) {
 do { try action(); fatalError(label) } catch { checks += 1 }
}
rejectImport("Unclosed CSV rejected") { _ = try ContactImporter.csv("Name;Notes\nAcme;\"unfinished", title: "test") }
rejectImport("Unequal CSV columns rejected") { _ = try ContactImporter.csv("Name;Notes\nAcme;hello;extra", title: "test") }
rejectImport("No silent invalid encoding") { _ = try ContactImporter.parse(Data([255,255]), filename: "test.csv") }
rejectImport("Oversize file rejected") { _ = try ContactImporter.parse(Data(repeating: 1, count: ContactImporter.fileLimit+1), filename: "test.csv") }
rejectImport("Legacy XLS explicit conversion") { _ = try ContactImporter.parse(Data([1]), filename: "test.xls") }
rejectImport("Macro files not accepted") { _ = try ContactImporter.parse(Data([1]), filename: "test.xlsm") }
let windowsPL = Data([78,97,109,101,59,67,105,116,121,10,163,117,107,97,115,122,59,163,243,100,159])
let pl = try ContactImporter.parse(windowsPL, filename: "old.csv", encoding: "cp1250")[0]
check(pl.rows[0][0] == "Łukasz" && pl.rows[0][1] == "Łódź", "Explicit Windows-1250 decoding")
let vcf = try ContactImporter.parse(Data("BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Łukasz Nowak\r\nORG:Acme\r\nTEL:+48123\r\nTEL:+48456\r\nEMAIL:mail@example.invalid\r\nNOTE:First\\nSecond\r\nEND:VCARD\r\n".utf8), filename: "contacts.vcf")[0]
let vc = ContactImporter.candidates(table: vcf, mapping: vcf.headers.map(ContactField.guess), source: "Contacts", existing: [])[0].customer
check(vc.name == "Acme" && vc.details.person == "Łukasz Nowak", "vCard organization and person separate")
check(vc.details.phone == "+48123\n+48456" && vc.details.notes == "First\nSecond", "vCard multiple phone numbers and escaped newlines")
rejectImport("Truncated vCard rejected") { _ = try ContactImporter.vcard("BEGIN:VCARD\nFN:Incomplete", title: "test") }
let emptyName = try ContactImporter.csv("Name;City\n;Berlin", title: "test")
check(ContactImporter.candidates(table: emptyName, mapping: emptyName.headers.map(ContactField.guess), source: "x", existing: [])[0].issue != nil, "Missing name is review error")
var imported = candidates[0].customer; let importID = UUID(); imported.details.importID = importID
let receipt = ImportReceipt(id: importID, source: "Export", customers: [imported])
var undoWorkspace = Workspace(customers: [imported])
check(ImportUndo.removable(receipt: receipt, workspace: undoWorkspace) == [imported.id], "Undo selects unchanged imported customer")
undoWorkspace.customers[0].details.notes = "Changed after import"
check(ImportUndo.removable(receipt: receipt, workspace: undoWorkspace).isEmpty, "Undo retains later edits")
undoWorkspace.customers = [imported]; undoWorkspace.jobs = [Job(customerID: imported.id, title: "Used")]
check(ImportUndo.removable(receipt: receipt, workspace: undoWorkspace).isEmpty, "Undo retains customers referenced by projects")
let structuredRoundTrip = try Workspace.decode(Workspace(customers: [imported]).encoded())
check(structuredRoundTrip.customers == [imported], "Structured fields and import provenance round trip")
let xlsxDeflated = Data(base64Encoded: "UEsDBBQAAAAIAG6WUV3HHBc8CgAAAAgAAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbLMJqSxILda3AwBQSwMEFAAAAAgAbpZRXU1bBW57AAAAmQAAAA8AAAB4bC93b3JrYm9vay54bWw1jjEOwjAMRa8S5QC4MDBETRZYOEZoHRK1iSPbVTk+Hej09fTe8MedeHkTLeZb1yaOvc2q3QHIlLFGuVDHdrhEXKMeyB+glMqET5q2ik3hNgx3YFyjFmqSSxcbRsmIKv81LVb09rGJUkUWa9iV2Vt+zVcLYYSzhvNO+AFQSwMEFAAAAAgAbpZRXdTErVk/AAAAVwAAABoAAAB4bC9fcmVscy93b3JrYm9vay54bWwucmVsc7MJSs1JLMnMzyvOyCwotrNB5ip4ptgqFXmmGCophCQWpaeW2CqV5xdlF2ekppYU64MpQ72K3BwlfTsbfVRzAFBLAwQUAAAACABullFdvPUpYz4AAABrAAAAFAAAAHhsL3NoYXJlZFN0cmluZ3MueG1ssykuLrGzKc60symx80vMTbXRB3L1QXyIWEB+cUlijkJyfgqG1NHG0uzE4ioF99wkD3Q5AwNDI2OEoD7IFgBQSwMEFAAAAAgAbpZRXb6eN9hZAAAAwAAAABgAAAB4bC93b3Jrc2hlZXRzL3NoZWV0MS54bWyzKc8vyi7OSE0tsbMBUy6JJYl2NkX55QpFtkqGSnY2ySCGo6GSQomtUjGQX2ZnYKNfZmejnwyVc0KWM4TL6QPNgBtkBDfICEmxEZpByHLGaAbpI7lOH+FoAFBLAQIUAxQAAAAIAG6WUV3HHBc8CgAAAAgAAAATAAAAAAAAAAAAAACAAQAAAABbQ29udGVudF9UeXBlc10ueG1sUEsBAhQDFAAAAAgAbpZRXU1bBW57AAAAmQAAAA8AAAAAAAAAAAAAAIABOwAAAHhsL3dvcmtib29rLnhtbFBLAQIUAxQAAAAIAG6WUV3UxK1ZPwAAAFcAAAAaAAAAAAAAAAAAAACAAeMAAAB4bC9fcmVscy93b3JrYm9vay54bWwucmVsc1BLAQIUAxQAAAAIAG6WUV289SljPgAAAGsAAAAUAAAAAAAAAAAAAACAAVoBAAB4bC9zaGFyZWRTdHJpbmdzLnhtbFBLAQIUAxQAAAAIAG6WUV2+njfYWQAAAMAAAAAYAAAAAAAAAAAAAACAAcoBAAB4bC93b3Jrc2hlZXRzL3NoZWV0MS54bWxQSwUGAAAAAAUABQBOAQAAWQIAAAAA")!
let tableDeflated = try ContactImporter.parse(xlsxDeflated, filename: "test.xlsx")[0]
check(tableDeflated.rows[0] == ["Łukasz GmbH", "00123"], "Deflated OOXML shared-string fixture")
let xlsxStored = Data(base64Encoded: "UEsDBBQAAAAAAG6WUV3HHBc8CAAAAAgAAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbDxUeXBlcy8+UEsDBBQAAAAAAG6WUV1NWwVumQAAAJkAAAAPAAAAeGwvd29ya2Jvb2sueG1sPHdvcmtib29rIHhtbG5zOnI9Imh0dHA6Ly9zY2hlbWFzLm9wZW54bWxmb3JtYXRzLm9yZy9vZmZpY2VEb2N1bWVudC8yMDA2L3JlbGF0aW9uc2hpcHMiPjxzaGVldHM+PHNoZWV0IG5hbWU9IkN1c3RvbWVycyIgcjppZD0icklkMSIvPjwvc2hlZXRzPjwvd29ya2Jvb2s+UEsDBBQAAAAAAG6WUV3UxK1ZVwAAAFcAAAAaAAAAeGwvX3JlbHMvd29ya2Jvb2sueG1sLnJlbHM8UmVsYXRpb25zaGlwcz48UmVsYXRpb25zaGlwIElkPSJySWQxIiBUYXJnZXQ9IndvcmtzaGVldHMvc2hlZXQxLnhtbCIvPjwvUmVsYXRpb25zaGlwcz5QSwMEFAAAAAAAbpZRXbz1KWNrAAAAawAAABQAAAB4bC9zaGFyZWRTdHJpbmdzLnhtbDxzc3Q+PHNpPjx0Pk5hbWU8L3Q+PC9zaT48c2k+PHQ+UG9zdGFsIGNvZGU8L3Q+PC9zaT48c2k+PHQ+xYF1a2FzeiBHbWJIPC90Pjwvc2k+PHNpPjx0PjAwMTIzPC90Pjwvc2k+PC9zc3Q+UEsDBBQAAAAAAG6WUV2+njfYwAAAAMAAAAAYAAAAeGwvd29ya3NoZWV0cy9zaGVldDEueG1sPHdvcmtzaGVldD48c2hlZXREYXRhPjxyb3cgcj0iMSI+PGMgcj0iQTEiIHQ9InMiPjx2PjA8L3Y+PC9jPjxjIHI9IkIxIiB0PSJzIj48dj4xPC92PjwvYz48L3Jvdz48cm93IHI9IjIiPjxjIHI9IkEyIiB0PSJzIj48dj4yPC92PjwvYz48YyByPSJCMiIgdD0icyI+PHY+Mzwvdj48L2M+PC9yb3c+PC9zaGVldERhdGE+PC93b3Jrc2hlZXQ+UEsBAhQDFAAAAAAAbpZRXcccFzwIAAAACAAAABMAAAAAAAAAAAAAAIABAAAAAFtDb250ZW50X1R5cGVzXS54bWxQSwECFAMUAAAAAABullFdTVsFbpkAAACZAAAADwAAAAAAAAAAAAAAgAE5AAAAeGwvd29ya2Jvb2sueG1sUEsBAhQDFAAAAAAAbpZRXdTErVlXAAAAVwAAABoAAAAAAAAAAAAAAIAB/wAAAHhsL19yZWxzL3dvcmtib29rLnhtbC5yZWxzUEsBAhQDFAAAAAAAbpZRXbz1KWNrAAAAawAAABQAAAAAAAAAAAAAAIABjgEAAHhsL3NoYXJlZFN0cmluZ3MueG1sUEsBAhQDFAAAAAAAbpZRXb6eN9jAAAAAwAAAABgAAAAAAAAAAAAAAIABKwIAAHhsL3dvcmtzaGVldHMvc2hlZXQxLnhtbFBLBQYAAAAABQAFAE4BAAAhAwAAAAA=")!
let tableStored = try ContactImporter.parse(xlsxStored, filename: "test.xlsx")[0]
check(tableStored.rows[0] == ["Łukasz GmbH", "00123"], "Stored OOXML shared-string fixture")
let formulaXLSX = Data(base64Encoded: "UEsDBBQAAAAIAG6WUV3HHBc8CgAAAAgAAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbLMJqSxILda3AwBQSwMEFAAAAAgAbpZRXU1bBW57AAAAmQAAAA8AAAB4bC93b3JrYm9vay54bWw1jjEOwjAMRa8S5QC4MDBETRZYOEZoHRK1iSPbVTk+Hej09fTe8MedeHkTLeZb1yaOvc2q3QHIlLFGuVDHdrhEXKMeyB+glMqET5q2ik3hNgx3YFyjFmqSSxcbRsmIKv81LVb09rGJUkUWa9iV2Vt+zVcLYYSzhvNO+AFQSwMEFAAAAAgAbpZRXdTErVk/AAAAVwAAABoAAAB4bC9fcmVscy93b3JrYm9vay54bWwucmVsc7MJSs1JLMnMzyvOyCwotrNB5ip4ptgqFXmmGCophCQWpaeW2CqV5xdlF2ekppYU64MpQ72K3BwlfTsbfVRzAFBLAwQUAAAACABullFdvPUpYz4AAABrAAAAFAAAAHhsL3NoYXJlZFN0cmluZ3MueG1ssykuLrGzKc60symx80vMTbXRB3L1QXyIWEB+cUlijkJyfgqG1NHG0uzE4ioF99wkD3Q5AwNDI2OEoD7IFgBQSwMEFAAAAAgAbpZRXX3ObxVjAAAAygAAABgAAAB4bC93b3Jrc2hlZXRzL3NoZWV0MS54bWyzKc8vyi7OSE0tsbMBUy6JJYl2NkX55QpFtkqGSnY2ySCGo6GSQomtUjGQX2ZnYKNfZmejnwyVc0KWM4TL6QPNgBtkBDfICK44zc5QG6g8DaTNCM1IIyQjjdGM1Edypz7C+QBQSwECFAMUAAAACABullFdxxwXPAoAAAAIAAAAEwAAAAAAAAAAAAAAgAEAAAAAW0NvbnRlbnRfVHlwZXNdLnhtbFBLAQIUAxQAAAAIAG6WUV1NWwVuewAAAJkAAAAPAAAAAAAAAAAAAACAATsAAAB4bC93b3JrYm9vay54bWxQSwECFAMUAAAACABullFd1MStWT8AAABXAAAAGgAAAAAAAAAAAAAAgAHjAAAAeGwvX3JlbHMvd29ya2Jvb2sueG1sLnJlbHNQSwECFAMUAAAACABullFdvPUpYz4AAABrAAAAFAAAAAAAAAAAAAAAgAFaAQAAeGwvc2hhcmVkU3RyaW5ncy54bWxQSwECFAMUAAAACABullFdfc5vFWMAAADKAAAAGAAAAAAAAAAAAAAAgAHKAQAAeGwvd29ya3NoZWV0cy9zaGVldDEueG1sUEsFBgAAAAAFAAUATgEAAGMCAAAAAA==")!
rejectImport("Spreadsheet formulas rejected") { _ = try ContactImporter.parse(formulaXLSX, filename: "test.xlsx") }
rejectImport("XML entities rejected") { _ = try SheetXML.parse(Data("<!DOCTYPE x [<!ENTITY bad SYSTEM 'file:///etc/passwd'>]><worksheet/>".utf8), kind: "worksheet") }
rejectImport("Huge cell references rejected without overflow") { _ = try SheetXML.parse(Data("<worksheet><sheetData><row><c r='AAAAAAAAAAAAAAAAAAAAAAAAAAAA1'><v>1</v></c></row></sheetData></worksheet>".utf8), kind: "worksheet") }
rejectImport("Truncated ZIP rejected") { _ = try ContactImporter.parse(Data(xlsxDeflated.prefix(100)), filename: "test.xlsx") }
var damagedZIP = xlsxStored; damagedZIP[100] ^= 1
rejectImport("ZIP integrity failure rejected") { _ = try ContactImporter.parse(damagedZIP, filename: "test.xlsx") }

let result: [String: Any] = ["product": "Werkbeleg", "passed": true, "checks": checks, "source": "synthetic", "teamHosted": false]
if let index = CommandLine.arguments.firstIndex(of: "--json"), CommandLine.arguments.count > index + 1 {
    try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
}
print("PASS: \(checks) workspace validation / attachment round-trip checks")
