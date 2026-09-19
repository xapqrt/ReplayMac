import Capture
import Feedback
import Foundation
import UI

@MainActor
extension AppDelegate {
    /// Folder for stills, kept apart from the movie clips the library scans.
    static let screenshotsFolderName = "Screenshots"

    /// Saves a PNG of the recorded display (or the one under the pointer).
    /// Works whether or not the replay pipeline is running.
    func takeScreenshot(trigger: ClipTrigger) {
        guard let outputDirectory = selectedOutputDirectoryOrNotify() else {
            return
        }
        let sourceApp = currentForegroundApp()
        let triggeredAt = Date()
        let directory = outputDirectory.appendingPathComponent(Self.screenshotsFolderName, isDirectory: true)
        let baseName = resolvedClipBaseName(sourceApp: sourceApp)

        Task {
            let preferredDisplayID = await captureManager.capturedDisplayID
            do {
                let url = try await ScreenshotCapturer.capturePNG(
                    preferredDisplayID: preferredDisplayID,
                    directory: directory,
                    baseName: baseName
                )
                ClipLibraryMetadataStore.recordCapture(
                    ClipCaptureRecord(kind: .screenshot, trigger: trigger, sourceApp: sourceApp, capturedAt: triggeredAt),
                    for: url,
                    in: directory
                )
                if AppSettings.playAudioCueOnSave {
                    AudioCue.playScreenshotTaken()
                }
                if AppSettings.showNotificationOnSave {
                    NotificationManager.shared.showOperationalNotification(
                        title: "Screenshot Saved",
                        body: url.lastPathComponent
                    )
                }
            } catch {
                NotificationManager.shared.showSaveFailedNotification(error: String(describing: error))
                print("Failed to take screenshot: \(error)")
            }
        }
    }
}
