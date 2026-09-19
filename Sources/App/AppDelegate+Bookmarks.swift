import Foundation
import Feedback
import UI

@MainActor
extension AppDelegate {
    /// Marks "now" so it can be attached to whichever clip later covers it.
    func addBookmark() {
        guard isCaptureRunning || isSessionRecording else {
            NotificationManager.shared.showOperationalNotification(
                title: "Nothing to Bookmark",
                body: "Start recording first; bookmarks mark moments in a running replay buffer or session."
            )
            return
        }

        let now = Date()
        guard bookmarkLedger.add(at: now) else {
            return // debounced double-tap
        }

        if AppSettings.playAudioCueOnSave {
            AudioCue.playBookmarkAdded()
        }
        if AppSettings.showNotificationOnSave {
            let inBuffer = bookmarkLedger.count(inLast: TimeInterval(AppSettings.bufferDurationSeconds), now: now)
            let body = isSessionRecording
                ? "Saved with the session when you stop it."
                : "\(inBuffer) in the current \(AppSettings.bufferDurationSeconds) s buffer. Save a replay to keep them."
            NotificationManager.shared.showOperationalNotification(title: "Bookmark Added", body: body)
        }
    }
}
