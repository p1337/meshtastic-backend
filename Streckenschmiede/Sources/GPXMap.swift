import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import CoreLocation
import MapKit

final class GPXParser: NSObject, XMLParserDelegate {
    private(set) var coordinates: [CLLocationCoordinate2D] = []
    private var lat: Double?
    private var lon: Double?
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "trkpt" || elementName == "rtept" {
            lat = attributeDict["lat"].flatMap(Double.init)
            lon = attributeDict["lon"].flatMap(Double.init)
            if let lat, let lon, (-90...90).contains(lat), (-180...180).contains(lon) {
                coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
        }
    }
    static func load(_ url: URL) throws -> [CLLocationCoordinate2D] {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let delegate = GPXParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), !delegate.coordinates.isEmpty else {
            throw NSError(domain: "Streckenschmiede", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "GPX enthält keine gültigen Streckenpunkte"])
        }
        return delegate.coordinates
    }
}

struct RouteMap: View {
    let coordinates: [CLLocationCoordinate2D]

    private var initialCamera: MapCameraPosition {
        guard let first = coordinates.first else { return .automatic }
        if coordinates.count == 1 {
            return .region(MKCoordinateRegion(
                center: first,
                latitudinalMeters: 1_000,
                longitudinalMeters: 1_000
            ))
        }
        // Fit the imported route, not the user's current GPS position.
        let line = MKPolyline(coordinates: coordinates, count: coordinates.count)
        return .rect(line.boundingMapRect)
    }

    var body: some View {
        Map(initialPosition: initialCamera) {
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates)
                    .stroke(.orange, lineWidth: 5)
            }
            if let start = coordinates.first {
                Annotation("Start", coordinate: start) {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(.orange)
                        .padding(7)
                        .background(.black.opacity(0.85), in: Circle())
                }
            }
            if coordinates.count > 1, let finish = coordinates.last {
                Annotation("Ziel", coordinate: finish) {
                    Image(systemName: "flag.checkered")
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(.black.opacity(0.85), in: Circle())
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityLabel("Streckenkarte mit Start und Ziel")
    }
}
