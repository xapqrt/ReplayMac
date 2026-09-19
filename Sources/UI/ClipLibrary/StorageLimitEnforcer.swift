import Foundation
import Save

/// Medal-style storage cap for the output folder: when clips exceed the
/// limit, the oldest eligible ones are moved to the Trash until the folder
/// fits again. Favorites are never touched, and the user can restrict
/// eviction to full-length recordings (sessions / extended replays) so short
/// highlights survive while long raw footage is recycled first.
public enum StorageLimitEnforcer {
    /// What the planner needs to know about one clip.
    public struct Candidate: Equatable, Sendable {
        public var fileURL: URL
        public var bytes: Int64
        public var createdAt: Date
        public var isFavorite: Bool
        public var kind: ClipCaptureKind?

        public init(fileURL: URL, bytes: Int64, createdAt: Date, isFavorite: Bool, kind: ClipCaptureKind?) {
            self.fileURL = fileURL
            self.bytes = bytes
            self.createdAt = createdAt
            self.isFavorite = isFavorite
            self.kind = kind
        }

        /// Sessions and extended replays; the only things "only delete
        /// full-length recordings" is allowed to evict.
        var isFullLengthRecording: Bool {
            kind == .session || kind == .extendedReplay
        }
    }

    public struct Plan: Equatable, Sendable {
        public var toTrash: [URL]
        public var bytesFreed: Int64
        /// Bytes still over the cap after trashing everything eligible
        /// (favorites / protected kinds are holding the folder over the limit).
        public var bytesStillOver: Int64

        public static let nothing = Plan(toTrash: [], bytesFreed: 0, bytesStillOver: 0)
    }

    /// Decides which clips to trash. Pure: no file access.
    ///
    /// Oldest first, skipping favorites and — when `onlyFullLengthRecordings`
    /// is set — anything that isn't a session or extended replay. Clips with
    /// no capture record (pre-metadata files) count as *not* full length, so
    /// the restrictive mode never deletes something it can't classify.
    public static func plan(
        candidates: [Candidate],
        limitBytes: Int64,
        onlyFullLengthRecordings: Bool
    ) -> Plan {
        let total = candidates.reduce(Int64(0)) { $0 + $1.bytes }
        guard limitBytes > 0, total > limitBytes else { return .nothing }

        var over = total - limitBytes
        var toTrash: [URL] = []
        var freed: Int64 = 0

        let eligible = candidates
            .filter { !$0.isFavorite && (!onlyFullLengthRecordings || $0.isFullLengthRecording) }
            .sorted { $0.createdAt < $1.createdAt }

        for candidate in eligible where over > 0 {
            toTrash.append(candidate.fileURL)
            freed += candidate.bytes
            over -= candidate.bytes
        }

        return Plan(toTrash: toTrash, bytesFreed: freed, bytesStillOver: max(over, 0))
    }

    /// Scans `directory`, joins the library metadata (favorites, capture
    /// kinds), and returns the plan for the current settings. Does not delete.
    public static func plan(for directory: URL, limitBytes: Int64, onlyFullLengthRecordings: Bool) -> Plan {
        let metadata = ClipLibraryMetadataStore.load(in: directory)
        let candidates = ClipMetadata.scanClips(in: directory).map { info -> Candidate in
            let entry = metadata[ClipLibraryMetadataStore.key(for: info.fileURL)]
            return Candidate(
                fileURL: info.fileURL,
                bytes: info.fileSize,
                createdAt: info.creationDate,
                isFavorite: entry?.isFavorite ?? false,
                kind: entry?.capture?.kind
            )
        }
        return plan(candidates: candidates, limitBytes: limitBytes, onlyFullLengthRecordings: onlyFullLengthRecordings)
    }

    /// Applies `plan` by moving files to the Trash (recoverable, like Medal's
    /// recycle bin). Returns the URLs actually trashed.
    @discardableResult
    public static func apply(_ plan: Plan, in directory: URL) -> [URL] {
        var trashed: [URL] = []
        for url in plan.toTrash {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                trashed.append(url)
            } catch {
                print("Storage limit: failed to trash \(url.lastPathComponent): \(error)")
            }
        }
        if !trashed.isEmpty {
            ClipLibraryMetadataStore.pruneMissingEntries(in: directory)
            NotificationCenter.default.post(name: .replayCapClipMetadataDidChange, object: nil)
        }
        return trashed
    }

    /// Plan + apply for the configured output folder, honouring the settings.
    /// Returns nil when the feature is off or nothing had to go.
    public static func enforceIfNeeded() -> Plan? {
        guard AppSettings.storageLimitEnabled,
              let directory = AppSettings.outputDirectoryURL else {
            return nil
        }
        let plan = plan(
            for: directory,
            limitBytes: AppSettings.storageLimitBytes,
            onlyFullLengthRecordings: AppSettings.storageLimitOnlyFullLengthRecordings
        )
        guard !plan.toTrash.isEmpty else { return nil }
        apply(plan, in: directory)
        return plan
    }
}
