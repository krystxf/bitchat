import MapKit
import SwiftUI

struct GeohashMapCluster: Identifiable {
    let geohash: String
    let peopleCount: Int
    var id: String { geohash }
    var coordinate: CLLocationCoordinate2D {
        let center = Geohash.decodeCenter(geohash)
        return CLLocationCoordinate2D(latitude: center.lat, longitude: center.lon)
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct MapKitGlobePickerView: View {
    let onSelect: (String) -> Void
    let onCancel: () -> Void
    private let clusters: [GeohashMapCluster]
    @State private var position: MapCameraPosition
    @State private var camera: MapCamera
    @State private var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 20, longitude: 0), span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360))
    @State private var selectedGeohash: String
    @State private var precision: Int
    @ThemedPalette private var palette

    private enum Strings {
        static let title: LocalizedStringKey = "location_channels.action.teleport"
        static let instruction = String(localized: "geohash_picker.instruction", defaultValue: "Drag to spin · Pinch to zoom · Tap to focus", comment: "Hint at the top of the globe geohash picker explaining its gestures")
        static let noSelection = String(localized: "geohash_picker.no_selection", defaultValue: "Select location", comment: "Shown in the globe geohash picker before a geohash is under the crosshair")
        static let select = String(localized: "geohash_picker.select", defaultValue: "Select", comment: "Button in the globe geohash picker that teleports to the geohash under the crosshair")
        static let selectHint = String(localized: "geohash_picker.accessibility.select", defaultValue: "Select Geohash", comment: "Accessibility label for the globe picker's select button")
        static let decrease = String(localized: "geohash_picker.accessibility.decrease_precision", defaultValue: "Decrease Precision", comment: "Accessibility label for the globe picker button that zooms out to a larger geohash cell")
        static let increase = String(localized: "geohash_picker.accessibility.increase_precision", defaultValue: "Increase Precision", comment: "Accessibility label for the globe picker button that zooms in to a smaller geohash cell")
    }

    init(initialGeohash: String?, nearbyGeohashes: [String], clusters: [GeohashMapCluster], onSelect: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onSelect = onSelect
        self.onCancel = onCancel
        self.clusters = clusters
        let target = GeohashPickerView.initialTarget(initialGeohash: initialGeohash, nearbyGeohashes: nearbyGeohashes)
        let center = CLLocationCoordinate2D(latitude: target.lat, longitude: target.lon)
        let startCamera = MapCamera(centerCoordinate: center, distance: 28_000_000, heading: 0, pitch: 0)
        _camera = State(initialValue: startCamera)
        _position = State(initialValue: .camera(startCamera))
        _precision = State(initialValue: target.precision)
        _selectedGeohash = State(initialValue: Geohash.encode(latitude: target.lat, longitude: target.lon, precision: target.precision))
    }

    var body: some View {
        ZStack {
            map
            VStack(spacing: 0) {
                Text(Strings.instruction)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassSurface(in: Capsule())
                clusterList
                Spacer(minLength: 0)
                bottomControls
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 20)
        }
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .sheetChrome(title: Text(Strings.title), onClose: onCancel)
        // Space around the globe is black in light mode too, so the title,
        // the controls and the status bar always use dark mode here. It
        // applies to this sheet only, not to the window under it.
        .preferredColorScheme(.dark)
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 640)
        #endif
        .accessibilityElement(children: .contain)
    }

    private var map: some View {
        MapReader { proxy in
            Map(position: $position) {
                ForEach(visibleCells) { cell in
                    let selected = cell.geohash == selectedGeohash
                    MapPolygon(coordinates: cell.coordinates)
                        .foregroundStyle(selected ? palette.locationAccent.opacity(0.34) : palette.locationAccent.opacity(0.045))
                        .stroke(selected ? palette.locationAccent : palette.locationAccent.opacity(0.4), lineWidth: selected ? 2 : 0.7)
                }
                ForEach(clusters.filter { $0.peopleCount > 0 }) { cluster in
                    Annotation("#\(cluster.geohash), \(cluster.peopleCount)", coordinate: cluster.coordinate, anchor: .bottom) {
                        Button { select(cluster.geohash) } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "person.2.fill")
                                Text("\(cluster.peopleCount)")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(Color.novaBackground.opacity(0.92), in: Capsule())
                            .overlay(Capsule().stroke(palette.locationAccent, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: "#\(cluster.geohash), \(cluster.peopleCount)"))
                    }
                }
            }
            // The imagery globe draws its own sky: real stars around the limb
            // that track the camera. An overlay would duplicate them over Earth.
            .mapStyle(.imagery(elevation: .realistic))
            .onMapCameraChange(frequency: .continuous) { context in
                camera = context.camera
                region = context.region
                precision = GeohashMapGeometry.precision(forLatitudeSpan: context.region.span.latitudeDelta)
                selectedGeohash = GeohashMapGeometry.geohash(
                    latitude: context.camera.centerCoordinate.latitude,
                    longitude: context.camera.centerCoordinate.longitude,
                    precision: precision
                )
            }
            .gesture(SpatialTapGesture().onEnded { event in
                guard let coordinate = proxy.convert(event.location, from: .local) else { return }
                selectedGeohash = GeohashMapGeometry.geohash(latitude: coordinate.latitude, longitude: coordinate.longitude, precision: precision)
            })
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var clusterList: some View {
        let active = clusters.filter { $0.peopleCount > 0 }
        if !active.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(active) { cluster in
                        Button { select(cluster.geohash) } label: {
                            Label {
                                Text(verbatim: "#\(cluster.geohash) · \(cluster.peopleCount)")
                            } icon: {
                                Image(systemName: "person.2.fill")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassSurface(in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: "#\(cluster.geohash), \(cluster.peopleCount)"))
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private var visibleCells: [GeohashMapGeometry.Cell] {
        let south = max(-90, region.center.latitude - region.span.latitudeDelta / 2)
        let north = min(90, region.center.latitude + region.span.latitudeDelta / 2)
        let left = region.center.longitude - region.span.longitudeDelta / 2
        let right = region.center.longitude + region.span.longitudeDelta / 2
        if left < -180 {
            return GeohashMapGeometry.cells(south: south, north: north, west: -180, east: right, precision: precision)
                + GeohashMapGeometry.cells(south: south, north: north, west: left + 360, east: 180, precision: precision)
        }
        if right > 180 {
            return GeohashMapGeometry.cells(south: south, north: north, west: left, east: 180, precision: precision)
                + GeohashMapGeometry.cells(south: south, north: north, west: -180, east: right - 360, precision: precision)
        }
        return GeohashMapGeometry.cells(south: south, north: north, west: left, east: right, precision: precision)
    }

    /// The selection and its actions in one floating card, as Maps puts
    /// a place's actions under it.
    private var bottomControls: some View {
        GlobePickerControls(
            title: selectedGeohash.isEmpty ? Strings.noSelection : "#\(selectedGeohash)",
            subtitle: selectedGeohash.isEmpty ? nil : "\(GeohashCoverage.level(forLength: selectedGeohash.count).displayName) • \(GeohashCoverage.string(forPrecision: selectedGeohash.count))",
            selectTitle: Strings.select,
            selectLabel: Strings.selectHint,
            decreaseLabel: Strings.decrease,
            increaseLabel: Strings.increase,
            canSelect: !selectedGeohash.isEmpty,
            onDecrease: { adjustPrecision(-1) },
            onIncrease: { adjustPrecision(1) },
            onSelect: {
                guard !selectedGeohash.isEmpty else { return }
                onSelect(selectedGeohash)
            }
        )
    }

    private func adjustPrecision(_ delta: Int) {
        let next = min(max(precision + delta, 1), GlobeMath.maxPrecision)
        guard next != precision else { return }
        precision = next
        selectedGeohash = Geohash.encode(latitude: camera.centerCoordinate.latitude, longitude: camera.centerCoordinate.longitude, precision: next)
        let factor = delta > 0 ? 0.42 : 2.25
        camera = MapCamera(centerCoordinate: camera.centerCoordinate, distance: max(700, min(40_000_000, camera.distance * factor)), heading: camera.heading, pitch: camera.pitch)
        position = .camera(camera)
    }

    private func select(_ hash: String) {
        guard Geohash.isValidGeohash(hash) else { return }
        selectedGeohash = hash
        precision = hash.count
    }
}

/// The globe picker's bottom card: the cell under the crosshair, the
/// precision steppers and the select button. Shared by the MapKit globe and
/// the drawn one (iOS 16).
struct GlobePickerControls: View {
    let title: String
    let subtitle: String?
    let selectTitle: String
    let selectLabel: String
    let decreaseLabel: String
    let increaseLabel: String
    let canSelect: Bool
    let onDecrease: () -> Void
    let onIncrease: () -> Void
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(verbatim: title)
                    .font(.headline)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(.footnote)
                        .foregroundStyle(.novaSecondaryText)
                }
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)

            HStack(spacing: 12) {
                stepButton("minus", label: decreaseLabel, action: onDecrease)
                stepButton("plus", label: increaseLabel, action: onIncrease)
                Button(action: onSelect) {
                    Label(selectTitle, systemImage: "checkmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .glassButtonStyle(prominent: true)
                .controlSize(.large)
                .disabled(!canSelect)
                .accessibilityLabel(selectLabel)
            }
        }
        .padding(16)
        .frame(maxWidth: 420)
        .glassSurface(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func stepButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline)
                .frame(width: 24, height: 24)
        }
        .glassButtonStyle()
        .circularButtonShape()
        .controlSize(.large)
        .accessibilityLabel(label)
    }
}
