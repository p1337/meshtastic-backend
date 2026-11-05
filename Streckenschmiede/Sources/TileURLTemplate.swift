import Foundation

enum TileURLTemplate {
    private static let allowedSubdomains = ["a", "b", "c"]

    static func url(template: String, x: Int, y: Int, z: Int) -> URL? {
        guard x >= 0, y >= 0, (0...22).contains(z) else { return nil }
        let subdomain = allowedSubdomains[(x + y) % allowedSubdomains.count]
        let rendered = template
            .replacingOccurrences(of: "{s}", with: subdomain)
            .replacingOccurrences(of: "{z}", with: String(z))
            .replacingOccurrences(of: "{x}", with: String(x))
            .replacingOccurrences(of: "{y}", with: String(y))
        guard !rendered.contains("{"),
              let url = URL(string: rendered),
              url.scheme == "https",
              url.host != nil else { return nil }
        return url
    }
}
