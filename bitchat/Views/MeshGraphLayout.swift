import Foundation

/// Platform independent force layout used by the mesh graph.
struct MeshGraphLayout {
    struct Point: Equatable {
        var x: Double
        var y: Double
    }

    private(set) var positions: [String: Point] = [:]
    private var velocities: [String: Point] = [:]
    private var dragged: Set<String> = []
    private(set) var bounds = Point(x: 1000, y: 1000)

    var isMoving: Bool { velocities.values.contains { hypot($0.x, $0.y) > 0.12 } }

    mutating func setBounds(width: Double, height: Double) {
        let newBounds = Point(x: max(1, width), y: max(1, height))
        let scaleX = newBounds.x / bounds.x, scaleY = newBounds.y / bounds.y
        for id in positions.keys {
            if let point = positions[id] {
                positions[id] = Point(x: point.x * scaleX, y: point.y * scaleY)
            }
        }
        bounds = newBounds
        clampAll()
    }

    mutating func update(nodes: [String], edges: [(String, String)]) {
        let ids = Set(nodes)
        positions = positions.filter { ids.contains($0.key) }
        velocities = velocities.filter { ids.contains($0.key) }
        dragged.formIntersection(ids)
        let center = Point(x: bounds.x / 2, y: bounds.y / 2)
        for (index, id) in nodes.enumerated() where positions[id] == nil {
            let angle = Double(index) * 2.399963229728653
            let radius = 22 + Double(index % 5) * 7
            positions[id] = Point(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            velocities[id] = Point(x: cos(angle) * 2, y: sin(angle) * 2)
        }
        _ = edges
    }

    mutating func move(_ id: String, to point: Point) {
        guard positions[id] != nil else { return }
        dragged.insert(id)
        positions[id] = point
        velocities[id] = Point(x: 0, y: 0)
        clamp(id)
    }

    mutating func release(_ id: String) { dragged.remove(id) }

    mutating func settle(nodes: [String], edges: [(String, String)], iterations: Int = 1) {
        for _ in 0..<max(0, iterations) { step(nodes: nodes, edges: edges) }
    }

    mutating func step(nodes: [String], edges: [(String, String)]) {
        update(nodes: nodes, edges: edges)
        let ids = nodes
        var forces = Dictionary(uniqueKeysWithValues: ids.map { ($0, Point(x: 0, y: 0)) })
        func add(_ id: String, _ x: Double, _ y: Double) { forces[id]!.x += x; forces[id]!.y += y }
        if ids.count > 1 {
            for i in 0..<(ids.count - 1) { for j in (i + 1)..<ids.count {
                let a = positions[ids[i]]!, b = positions[ids[j]]!
                var dx = a.x - b.x, dy = a.y - b.y
                var d2 = dx * dx + dy * dy
                if d2 < 1 { dx += 0.01; dy += 0.01; d2 = dx * dx + dy * dy }
                let d = sqrt(d2), f = min(14, 2400 / d2)
                add(ids[i], dx / d * f, dy / d * f); add(ids[j], -dx / d * f, -dy / d * f)
            } }
        }
        for (aID, bID) in edges where positions[aID] != nil && positions[bID] != nil {
            let a = positions[aID]!, b = positions[bID]!, dx = b.x-a.x, dy = b.y-a.y
            let d = max(0.01, hypot(dx, dy)), f = (d - 82) * 0.012
            add(aID, dx/d*f, dy/d*f); add(bID, -dx/d*f, -dy/d*f)
        }
        for id in ids where !dragged.contains(id) {
            let p = positions[id]!, centerX = bounds.x/2, centerY = bounds.y/2
            let f = forces[id]!
            var v = velocities[id] ?? Point(x: 0, y: 0)
            v.x += f.x - (p.x-centerX)*0.018; v.y += f.y - (p.y-centerY)*0.018
            let speed = hypot(v.x, v.y)
            if speed > 12 { v.x *= 12/speed; v.y *= 12/speed }
            positions[id] = Point(x: p.x+v.x, y: p.y+v.y)
            velocities[id] = Point(x: v.x*0.78, y: v.y*0.78)
            clamp(id)
        }
    }

    private mutating func clampAll() { for id in positions.keys { clamp(id) } }
    private mutating func clamp(_ id: String) {
        guard var p = positions[id] else { return }
        p.x = min(bounds.x-18, max(18, p.x)); p.y = min(bounds.y-18, max(18, p.y))
        positions[id] = p
    }
}
