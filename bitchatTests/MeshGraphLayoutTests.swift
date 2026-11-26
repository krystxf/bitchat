import XCTest
@testable import bitchat

final class MeshGraphLayoutTests: XCTestCase {
    func testSimulationCreatesAndBoundsNodes() {
        var layout = MeshGraphLayout()
        layout.setBounds(width: 200, height: 140)
        layout.update(nodes: ["a", "b", "c"], edges: [("a", "b")])
        layout.settle(nodes: ["a", "b", "c"], edges: [("a", "b")], iterations: 30)
        XCTAssertEqual(Set(layout.positions.keys), ["a", "b", "c"])
        XCTAssertTrue(layout.positions.values.allSatisfy { $0.x >= 18 && $0.x <= 182 && $0.y >= 18 && $0.y <= 122 })
    }

    func testPinningKeepsNodeInPlaceWhileOthersMove() {
        var layout = MeshGraphLayout()
        layout.setBounds(width: 300, height: 300)
        let nodes = ["a", "b", "c"]
        let edges = [("a", "b"), ("b", "c")]
        layout.update(nodes: nodes, edges: edges)
        let pinned = MeshGraphLayout.Point(x: 70, y: 80)
        layout.move("a", to: pinned)
        layout.settle(nodes: nodes, edges: edges, iterations: 12)
        XCTAssertEqual(layout.positions["a"], pinned)
        layout.release("a")
        layout.settle(nodes: nodes, edges: edges, iterations: 12)
        XCTAssertNotEqual(layout.positions["a"], pinned)
    }

    func testUpdateRemovesStaleNodesWithoutResettingExistingPositions() {
        var layout = MeshGraphLayout()
        layout.setBounds(width: 300, height: 300)
        layout.update(nodes: ["a", "b"], edges: [])
        let original = layout.positions["a"]
        layout.update(nodes: ["a", "c"], edges: [])
        XCTAssertEqual(layout.positions["a"], original)
        XCTAssertNil(layout.positions["b"])
        XCTAssertNotNil(layout.positions["c"])
    }
}
