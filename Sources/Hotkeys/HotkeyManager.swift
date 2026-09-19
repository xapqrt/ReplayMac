import Foundation
import KeyboardShortcuts

@MainActor
public final class HotkeyManager: @unchecked Sendable {
    public var onSaveClip: (() -> Void)?
    public var onToggleRecording: (() -> Void)?
    public var onSaveLast15Seconds: (() -> Void)?
    public var onSaveLast60Seconds: (() -> Void)?
    public var onSaveLongBuffer: (() -> Void)?
    public var onToggleSessionRecording: (() -> Void)?
    public var onOpenClipLibrary: (() -> Void)?

    private var isStarted = false

    /// Every shortcut the app registers, in the order shown in Settings.
    /// Used by `stop()` and by callers that need to enumerate them (e.g. the
    /// menu bar hint that checks whether any save shortcut is configured).
    public static let allNames: [KeyboardShortcuts.Name] = [
        .saveClip,
        .toggleRecording,
        .saveLast15Seconds,
        .saveLast60Seconds,
        .saveLongBuffer,
        .toggleSessionRecording,
        .openClipLibrary
    ]

    public init() {}

    // No `deinit` cleanup: KeyboardShortcuts 3.x is compiled with MainActor
    // default isolation, so its handler API cannot be called from a
    // nonisolated deinit. The manager is owned by the AppDelegate for the
    // whole process lifetime; callers that really need to unregister use
    // `stop()` from the main actor.

    public func start() {
        guard !isStarted else {
            return
        }
        isStarted = true

        KeyboardShortcuts.onKeyUp(for: .saveClip) { [weak self] in
            self?.onSaveClip?()
        }
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
            self?.onToggleRecording?()
        }
        KeyboardShortcuts.onKeyUp(for: .saveLast15Seconds) { [weak self] in
            self?.onSaveLast15Seconds?()
        }
        KeyboardShortcuts.onKeyUp(for: .saveLast60Seconds) { [weak self] in
            self?.onSaveLast60Seconds?()
        }
        KeyboardShortcuts.onKeyUp(for: .saveLongBuffer) { [weak self] in
            self?.onSaveLongBuffer?()
        }
        KeyboardShortcuts.onKeyUp(for: .toggleSessionRecording) { [weak self] in
            self?.onToggleSessionRecording?()
        }
        KeyboardShortcuts.onKeyUp(for: .openClipLibrary) { [weak self] in
            self?.onOpenClipLibrary?()
        }
    }

    /// Unregisters every handler installed by `start()`. Safe to call when
    /// not started.
    public func stop() {
        guard isStarted else {
            return
        }
        isStarted = false
        for name in Self.allNames {
            KeyboardShortcuts.removeHandler(for: name)
        }
    }
}
