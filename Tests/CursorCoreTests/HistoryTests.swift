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

    func testDocumentAndSlideChangesReseedContext() {
        var history = EditHistory()
        _ = history.observe(snapshot(0))
        XCTAssertNil(history.observe(snapshot(1, slide: 2)))
        XCTAssertNil(history.observe(snapshot(2, slide: 2, document: "other")))
        history.reset()
        XCTAssertNil(history.current)
    }
}
