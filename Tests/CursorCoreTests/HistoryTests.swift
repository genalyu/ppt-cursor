import XCTest
@testable import CursorCore

final class HistoryTests: XCTestCase {
    func snapshot(_ x: Double, slide: Int = 1, document: String = "demo") -> SlideSnapshot {
        SlideSnapshot(document: document, slideID: slide, width: 960, height: 540,
                      objects: [SlideObject(id: "42", kind: "shape", name: "Title", text: nil,
                                            x: x, y: 20, width: 100, height: 64, rotation: 0)])
    }

    func testRealChangesOnlyAndBoundedHistory() {
        var history = EditHistory(limit: 3)
        XCTAssertNil(history.observe(snapshot(0)))
        XCTAssertNil(history.observe(snapshot(0)))
        for x in 1...3 { XCTAssertNotNil(history.observe(snapshot(Double(x)))) }
        let context = history.observe(snapshot(4))
        XCTAssertEqual(context?.previous, [snapshot(2), snapshot(3)])
        XCTAssertEqual(context?.current, snapshot(4))
    }

    func testSelectionUpdatesContextWithoutInventingAnEdit() {
        var history = EditHistory()
        var selected = snapshot(0)
        _ = history.observe(selected)
        selected.selectedIDs = ["42"]
        XCTAssertNil(history.observe(selected))
        let next = history.observe(snapshot(5))
        XCTAssertEqual(next?.previous, [selected])
    }

    func testModelSeesOrderedChangesAndUnchangedObjectsOnlyOnce() throws {
        let stationary = SlideObject(id: "fixed", kind: "shape", name: "Background", text: nil,
                                    x: 0, y: 0, width: 960, height: 540, rotation: 0)
        func page(_ x: Double) -> SlideSnapshot {
            SlideSnapshot(document: "demo", slideID: 1, width: 960, height: 540,
                          objects: [stationary] + snapshot(x).objects)
        }
        let context = EditContext(previous: [page(10), page(20)], current: page(30))
        let data = try JSONEncoder().encode(context)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let steps = json?["transitions"] as? [[String: Any]]
        func positions(_ key: String) -> [Double]? {
            steps?.flatMap { ($0[key] as? [[String: Any]])?.compactMap { $0["x"] as? Double } ?? [] }
        }
        XCTAssertEqual(positions("before"), [10, 20])
        XCTAssertEqual(positions("after"), [20, 30])
        XCTAssertEqual(String(decoding: data, as: UTF8.self).components(separatedBy: "Background").count, 2)
    }

    func testDismissalsFollowRecentEditsOnOneSlide() {
        var history = EditHistory(limit: 3)
        _ = history.observe(snapshot(0))
        history.recordDismissal("Move left", on: snapshot(0))
        XCTAssertEqual(history.observe(snapshot(1))?.recentlyDismissed, ["Move left"])
        XCTAssertNil(history.observe(snapshot(1)))
        XCTAssertEqual(history.observe(snapshot(2))?.recentlyDismissed, ["Move left"])
        XCTAssertEqual(history.observe(snapshot(3))?.recentlyDismissed, [])
        history.recordDismissal("Move right", on: snapshot(3))
        XCTAssertNil(history.observe(snapshot(3, slide: 2)))
        XCTAssertEqual(history.observe(snapshot(4, slide: 2))?.recentlyDismissed, [])
    }

    func testDocumentIdentityStaysLocal() throws {
        let path = "/Users/example/Private/Quarterly.pptx"
        let current = snapshot(12, document: path)
        let context = EditContext(previous: [snapshot(0, document: path)], current: current)
        let data = try JSONEncoder().encode(context)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let page = json?["current"] as? [String: Any]
        XCTAssertNotNil(page?["objects"])
        XCTAssertNil(page?["document"])
        XCTAssertEqual(context.current.document, path)
    }

    func testDocumentAndSlideChangesReseedContext() {
        var history = EditHistory()
        _ = history.observe(snapshot(0))
        XCTAssertNil(history.observe(snapshot(1, slide: 2)))
        XCTAssertNil(history.observe(snapshot(2, slide: 2, document: "other")))
        history.reset()
        XCTAssertNil(history.current)
    }
}
