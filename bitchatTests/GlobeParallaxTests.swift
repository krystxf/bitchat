import CoreGraphics
import Testing
@testable import bitchat

struct GlobeParallaxTests {
    private let size = CGSize(width: 400, height: 800)

    private func offset(_ longitude: Double, _ latitude: Double) -> CGSize {
        GlobeParallax.offset(longitude: longitude, latitude: latitude, size: size, reduceMotion: false)
    }

    @Test func cameraTravelSwingsTheSkyTheOtherWayOnBothAxes() {
        let start = offset(10, 10)
        let east = offset(20, 10)
        let north = offset(10, 20)

        // East slides Earth left and the sky right; north slides Earth down and the sky up.
        #expect(east.width > start.width)
        #expect(east.height == start.height)
        #expect(north.height < start.height)
        #expect(north.width == start.width)
        #expect(east.width - start.width == start.height - north.height)
    }

    @Test func longitudeWrapsWithoutASeam() {
        let fieldWidth = Double(size.width)
        let justWest = offset(-0.5, 0).width
        let justEast = offset(0.5, 0).width
        var step = (justEast - justWest).truncatingRemainder(dividingBy: fieldWidth)
        if step < 0 { step += fieldWidth }

        #expect(abs(step - (offset(1, 0).width - offset(0, 0).width)) < 1e-9)
        #expect(offset(450, 30) == offset(90, 30))
        #expect(offset(-270, 30) == offset(90, 30))
    }

    @Test func reduceMotionAndBadInputKeepTheSkyStill() {
        #expect(GlobeParallax.offset(longitude: 90, latitude: 45, size: size, reduceMotion: true) == .zero)
        #expect(GlobeParallax.offset(longitude: .nan, latitude: 45, size: size, reduceMotion: false) == .zero)
        #expect(GlobeParallax.offset(longitude: 90, latitude: .infinity, size: size, reduceMotion: false) == .zero)
        #expect(GlobeParallax.offset(longitude: 90, latitude: 45, size: .zero, reduceMotion: false) == .zero)
    }

    @MainActor
    @Test func skyDriftsAgainstTheFingerAndSlowerThanIt() {
        let state = GlobeState(targetLat: 0, targetLon: 0, initialPrecision: 2, startZoomedOut: false)
        state.setViewport(baseRadius: 170, screenMin: 390)
        let view = CGSize(width: 390, height: 844)
        func sky() -> CGSize {
            GlobeParallax.offset(longitude: state.centerLon, latitude: state.centerLat, size: view, reduceMotion: false)
        }

        // The field wraps at the view edges, so compare the drift the eye sees.
        func drift(_ from: CGFloat, _ to: CGFloat, extent: CGFloat) -> CGFloat {
            var delta = (to - from).truncatingRemainder(dividingBy: extent)
            if delta > extent / 2 { delta -= extent }
            if delta < -extent / 2 { delta += extent }
            return delta
        }

        // Longitude 0 puts the first drag across the wrap seam.
        let start = sky()
        state.rotateBy(dx: 30, dy: 0)
        let afterRight = sky()
        state.rotateBy(dx: 0, dy: 30)
        let afterDown = sky()

        let rightDrift = drift(start.width, afterRight.width, extent: view.width)
        let downDrift = drift(afterRight.height, afterDown.height, extent: view.height)
        #expect(rightDrift < 0 && rightDrift > -30)
        #expect(downDrift < 0 && downDrift > -30)
        #expect(abs(rightDrift - downDrift) < 1e-9)
    }
}
