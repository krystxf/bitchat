import CoreLocation
import Foundation

/// Pure geometry used by the MapKit picker. It bounds work to the visible map region.
enum GeohashMapGeometry {
    struct Cell: Identifiable, Equatable {
        let geohash: String
        let south: Double
        let north: Double
        let west: Double
        let east: Double

        var id: String { geohash }

        var coordinates: [CLLocationCoordinate2D] {
            [
                CLLocationCoordinate2D(latitude: south, longitude: west),
                CLLocationCoordinate2D(latitude: south, longitude: east),
                CLLocationCoordinate2D(latitude: north, longitude: east),
                CLLocationCoordinate2D(latitude: north, longitude: west)
            ]
        }
    }

    static func cells(
        south: Double, north: Double, west: Double, east: Double,
        precision: Int, limit: Int = 700
    ) -> [Cell] {
        guard precision > 0, limit > 0,
              south.isFinite, north.isFinite, west.isFinite, east.isFinite,
              south < north, west <= east else { return [] }
        let latStep = GlobeMath.cellSpanLat(precision: precision)
        let lonStep = GlobeMath.cellSpanLon(precision: precision)
        guard latStep > 0, lonStep > 0 else { return [] }
        let firstLat = max(-90, floor((max(-90, south) + 90) / latStep) * latStep - 90)
        let firstLon = max(-180, floor((max(-180, west) + 180) / lonStep) * lonStep - 180)
        var result: [Cell] = []
        var seen = Set<String>()
        var lat = firstLat
        while lat < min(90, north), result.count < limit {
            var lon = firstLon
            while lon <= min(180, east), result.count < limit {
                let centerLat = min(90, lat + latStep / 2)
                let centerLon = min(180, lon + lonStep / 2)
                let hash = Geohash.encode(latitude: centerLat, longitude: centerLon, precision: precision)
                if seen.insert(hash).inserted {
                    let bounds = Geohash.decodeBounds(hash)
                    result.append(Cell(geohash: hash, south: bounds.latMin, north: bounds.latMax,
                                       west: bounds.lonMin, east: bounds.lonMax))
                }
                lon += lonStep
            }
            lat += latStep
        }
        return result
    }

    /// Uses the same 22% visible-cell threshold as the Canvas globe's auto zoom rule.
    static func precision(forLatitudeSpan visibleSpan: Double) -> Int {
        guard visibleSpan.isFinite, visibleSpan > 0 else { return 2 }
        let targetCellSpan = visibleSpan * 0.22
        var best = 1
        for candidate in 1...GlobeMath.maxPrecision {
            guard GlobeMath.cellSpanLat(precision: candidate) >= targetCellSpan else { break }
            best = candidate
        }
        return best
    }

    static func geohash(latitude: Double, longitude: Double, precision: Int) -> String {
        guard latitude.isFinite, longitude.isFinite, precision > 0 else { return "" }
        return Geohash.encode(latitude: latitude, longitude: longitude, precision: precision)
    }
}

/// Small, deterministic camera-to-sky mapping. Longitude and heading wrap seamlessly.
enum GlobeParallax {
    static func offset(longitude: Double, latitude: Double, heading: Double, size: CGSize, reduceMotion: Bool) -> CGSize {
        guard !reduceMotion, size.width.isFinite, size.height.isFinite else { return .zero }
        let x = wrapped(longitude + heading) / 360 * Double(size.width)
        let y = min(max(-latitude / 180 * Double(size.height), -Double(size.height) / 2), Double(size.height) / 2)
        return CGSize(width: -x, height: y)
    }

    static func wrapped(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}
