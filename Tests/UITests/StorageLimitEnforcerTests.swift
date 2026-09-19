import XCTest
@testable import UI

final class StorageLimitEnforcerTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func clip(
        _ name: String,
        bytes: Int64,
        ageDays: Double,
        favorite: Bool = false,
        kind: ClipCaptureKind? = .replay
    ) -> StorageLimitEnforcer.Candidate {
        StorageLimitEnforcer.Candidate(
            fileURL: URL(fileURLWithPath: "/clips/\(name).mp4"),
            bytes: bytes,
            createdAt: t0.addingTimeInterval(-ageDays * day),
            isFavorite: favorite,
            kind: kind
        )
    }

    private func names(_ plan: StorageLimitEnforcer.Plan) -> [String] {
        plan.toTrash.map { $0.deletingPathExtension().lastPathComponent }
    }

    func testUnderTheLimitDoesNothing() {
        let plan = StorageLimitEnforcer.plan(
            candidates: [clip("a", bytes: 100, ageDays: 1), clip("b", bytes: 100, ageDays: 2)],
            limitBytes: 500,
            onlyFullLengthRecordings: false
        )
        XCTAssertEqual(plan, .nothing)
    }

    func testTrashesOldestFirstUntilUnderTheLimit() {
        let plan = StorageLimitEnforcer.plan(
            candidates: [
                clip("newest", bytes: 100, ageDays: 1),
                clip("middle", bytes: 100, ageDays: 5),
                clip("oldest", bytes: 100, ageDays: 9)
            ],
            limitBytes: 150,
            onlyFullLengthRecordings: false
        )
        XCTAssertEqual(names(plan), ["oldest", "middle"])
        XCTAssertEqual(plan.bytesFreed, 200)
        XCTAssertEqual(plan.bytesStillOver, 0)
    }

    func testFavoritesAreNeverTrashed() {
        let plan = StorageLimitEnforcer.plan(
            candidates: [
                clip("fav", bytes: 300, ageDays: 9, favorite: true),
                clip("plain", bytes: 100, ageDays: 1)
            ],
            limitBytes: 250,
            onlyFullLengthRecordings: false
        )
        XCTAssertEqual(names(plan), ["plain"])
        XCTAssertEqual(plan.bytesStillOver, 50, "the favorite alone still exceeds the cap")
    }

    func testOnlyFullLengthModeSkipsShortReplaysAndUnclassifiedClips() {
        let plan = StorageLimitEnforcer.plan(
            candidates: [
                clip("old-replay", bytes: 100, ageDays: 20, kind: .replay),
                clip("legacy", bytes: 100, ageDays: 15, kind: nil),
                clip("session", bytes: 100, ageDays: 10, kind: .session),
                clip("extended", bytes: 100, ageDays: 5, kind: .extendedReplay),
                clip("new-replay", bytes: 100, ageDays: 1, kind: .replay)
            ],
            limitBytes: 350,
            onlyFullLengthRecordings: true
        )
        XCTAssertEqual(names(plan), ["session", "extended"])
    }

    func testZeroLimitIsTreatedAsDisabled() {
        let plan = StorageLimitEnforcer.plan(
            candidates: [clip("a", bytes: 100, ageDays: 1)],
            limitBytes: 0,
            onlyFullLengthRecordings: false
        )
        XCTAssertEqual(plan, .nothing)
    }

    func testStorageLimitLabels() {
        XCTAssertEqual(SettingsView.storageLimitLabel(50), "50 GB")
        XCTAssertEqual(SettingsView.storageLimitLabel(2.5), "2.5 GB")
        XCTAssertEqual(SettingsView.storageLimitLabel(1000), "1 TB")
        XCTAssertEqual(SettingsView.storageLimitLabel(1500), "1.5 TB")
    }
}
