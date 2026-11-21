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

    func testExplicitPredictionCanUseAStationarySlide() {
        var history = EditHistory()
        XCTAssertNil(history.currentContext)
        _ = history.observe(snapshot(0))
        XCTAssertEqual(history.currentContext?.previous, [])
        XCTAssertEqual(history.currentContext?.current, snapshot(0))
        _ = history.observe(snapshot(4))
        history.recordDismissal("Move left", on: snapshot(4))
        XCTAssertEqual(history.currentContext?.previous, [snapshot(0)])
        XCTAssertEqual(history.currentContext?.recentlyDismissed, ["Move left"])
    }

    func testModelSeesTextRangesAcrossAnEdit() throws {
        var history = EditHistory()
        var before = snapshot(0)
        before.textSelection = TextSelection(offset: 2, length: 3)
        _ = history.observe(before)
        var after = snapshot(5)
        after.textSelection = TextSelection(offset: 5, length: 0)
        let context = history.observe(after)
        let data = try JSONEncoder().encode(context)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let step = (json?["transitions"] as? [[String: Any]])?.first
        XCTAssertEqual(step?["textSelectionBefore"] as? [String: Int], ["offset": 2, "length": 3])
        XCTAssertEqual(step?["textSelectionAfter"] as? [String: Int], ["offset": 5, "length": 0])
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

    func testReturningToUnchangedPageRestoresOnlyItsHistory() {
        var history = EditHistory()
        _ = history.observe(snapshot(0))
        _ = history.observe(snapshot(8))
        _ = history.observe(snapshot(90, slide: 2))
        XCTAssertNil(history.observe(snapshot(8)))
        XCTAssertEqual(history.observe(snapshot(16))?.previous, [snapshot(0), snapshot(8)])
        _ = history.observe(snapshot(90, slide: 2))
        XCTAssertNil(history.observe(snapshot(99)))
        XCTAssertEqual(history.currentContext?.previous, [])
        _ = history.observe(snapshot(90, slide: 2, document: "other"))
        XCTAssertNil(history.observe(snapshot(99)))
        XCTAssertEqual(history.currentContext?.previous, [])
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
