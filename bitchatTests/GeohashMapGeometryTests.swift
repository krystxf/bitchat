import CoreLocation
import Testing
@testable import bitchat

struct GeohashMapGeometryTests {
    @Test func cellsCoverOnlyTheRequestedRegionAtTheRequestedPrecision() {
        let cells = GeohashMapGeometry.cells(
            south: 37.70, north: 37.85, west: -122.52, east: -122.35, precision: 5
        )

        #expect(!cells.isEmpty)
        #expect(cells.count < 100)
        #expect(cells.allSatisfy { $0.geohash.count == 5 })
        #expect(cells.contains { $0.south <= 37.70 && $0.north >= 37.70 })
        #expect(cells.contains { $0.west <= -122.52 && $0.east >= -122.52 })
    }

    @Test func tapCoordinatesEncodeToTheExpectedCell() {
        let hash = GeohashMapGeometry.geohash(latitude: 37.7749, longitude: -122.4194, precision: 6)

        #expect(hash == Geohash.encode(latitude: 37.7749, longitude: -122.4194, precision: 6))
        #expect(hash == "9q8yyk")
        #expect(GeohashMapGeometry.geohash(latitude: .nan, longitude: 0, precision: 6).isEmpty)
    }

    @Test func parallaxWrapsAndMovesOppositeTheCamera() {
        let size = CGSize(width: 400, height: 800)
        let east = GlobeParallax.offset(longitude: 90, latitude: 45, heading: 0, size: size, reduceMotion: false)
        let wrapped = GlobeParallax.offset(longitude: 450, latitude: 45, heading: 0, size: size, reduceMotion: false)
        let motionless = GlobeParallax.offset(longitude: 90, latitude: 45, heading: 0, size: size, reduceMotion: true)

        #expect(east == wrapped)
        #expect(east.width < 0)
        #expect(east.height < 0)
        #expect(motionless == .zero)
    }
}
