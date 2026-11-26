import SwiftUI
import BitFoundation

struct MeshTopologyDisplayModel {
    struct Node: Identifiable, Equatable {
        let id: String
        let label: String
        let isSelf: Bool
    }
    let nodes: [Node]
    let edges: [(String, String)]
    static let empty = MeshTopologyDisplayModel(nodes: [], edges: [])
}

struct MeshTopologyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ThemedPalette private var palette
    let provider: @MainActor () -> MeshTopologyDisplayModel
    @State private var model: MeshTopologyDisplayModel = .empty
    @State private var layout = MeshGraphLayout()
    @State private var selectedID: String?
    @State private var zoom = 1.0
    @State private var zoomStart = 1.0
    @State private var pan = CGSize.zero
    @State private var panStart = CGSize.zero
    @State private var draggingID: String?
    @State private var dragStart: CGPoint = .zero

    var body: some View {
        content
            .sheetChrome(title: Text("topology.title"), onClose: { dismiss() }) { refreshButton }
            #if os(macOS)
            .frame(width: 600, height: 600)
            #else
            .presentationDetents([.medium, .large])
            #endif
            .onAppear { refresh() }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(8))
                    guard !Task.isCancelled else { break }
                    refresh()
                }
            }
            #if os(macOS)
            .popover(item: selectedNodeBinding, arrowEdge: .bottom) { node in detail(node) }
            #else
            .sheet(item: selectedNodeBinding) { node in detail(node).presentationDetents([.height(230)]) }
            #endif
    }

    private var selectedNodeBinding: Binding<MeshTopologyDisplayModel.Node?> {
        Binding(get: { model.nodes.first { $0.id == selectedID } }, set: { selectedID = $0?.id })
    }

    private var refreshButton: some View {
        HStack(spacing: 8) {
            Button(action: fit) { Label("Fit", systemImage: "arrow.up.left.and.arrow.down.right") }
            Button(action: refresh) { Label("topology.refresh", systemImage: "arrow.clockwise") }
        }
    }

    private var content: some View {
        VStack(spacing: 8) {
            if model.nodes.count <= 1 {
                Spacer(); Text("topology.empty").bitchatFont(size: 14).foregroundColor(palette.secondary); Spacer()
            } else {
                GeometryReader { proxy in
                    let size = proxy.size
                    TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion || !layout.isMoving)) { _ in
                        let _ = advanceLayout()
                        ZStack {
                            graph(size: size)
                            ForEach(model.nodes) { node in
                                nodeView(node)
                                    .position(point(for: node, size: size))
                                    .gesture(nodeDrag(node, size: size))
                                    .onTapGesture { selectedID = node.id }
                                    .accessibilityElement()
                                    .accessibilityLabel("\(node.label), \(node.id)")
                                    .accessibilityHint("Double tap for peer details. Drag to move.")
                                    .accessibilityAddTraits(.isButton)
                            }
                        }
                        .scaleEffect(zoom)
                        .offset(pan)
                        .contentShape(Rectangle())
                        .gesture(backgroundDrag)
                        .simultaneousGesture(MagnificationGesture().onChanged { zoom = min(3, max(0.45, zoomStart * $0)) }.onEnded { _ in zoomStart = zoom })
                        .onAppear {
                            layout.setBounds(width: size.width, height: size.height)
                            layout.update(nodes: model.nodes.map(\.id), edges: model.edges)
                            if reduceMotion { layout.settle(nodes: model.nodes.map(\.id), edges: model.edges, iterations: 160) }
                        }
                        .onChange(of: size) { newSize in layout.setBounds(width: newSize.width, height: newSize.height) }
                        .onChange(of: model.nodes.map(\.id)) { ids in
                            layout.update(nodes: ids, edges: model.edges)
                            if reduceMotion { layout.settle(nodes: ids, edges: model.edges, iterations: 160) }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            Text(summaryText).bitchatFont(size: 13, weight: .semibold).foregroundColor(palette.primary)
            Text("topology.caption").bitchatFont(size: 11).foregroundColor(palette.secondary).multilineTextAlignment(.center).padding(.bottom, 12)
        }
        .accessibilityElement(children: .contain)
    }

    private func graph(size: CGSize) -> some View {
        Canvas { context, _ in
            for (a, b) in model.edges {
                guard let p1 = layout.positions[a], let p2 = layout.positions[b] else { continue }
                var path = Path(); path.move(to: CGPoint(x: p1.x, y: p1.y)); path.addLine(to: CGPoint(x: p2.x, y: p2.y))
                let highlighted = selectedID == a || selectedID == b
                context.stroke(path, with: .color(highlighted ? palette.accent : palette.secondary.opacity(0.48)), style: StrokeStyle(lineWidth: highlighted ? 2.5 : 1.2, dash: [5, 4]))
            }
        }
    }

    @ViewBuilder private func nodeView(_ node: MeshTopologyDisplayModel.Node) -> some View {
        let size: CGFloat = node.isSelf ? 42 : 34
        ZStack {
            AvatarDisc(seed: node.id).frame(width: size, height: size)
                .overlay(Text(AvatarIdentity.initials(for: node.label)).font(.system(size: size * 0.38, weight: .semibold, design: .rounded)).foregroundStyle(.white))
            if node.isSelf { Circle().stroke(palette.accent, lineWidth: 2).frame(width: size + 7, height: size + 7) }
            if selectedID == node.id { Circle().stroke(palette.accent.opacity(0.7), lineWidth: 2).frame(width: size + 12, height: size + 12) }
        }
        .overlay(alignment: .bottom) { Text(verbatim: node.label).font(.system(size: 10)).foregroundStyle(palette.primary).lineLimit(1).fixedSize().offset(y: 15) }
        .frame(width: 58, height: 58)
        .contentShape(Circle())
    }

    private func detail(_ node: MeshTopologyDisplayModel.Node) -> some View {
        VStack(spacing: 12) {
            InitialsAvatar(name: node.label, seed: node.id, size: 48)
            Text(verbatim: node.label).font(.headline)
            Text(node.isSelf ? "You" : "Peer ID · \(node.id.prefix(12))…").font(.subheadline).foregroundStyle(.secondary)
            Text(node.isSelf ? "This device" : "Mesh peer · topology link information is advisory").font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(minWidth: 220)
    }

    private var backgroundDrag: some Gesture {
        DragGesture(minimumDistance: 6).onChanged { value in
            if draggingID == nil { pan = CGSize(width: panStart.width + value.translation.width, height: panStart.height + value.translation.height) }
        }.onEnded { _ in panStart = pan }
    }

    private func nodeDrag(_ node: MeshTopologyDisplayModel.Node, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4).onChanged { value in
            if draggingID == nil { draggingID = node.id; dragStart = value.startLocation }
            guard draggingID == node.id else { return }
            let origin = layout.positions[node.id] ?? .init(x: size.width/2, y: size.height/2)
            layout.move(node.id, to: .init(x: origin.x + value.translation.width / zoom, y: origin.y + value.translation.height / zoom))
        }.onEnded { _ in if draggingID == node.id { layout.release(node.id); draggingID = nil } }
    }

    private func point(for node: MeshTopologyDisplayModel.Node, size: CGSize) -> CGPoint {
        let p = layout.positions[node.id] ?? .init(x: size.width/2, y: size.height/2)
        return CGPoint(x: p.x, y: p.y)
    }

    private var summaryText: String {
        String(format: String(localized: "topology.summary", comment: "Topology map summary: number of peers and links"), locale: .current, model.nodes.count, model.edges.count)
    }

    private func refresh() {
        model = provider()
        layout.update(nodes: model.nodes.map(\.id), edges: model.edges)
        if reduceMotion { layout.settle(nodes: model.nodes.map(\.id), edges: model.edges, iterations: 160) }
    }

    private func fit() { zoom = 1; zoomStart = 1; pan = .zero; panStart = .zero }

    private func advanceLayout() {
        if !reduceMotion { layout.step(nodes: model.nodes.map(\.id), edges: model.edges) }
    }

    /// Kept for callers that need a deterministic initial preview layout.
    static func layout(nodes: [MeshTopologyDisplayModel.Node], in size: CGSize) -> [String: CGPoint] {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = max(20, min(size.width, size.height) / 2 - 36)
        let ringNodes = nodes.filter { !$0.isSelf }
        var result: [String: CGPoint] = [:]
        for node in nodes where node.isSelf { result[node.id] = center }
        for (index, node) in ringNodes.enumerated() {
            let angle = 2 * CGFloat.pi * CGFloat(index) / CGFloat(max(1, ringNodes.count)) - CGFloat.pi / 2
            result[node.id] = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
        return result
    }
}
