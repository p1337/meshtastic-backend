import Foundation

struct Customer: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var address = ""
    var contact = ""
    var details = CustomerDetails()
}
struct CustomerDetails: Codable, Equatable {
    var externalID = ""
    var source = ""
    var person = ""
    var street = ""
    var postalCode = ""
    var city = ""
    var country = ""
    var email = ""
    var phone = ""
    var taxID = ""
    var notes = ""
    var importID: UUID? = nil
}
extension Customer {
    enum CodingKeys: String, CodingKey { case id, name, address, contact, details }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        contact = try c.decodeIfPresent(String.self, forKey: .contact) ?? ""
        details = try c.decodeIfPresent(CustomerDetails.self, forKey: .details) ?? CustomerDetails()
    }
}
struct Job: Codable, Identifiable, Equatable {
    var id = UUID()
    var customerID: UUID
    var title: String
    var address = ""
    var assignedTo = ""
    var completed = false
}
struct Evidence: Codable, Identifiable, Equatable {
    var id = UUID()
    var data: Data
    var capturedAt = Date()
    var source: String // camera or imported; import time is not claimed as capture time
}
struct Report: Codable, Identifiable, Equatable {
    var id = UUID()
    var jobID: UUID
    var createdAt = Date()
    var author = ""
    var text = ""
    var photos: [Evidence] = []
    var audio: Data? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    var accuracy: Double? = nil
    var locationAt: Date? = nil
    var weather = "" // entered by the author; never presented as measured weather
}
struct ProjectMessage: Codable, Identifiable, Equatable {
    var id = UUID()
    var jobID: UUID
    var author: String
    var text: String
    var createdAt = Date()
}
struct TeamMember: Codable, Identifiable { var name: String; var role: String; var id: String { name } }
struct TeamInfo: Codable { var seatLimit: Int; var memberCount: Int; var pendingInvites: Int; var role: String; var members: [TeamMember]; var recipientBoundInvites: Bool? = nil }
struct InvitationContext: Identifiable { let id = UUID(); var server: URL; var code: String }
struct Workspace: Codable, Equatable {
    var schema = 1
    var company = ""
    var customers: [Customer] = []
    var jobs: [Job] = []
    var reports: [Report] = []
    var messages: [ProjectMessage] = []
    func validate() throws {
        guard schema == 1, Set(customers.map(\.id)).count == customers.count,
              Set(jobs.map(\.id)).count == jobs.count,
              Set(reports.map(\.id)).count == reports.count else { throw ModelError.invalid }
        let customerIDs = Set(customers.map(\.id)), jobIDs = Set(jobs.map(\.id))
        guard jobs.allSatisfy({ customerIDs.contains($0.customerID) }),
              reports.allSatisfy({ jobIDs.contains($0.jobID) }),
              reports.allSatisfy({ $0.latitude.map { $0.isFinite && abs($0) <= 90 } ?? true }),
              reports.allSatisfy({ $0.longitude.map { $0.isFinite && abs($0) <= 180 } ?? true })
        else { throw ModelError.invalid }
    }
    func encoded() throws -> Data { try validate(); return try JSONEncoder().encode(self) }
    static func decode(_ data: Data) throws -> Workspace {
        guard data.count <= 30 * 1024 * 1024 else { throw ModelError.tooLarge }
        let result = try JSONDecoder().decode(Workspace.self, from: data)
        try result.validate(); return result
    }
}
// Explicitly decode additive fields so pilot 1.0 backups remain readable.
extension Workspace {
    enum CodingKeys: String, CodingKey { case schema, company, customers, jobs, reports, messages }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(Int.self, forKey: .schema)
        company = try c.decode(String.self, forKey: .company)
        customers = try c.decode([Customer].self, forKey: .customers)
        jobs = try c.decode([Job].self, forKey: .jobs)
        reports = try c.decode([Report].self, forKey: .reports)
        messages = try c.decodeIfPresent([ProjectMessage].self, forKey: .messages) ?? []
    }
}
enum ModelError: LocalizedError {
    case invalid, tooLarge
    var errorDescription: String? {
        switch self {
        case .invalid: return "Ungültige Projektdaten / Invalid project data"
        case .tooLarge: return "Sicherung über 30 MiB / Backup exceeds 30 MiB"
        }
    }
}
struct TeamSnapshot: Codable { var version: Int; var workspace: Workspace }

enum L {
    static func t(_ de: String, _ en: String, _ pl: String) -> String {
        let lang = UserDefaults.standard.string(forKey: "language") ?? "de"
        return lang == "pl" ? pl : lang == "en" ? en : de
    }
}
