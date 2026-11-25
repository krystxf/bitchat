import MapKit
import SwiftUI

/// The MapKit globe is opaque, so the sky is drawn only in the corners beyond
/// its limb. A fixed seed keeps the field stable between picker presentations.
@available(iOS 17.0, macOS 14.0, *)
struct MapKitGlobeStarfield: View {
    let color: Color
    let camera: MapCamera
    let reduceMotion: Bool

    private struct Star {
        let x: CGFloat
        let y: CGFloat
        let radius: CGFloat
        let alpha: Double
    }

    private static let stars: [Star] = (0..<180).map { index in
        var value = UInt64(index) &+ 0x9E3779B97F4A7C15
        func next(_ value: inout UInt64) -> Double {
            value &+= 0x9E3779B97F4A7C15
            var z = value
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
        return Star(x: next(&value), y: next(&value), radius: 0.7 + next(&value) * 1.3, alpha: 0.2 + next(&value) * 0.55)
    }

    var body: some View {
        Canvas { context, size in
            guard camera.distance > 9_000_000 else { return }
            let offset = GlobeParallax.offset(longitude: camera.centerCoordinate.longitude,
                                              latitude: camera.centerCoordinate.latitude,
                                              heading: camera.heading,
                                              size: size,
                                              reduceMotion: reduceMotion)
            let radius = min(size.width, size.height) * 0.47
            for star in Self.stars {
                let x = wrapped(star.x * size.width + offset.width, extent: size.width)
                let y = wrapped(star.y * size.height + offset.height, extent: size.height)
                for xCopy in -1...1 {
                    for yCopy in -1...1 {
                        let point = CGPoint(x: x + CGFloat(xCopy) * size.width,
                                            y: y + CGFloat(yCopy) * size.height)
                        let dx = point.x - size.width / 2
                        let dy = point.y - size.height / 2
                        guard dx * dx + dy * dy > radius * radius else { continue }
                        let rect = CGRect(x: point.x - star.radius,
                                          y: point.y - star.radius,
                                          width: star.radius * 2,
                                          height: star.radius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(color.opacity(star.alpha)))
                    }
                }
            }
        }
    }

    private func wrapped(_ value: CGFloat, extent: CGFloat) -> CGFloat {
        guard extent > 0 else { return value }
        let remainder = value.truncatingRemainder(dividingBy: extent)
        return remainder < 0 ? remainder + extent : remainder
    }
}
