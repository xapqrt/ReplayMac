import Foundation

/// Wall-clock moments the user marked while recording ("bookmark that!").
///
/// Marks are kept by absolute time, not by clip, because at the moment the
/// key is pressed no file exists yet. When a replay, extended replay or
/// session is saved, the marks that fall inside its time window are attached
/// to the clip as offsets from its start (see `bookmarks(clipStart:clipEnd:)`).
public struct BookmarkLedger: Equatable, Sendable {
    public struct Mark: Equatable, Sendable {
        public var date: Date
        public var label: String

        public init(date: Date, label: String = "") {
            self.date = date
            self.label = label
        }
    }

    /// How long a mark is kept before it can no longer land in any clip.
    /// Sessions can run for hours; six covers any realistic one.
    public static let defaultRetention: TimeInterval = 6 * 60 * 60

    /// Two presses closer than this collapse into one mark, so a nervous
    /// double-tap doesn't litter the timeline.
    public static let debounceInterval: TimeInterval = 1.0

    public private(set) var marks: [Mark] = []
    public var retention: TimeInterval

    public init(retention: TimeInterval = BookmarkLedger.defaultRetention) {
        self.retention = retention
    }

    /// Adds a mark at `date`. Returns false when it was debounced.
    @discardableResult
    public mutating func add(at date: Date = Date(), label: String = "") -> Bool {
        prune(now: date)
        if let last = marks.last, abs(date.timeIntervalSince(last.date)) < Self.debounceInterval {
            return false
        }
        marks.append(Mark(date: date, label: label))
        marks.sort { $0.date < $1.date }
        return true
    }

    /// Drops marks older than `retention`.
    public mutating func prune(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-retention)
        marks.removeAll { $0.date < cutoff }
    }

    /// Marks inside `[clipStart, clipEnd]`, as offsets from `clipStart`.
    /// Offsets are clamped to the clip so a mark pressed a hair before a
    /// replay began still points at its first frame.
    public func bookmarks(clipStart: Date, clipEnd: Date) -> [ClipBookmark] {
        guard clipEnd > clipStart else { return [] }
        let length = clipEnd.timeIntervalSince(clipStart)
        return marks
            .filter { $0.date >= clipStart && $0.date <= clipEnd }
            .map { mark in
                let offset = mark.date.timeIntervalSince(clipStart)
                return ClipBookmark(seconds: min(max(offset, 0), length), label: mark.label)
            }
    }

    /// Number of marks that would land in a clip ending now with `lastSeconds`
    /// of footage — what the menu bar shows while recording.
    public func count(inLast lastSeconds: TimeInterval, now: Date = Date()) -> Int {
        bookmarks(clipStart: now.addingTimeInterval(-lastSeconds), clipEnd: now).count
    }
}
