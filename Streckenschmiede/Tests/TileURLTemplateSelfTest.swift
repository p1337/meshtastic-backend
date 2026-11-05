import Foundation

@main
struct TileURLTemplateSelfTest {
    static func main() {
        require(
            TileURLTemplate.url(
                template: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                x: 8,
                y: 5,
                z: 4
            )?.absoluteString == "https://tile.openstreetmap.org/4/8/5.png",
            "OSM template must render exact HTTPS tile URL"
        )
        require(
            TileURLTemplate.url(
                template: "https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png",
                x: 1,
                y: 1,
                z: 12
            )?.absoluteString == "https://c.tile-cyclosm.openstreetmap.fr/cyclosm/12/1/1.png",
            "CyclOSM template must choose a stable approved subdomain"
        )
        require(
            TileURLTemplate.url(
                template: "http://tile.openstreetmap.org/{z}/{x}/{y}.png",
                x: 0,
                y: 0,
                z: 0
            ) == nil,
            "Non-HTTPS tile URLs must be rejected"
        )
        require(
            TileURLTemplate.url(
                template: "https://example.invalid/{unknown}/{z}/{x}/{y}.png",
                x: 0,
                y: 0,
                z: 0
            ) == nil,
            "Unresolved template variables must be rejected"
        )
        require(
            TileURLTemplate.url(
                template: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                x: -1,
                y: 0,
                z: 0
            ) == nil,
            "Invalid tile coordinates must be rejected"
        )
        print("Tile URL template tests passed")
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
