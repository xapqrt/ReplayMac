import XCTest
@testable import UI

final class ClipLibraryMetadataStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Creates an empty stand-in clip file so existence checks see it.
    private func makeClipFile(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data().write(to: url)
        return url
    }

    private func sampleCapture(app: String = "Some Game") -> ClipCaptureRecord {
        ClipCaptureRecord(
            kind: .replay,
            trigger: .hotkey,
            sourceApp: ClipSourceApp(bundleIdentifier: "com.example.game", name: app),
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
            requestedDurationSeconds: 30
        )
    }

    // MARK: Compatibility

    func testLoadMigratesLegacyReplayMacMetadataFile() throws {
        let legacyURL = directory.appendingPathComponent(".ReplayMacClipLibrary.json")
        let metadata = [
            "/tmp/clip.mp4": ClipUserMetadata(
                displayName: "Highlight",
                isFavorite: true,
                tags: ["game"],
                notes: "Legacy metadata"
            )
        ]
        try JSONEncoder().encode(metadata).write(to: legacyURL)

        XCTAssertEqual(ClipLibraryMetadataStore.load(in: directory), metadata)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(".ReplayCapClipLibrary.json").path
            )
        )
    }

    func testSchemaV1FileDecodesWithEmptyCaptureFields() throws {
        // Exactly what 1.7.x wrote: no capture, no bookmarks.
        let v1JSON = """
        {
          "/tmp/old.mp4": {
            "displayName": "Old",
            "isFavorite": false,
            "tags": ["ranked"],
            "notes": ""
          }
        }
        """
        try Data(v1JSON.utf8).write(to: ClipLibraryMetadataStore.metadataURL(in: directory))

        let loaded = ClipLibraryMetadataStore.load(in: directory)
        let entry = try XCTUnwrap(loaded["/tmp/old.mp4"])
        XCTAssertEqual(entry.displayName, "Old")
        XCTAssertEqual(entry.tags, ["ranked"])
        XCTAssertNil(entry.capture)
        XCTAssertEqual(entry.bookmarks, [])
    }

    func testUnknownCaptureKindDoesNotDropTheEntry() throws {
        // A future build may write kinds this one doesn't know; the user's
        // edits must survive even if the capture record can't be decoded.
        let json = """
        {
          "/tmp/future.mp4": {
            "displayName": "From the future",
            "isFavorite": true,
            "tags": [],
            "notes": "",
            "capture": { "kind": "hologram", "trigger": "hotkey", "capturedAt": "2030-01-01T00:00:00Z" }
          }
        }
        """
        try Data(json.utf8).write(to: ClipLibraryMetadataStore.metadataURL(in: directory))

        let entry = try XCTUnwrap(ClipLibraryMetadataStore.load(in: directory)["/tmp/future.mp4"])
        XCTAssertEqual(entry.displayName, "From the future")
        XCTAssertTrue(entry.isFavorite)
        XCTAssertNil(entry.capture)
    }

    func testCaptureRecordRoundTrips() throws {
        let clip = try makeClipFile("clip.mp4")
        let record = sampleCapture()

        ClipLibraryMetadataStore.recordCapture(record, for: clip, in: directory)

        XCTAssertEqual(ClipLibraryMetadataStore.captureRecord(for: clip, in: directory), record)
        let entry = try XCTUnwrap(ClipLibraryMetadataStore.load(in: directory)[ClipLibraryMetadataStore.key(for: clip)])
        XCTAssertFalse(entry.hasUserEdits, "capture facts alone are not a user edit")
    }

    // MARK: Two writers

    func testRecordCaptureNeverReplacesAnExistingRecord() throws {
        let clip = try makeClipFile("clip.mp4")
        let first = sampleCapture(app: "First")
        let second = sampleCapture(app: "Second")

        ClipLibraryMetadataStore.recordCapture(first, for: clip, in: directory)
        ClipLibraryMetadataStore.recordCapture(second, for: clip, in: directory)

        XCTAssertEqual(ClipLibraryMetadataStore.captureRecord(for: clip, in: directory)?.sourceApp?.name, "First")
    }

    func testMergeKeepsCaptureRecordWrittenAfterTheLibraryLoaded() throws {
        let clip = try makeClipFile("clip.mp4")
        let key = ClipLibraryMetadataStore.key(for: clip)

        // 1. Library loads (empty), 2. pipeline records capture facts,
        // 3. library persists a user edit from its stale copy.
        var stale = ClipLibraryMetadataStore.load(in: directory)
        ClipLibraryMetadataStore.recordCapture(sampleCapture(), for: clip, in: directory)
        stale[key] = ClipUserMetadata(displayName: "Renamed", isFavorite: true, tags: [], notes: "")
        ClipLibraryMetadataStore.merge(stale, in: directory)

        let entry = try XCTUnwrap(ClipLibraryMetadataStore.load(in: directory)[key])
        XCTAssertEqual(entry.displayName, "Renamed")
        XCTAssertTrue(entry.isFavorite)
        XCTAssertEqual(entry.capture?.sourceApp?.name, "Some Game")
    }

    func testMergeKeepsUnknownEntriesForExistingFilesAndDropsMissingOnes() throws {
        let existing = try makeClipFile("existing.mp4")
        let missing = directory.appendingPathComponent("missing.mp4")
        ClipLibraryMetadataStore.recordCapture(sampleCapture(app: "Kept"), for: existing, in: directory)
        ClipLibraryMetadataStore.recordCapture(sampleCapture(app: "Gone"), for: missing, in: directory)

        // The library knows about neither (e.g. both landed after its last scan).
        ClipLibraryMetadataStore.merge([:], in: directory)

        let loaded = ClipLibraryMetadataStore.load(in: directory)
        XCTAssertEqual(loaded[ClipLibraryMetadataStore.key(for: existing)]?.capture?.sourceApp?.name, "Kept")
        XCTAssertNil(loaded[ClipLibraryMetadataStore.key(for: missing)])
    }

    func testMergeInMemoryWinsForUserFields() throws {
        let clip = try makeClipFile("clip.mp4")
        let key = ClipLibraryMetadataStore.key(for: clip)
        ClipLibraryMetadataStore.update(for: clip, in: directory) { $0.isFavorite = true; $0.notes = "disk" }

        ClipLibraryMetadataStore.merge(
            [key: ClipUserMetadata(displayName: "", isFavorite: false, tags: ["a"], notes: "memory")],
            in: directory
        )

        let entry = try XCTUnwrap(ClipLibraryMetadataStore.load(in: directory)[key])
        XCTAssertFalse(entry.isFavorite)
        XCTAssertEqual(entry.notes, "memory")
        XCTAssertEqual(entry.tags, ["a"])
    }

    func testPruneRemovesOnlyEntriesWhoseFileIsGone() throws {
        let existing = try makeClipFile("existing.mp4")
        let missing = directory.appendingPathComponent("missing.mp4")
        ClipLibraryMetadataStore.update(for: existing, in: directory) { $0.isFavorite = true }
        ClipLibraryMetadataStore.update(for: missing, in: directory) { $0.isFavorite = true }

        ClipLibraryMetadataStore.pruneMissingEntries(in: directory)

        let loaded = ClipLibraryMetadataStore.load(in: directory)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertNotNil(loaded[ClipLibraryMetadataStore.key(for: existing)])
    }

    // MARK: Bookmarks

    func testAddBookmarkKeepsThemSortedByTime() throws {
        let clip = try makeClipFile("clip.mp4")
        ClipLibraryMetadataStore.addBookmark(ClipBookmark(seconds: 42, label: "late"), for: clip, in: directory)
        ClipLibraryMetadataStore.addBookmark(ClipBookmark(seconds: 7, label: "early"), for: clip, in: directory)

        let entry = try XCTUnwrap(ClipLibraryMetadataStore.load(in: directory)[ClipLibraryMetadataStore.key(for: clip)])
        XCTAssertEqual(entry.bookmarks.map(\.label), ["early", "late"])
        XCTAssertTrue(entry.hasUserEdits)
    }
}
