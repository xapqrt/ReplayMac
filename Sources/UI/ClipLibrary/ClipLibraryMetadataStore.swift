import Foundation

// MARK: - Capture facts (schema v2)

/// What produced a clip. Stored per clip so the library can group and filter
/// (Clips / Sessions / Screenshots) without inferring it from file names.
public enum ClipCaptureKind: String, Codable, Sendable, CaseIterable {
    /// Instant replay saved from the in-memory ring buffer.
    case replay
    /// 5/10/30 minute replay saved from the on-disk extended buffer.
    case extendedReplay
    /// Start → stop session recording.
    case session
    case screenshot
    /// Dropped in by the user or picked up from a watched folder.
    case imported

    public var title: String {
        switch self {
        case .replay: return "Replay"
        case .extendedReplay: return "Extended replay"
        case .session: return "Session"
        case .screenshot: return "Screenshot"
        case .imported: return "Imported"
        }
    }
}

/// How a save was triggered.
public enum ClipTrigger: String, Codable, Sendable, CaseIterable {
    case hotkey
    case menu
    case voice
    case automatic
    case unknown
}

/// The application that was frontmost when a clip was captured — for game
/// clips, the game. Lets the library group by game and show its icon.
public struct ClipSourceApp: Codable, Equatable, Hashable, Sendable {
    public var bundleIdentifier: String?
    public var name: String

    public init(bundleIdentifier: String?, name: String) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }
}

/// A user-dropped marker inside a recording (Medal's "bookmarks").
public struct ClipBookmark: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// Offset from the start of the saved file.
    public var seconds: Double
    public var label: String

    public init(id: UUID = UUID(), seconds: Double, label: String = "") {
        self.id = id
        self.seconds = seconds
        self.label = label
    }
}

/// Facts recorded by the capture pipeline the moment a clip is written.
/// Written once and never edited by the user.
public struct ClipCaptureRecord: Codable, Equatable, Sendable {
    public var kind: ClipCaptureKind
    public var trigger: ClipTrigger
    public var sourceApp: ClipSourceApp?
    public var capturedAt: Date
    /// The replay length the user asked for (nil for sessions/screenshots).
    public var requestedDurationSeconds: Double?

    public init(
        kind: ClipCaptureKind,
        trigger: ClipTrigger,
        sourceApp: ClipSourceApp?,
        capturedAt: Date = Date(),
        requestedDurationSeconds: Double? = nil
    ) {
        self.kind = kind
        self.trigger = trigger
        self.sourceApp = sourceApp
        self.capturedAt = capturedAt
        self.requestedDurationSeconds = requestedDurationSeconds
    }
}

// MARK: - Per-clip entry

struct ClipUserMetadata: Codable, Equatable {
    var displayName: String
    var isFavorite: Bool
    var tags: [String]
    var notes: String
    /// Schema v2. Optional so files written by older builds still decode.
    var capture: ClipCaptureRecord?
    var bookmarks: [ClipBookmark]

    static let empty = ClipUserMetadata(displayName: "", isFavorite: false, tags: [], notes: "")

    init(
        displayName: String,
        isFavorite: Bool,
        tags: [String],
        notes: String,
        capture: ClipCaptureRecord? = nil,
        bookmarks: [ClipBookmark] = []
    ) {
        self.displayName = displayName
        self.isFavorite = isFavorite
        self.tags = tags
        self.notes = notes
        self.capture = capture
        self.bookmarks = bookmarks
    }

    private enum CodingKeys: String, CodingKey {
        case displayName, isFavorite, tags, notes, capture, bookmarks
    }

    /// Tolerant decoding: every key is optional so a partially written or
    /// older file never takes the whole library's metadata down with it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        capture = try? container.decodeIfPresent(ClipCaptureRecord.self, forKey: .capture)
        bookmarks = (try? container.decodeIfPresent([ClipBookmark].self, forKey: .bookmarks)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(tags, forKey: .tags)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(capture, forKey: .capture)
        if !bookmarks.isEmpty {
            try container.encode(bookmarks, forKey: .bookmarks)
        }
    }

    /// True when the user has never touched this entry, so it carries nothing
    /// beyond what the pipeline recorded.
    var hasUserEdits: Bool {
        !displayName.isEmpty || isFavorite || !tags.isEmpty || !notes.isEmpty || !bookmarks.isEmpty
    }
}

struct ClipLibraryStorageSummary: Equatable {
    var clipCount: Int
    var totalBytes: Int64
    var oldestClipDate: Date?
}

// MARK: - Store

/// One JSON file per output folder, keyed by clip path.
///
/// Two writers touch this file: the library window (user edits) and the
/// capture pipeline (capture records written the moment a clip lands). Every
/// write here is a locked read-modify-write of the on-disk file, so neither
/// side can clobber the other's changes — the library used to persist its
/// whole in-memory dictionary, which silently dropped anything written while
/// it was loading thumbnails.
public enum ClipLibraryMetadataStore {
    private static let metadataFileName = ".ReplayCapClipLibrary.json"
    private static let legacyMetadataFileName = ".ReplayMacClipLibrary.json"
    // NSLock is Sendable on Darwin, but `nonisolated(unsafe)` keeps this
    // independent of overlay annotations across SDK versions.
    nonisolated(unsafe) private static let lock = NSLock()

    private static func withLock<R>(_ body: () throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    static func metadataURL(in directory: URL) -> URL {
        directory.appendingPathComponent(metadataFileName, isDirectory: false)
    }

    static func load(in directory: URL) -> [String: ClipUserMetadata] {
        withLock { loadUnlocked(in: directory) }
    }

    static func save(_ metadata: [String: ClipUserMetadata], in directory: URL) {
        withLock { saveUnlocked(metadata, in: directory) }
    }

    static func key(for url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false)
    }

    /// Read-modify-write of a single entry. Creates the entry when missing.
    @discardableResult
    static func update(
        for fileURL: URL,
        in directory: URL,
        _ mutate: (inout ClipUserMetadata) -> Void
    ) -> ClipUserMetadata {
        withLock {
            var all = loadUnlocked(in: directory)
            let entryKey = Self.key(for: fileURL)
            var entry = all[entryKey] ?? .empty
            mutate(&entry)
            all[entryKey] = entry
            saveUnlocked(all, in: directory)
            return entry
        }
    }

    /// Merges the library's in-memory dictionary into the on-disk file.
    ///
    /// Rules, per key:
    /// - present in memory → memory wins for user fields, but a capture record
    ///   or bookmarks that only exist on disk are kept (they were written by
    ///   the pipeline after the library last loaded);
    /// - only on disk → kept while its file still exists, dropped otherwise.
    ///
    /// Deletions and renames therefore need no special casing: a trashed or
    /// moved file simply fails the existence check.
    static func merge(_ inMemory: [String: ClipUserMetadata], in directory: URL) {
        withLock {
            let onDisk = loadUnlocked(in: directory)
            var result: [String: ClipUserMetadata] = [:]
            let fileManager = FileManager.default

            for (key, entry) in onDisk where inMemory[key] == nil {
                if fileManager.fileExists(atPath: key) {
                    result[key] = entry
                }
            }

            for (key, var entry) in inMemory {
                if let disk = onDisk[key] {
                    if entry.capture == nil {
                        entry.capture = disk.capture
                    }
                    if entry.bookmarks.isEmpty {
                        entry.bookmarks = disk.bookmarks
                    }
                }
                result[key] = entry
            }

            saveUnlocked(result, in: directory)
        }
    }

    /// Drops entries whose file no longer exists.
    static func pruneMissingEntries(in directory: URL) {
        withLock {
            let all = loadUnlocked(in: directory)
            let live = all.filter { FileManager.default.fileExists(atPath: $0.key) }
            if live.count != all.count {
                saveUnlocked(live, in: directory)
            }
        }
    }

    /// Entry point for the capture pipeline: attaches capture facts to a clip
    /// that was just written. Never overwrites user edits and never replaces
    /// an existing capture record (the first writer knows best).
    public static func recordCapture(_ record: ClipCaptureRecord, for fileURL: URL, in directory: URL) {
        update(for: fileURL, in: directory) { entry in
            if entry.capture == nil {
                entry.capture = record
            }
        }
        NotificationCenter.default.post(name: .replayCapClipMetadataDidChange, object: fileURL)
    }

    /// Appends a bookmark to a clip's entry.
    public static func addBookmark(_ bookmark: ClipBookmark, for fileURL: URL, in directory: URL) {
        update(for: fileURL, in: directory) { entry in
            entry.bookmarks.append(bookmark)
            entry.bookmarks.sort { $0.seconds < $1.seconds }
        }
        NotificationCenter.default.post(name: .replayCapClipMetadataDidChange, object: fileURL)
    }

    public static func captureRecord(for fileURL: URL, in directory: URL) -> ClipCaptureRecord? {
        load(in: directory)[key(for: fileURL)]?.capture
    }

    // MARK: Unlocked primitives

    private static func loadUnlocked(in directory: URL) -> [String: ClipUserMetadata] {
        let currentURL = metadataURL(in: directory)
        let legacyURL = directory.appendingPathComponent(legacyMetadataFileName, isDirectory: false)
        let sourceURL = FileManager.default.fileExists(atPath: currentURL.path)
            ? currentURL
            : legacyURL

        guard let data = try? Data(contentsOf: sourceURL),
              let metadata = try? Self.decoder.decode([String: ClipUserMetadata].self, from: data) else {
            return [:]
        }

        if sourceURL == legacyURL {
            try? data.write(to: currentURL, options: .atomic)
        }
        return metadata
    }

    private static func saveUnlocked(_ metadata: [String: ClipUserMetadata], in directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try Self.encoder.encode(metadata)
            try data.write(to: metadataURL(in: directory), options: .atomic)
        } catch {
            print("Failed to save clip library metadata: \(error)")
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public extension Notification.Name {
    /// Posted after the pipeline attaches capture facts or bookmarks to a clip,
    /// so an open library window refreshes its rows.
    static let replayCapClipMetadataDidChange = Notification.Name("com.replaycap.clip.metadataDidChange")
}
