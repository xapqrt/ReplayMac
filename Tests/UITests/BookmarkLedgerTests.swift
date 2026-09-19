import XCTest
@testable import UI

final class BookmarkLedgerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testMarksInsideTheClipWindowBecomeOffsetsFromClipStart() {
        var ledger = BookmarkLedger()
        ledger.add(at: t0.addingTimeInterval(-100))   // before the clip
        ledger.add(at: t0.addingTimeInterval(-25))    // 5 s into a 30 s clip
        ledger.add(at: t0.addingTimeInterval(-3))     // 27 s in
        ledger.add(at: t0.addingTimeInterval(10))     // after the clip

        let bookmarks = ledger.bookmarks(clipStart: t0.addingTimeInterval(-30), clipEnd: t0)

        XCTAssertEqual(bookmarks.map(\.seconds), [5, 27])
    }

    func testOffsetsAreClampedToTheClip() {
        var ledger = BookmarkLedger()
        ledger.add(at: t0.addingTimeInterval(-30))
        let bookmarks = ledger.bookmarks(clipStart: t0.addingTimeInterval(-30), clipEnd: t0)
        XCTAssertEqual(bookmarks.map(\.seconds), [0])
    }

    func testDoubleTapIsDebounced() {
        var ledger = BookmarkLedger()
        XCTAssertTrue(ledger.add(at: t0))
        XCTAssertFalse(ledger.add(at: t0.addingTimeInterval(0.3)))
        XCTAssertTrue(ledger.add(at: t0.addingTimeInterval(2)))
        XCTAssertEqual(ledger.marks.count, 2)
    }

    func testOldMarksArePruned() {
        var ledger = BookmarkLedger(retention: 60)
        ledger.add(at: t0)
        ledger.add(at: t0.addingTimeInterval(120))
        XCTAssertEqual(ledger.marks.map { $0.date.timeIntervalSince(t0) }, [120])
    }

    func testCountInLastSeconds() {
        var ledger = BookmarkLedger()
        ledger.add(at: t0.addingTimeInterval(-50))
        ledger.add(at: t0.addingTimeInterval(-10))
        XCTAssertEqual(ledger.count(inLast: 30, now: t0), 1)
        XCTAssertEqual(ledger.count(inLast: 60, now: t0), 2)
    }

    func testEmptyOrInvertedWindowYieldsNothing() {
        var ledger = BookmarkLedger()
        ledger.add(at: t0)
        XCTAssertEqual(ledger.bookmarks(clipStart: t0, clipEnd: t0), [])
        XCTAssertEqual(ledger.bookmarks(clipStart: t0.addingTimeInterval(5), clipEnd: t0), [])
    }
}
