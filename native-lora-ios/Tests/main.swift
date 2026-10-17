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
let result: [String: Any] = ["product": "Werkbeleg", "passed": true, "checks": checks, "source": "synthetic", "teamHosted": false]
if let index = CommandLine.arguments.firstIndex(of: "--json"), CommandLine.arguments.count > index + 1 {
    try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
}
print("PASS: \(checks) workspace validation / attachment round-trip checks")
