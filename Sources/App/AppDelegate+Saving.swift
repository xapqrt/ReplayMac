import Foundation
import AppKit
import Save
import UI
import Feedback

@MainActor
extension AppDelegate {
    func saveClipFromUI(trigger: ClipTrigger = .menu) {
        saveClip(lastSeconds: TimeInterval(AppSettings.bufferDurationSeconds), trigger: trigger)
    }

    func saveLongBufferFromUI(trigger: ClipTrigger = .menu) {
        saveLongBuffer(lastSeconds: TimeInterval(AppSettings.longBufferDurationSeconds), trigger: trigger)
    }

    func saveClip(lastSeconds: TimeInterval, trigger: ClipTrigger) {
        // Resolve the source app now, on the trigger, not after the export:
        // by then the user may have tabbed away from the game.
        let sourceApp = currentForegroundApp()
        Task {
            await saveConfiguredClip(lastSeconds: lastSeconds, trigger: trigger, sourceApp: sourceApp)
        }
    }

    func currentBufferedVideoSeconds() -> TimeInterval {
        SavePreflight.bufferedSeconds(
            primaryVideo: videoRingBuffer.duration,
            dualDisplay1: dualDisplay1VideoRingBuffer.duration,
            dualDisplay2: dualDisplay2VideoRingBuffer.duration,
            isSeparateDualSave: isSeparateDualSaveMode
        )
    }

    var isSeparateDualSaveMode: Bool {
        AppSettings.captureMode == CaptureMode.dualSideBySide.rawValue
            && AppSettings.dualCaptureSaveMode == DualCaptureSaveMode.separateFiles.rawValue
    }

    func saveLongBuffer(lastSeconds: TimeInterval, trigger: ClipTrigger) {
        let sourceApp = currentForegroundApp()
        Task {
            await saveConfiguredLongBufferClip(lastSeconds: lastSeconds, trigger: trigger, sourceApp: sourceApp)
        }
    }

    func saveConfiguredClip(
        lastSeconds: TimeInterval,
        trigger: ClipTrigger = .unknown,
        sourceApp: ClipSourceApp? = nil
    ) async {
        guard let outputDirectory = selectedOutputDirectoryOrNotify() else {
            menuBarState.showSaveFailedBriefly()
            return
        }

        if let failure = SavePreflight.failure(
            isRecording: isCaptureRunning,
            bufferedSeconds: currentBufferedVideoSeconds(),
            saveInProgress: menuBarState.isSaveInProgress,
            replayBufferEnabled: replayBufferGate.isEnabled
        ) {
            if failure != .saveInProgress {
                let message = SavePreflight.notificationMessage(for: failure)
                NotificationManager.shared.showOperationalNotification(title: message.title, body: message.body)
                menuBarState.showSaveFailedBriefly()
            }
            return
        }

        if let diskFailure = diskSpaceFailure(
            lastSeconds: lastSeconds,
            streamCount: isSeparateDualSaveMode ? 2 : 1
        ) {
            let message = SavePreflight.notificationMessage(for: diskFailure)
            NotificationManager.shared.showOperationalNotification(title: message.title, body: message.body)
            menuBarState.showSaveFailedBriefly()
            return
        }

        guard menuBarState.beginSaving() else {
            return
        }
        statusItemController.refreshPresentation()

        do {
            print("Saving clip to output directory: \(outputDirectory.path(percentEncoded: false))")

            let baseName = resolvedClipBaseName(sourceApp: sourceApp)
            let finalURLs: [URL]
            if isSeparateDualSaveMode {
                finalURLs = try await clipSaver.saveDualDisplayClips(
                    lastSeconds: lastSeconds,
                    outputDirectory: outputDirectory,
                    mergeAudioTracks: AppSettings.mergeAudioTracks,
                    baseName: baseName
                )
            } else {
                let savedURL = try await clipSaver.saveClip(
                    lastSeconds: lastSeconds,
                    outputDirectory: outputDirectory,
                    mergeAudioTracks: AppSettings.mergeAudioTracks,
                    baseName: baseName
                )
                finalURLs = [savedURL]
            }

            recordCaptureMetadata(
                for: finalURLs,
                in: outputDirectory,
                kind: .replay,
                trigger: trigger,
                sourceApp: sourceApp,
                requestedDuration: lastSeconds
            )

            menuBarState.finishSaving(success: true)
            statusItemController.setLastClip(finalURLs.first)
            statusItemController.refreshPresentation()

            if AppSettings.playAudioCueOnSave {
                AudioCue.playSaveSuccess()
            }

            if AppSettings.showNotificationOnSave {
                NotificationManager.shared.showClipSavedNotification(fileURL: finalURLs[0], clipDuration: lastSeconds)
            }
            print("Clip saved: \(finalURLs.map(\.path).joined(separator: ", "))")
        } catch {
            menuBarState.finishSaving(success: false)
            statusItemController.refreshPresentation()
            NotificationManager.shared.showSaveFailedNotification(error: error.localizedDescription)
            print("Failed to save clip: \(error)")
        }
    }

    func saveConfiguredLongBufferClip(
        lastSeconds: TimeInterval,
        trigger: ClipTrigger = .unknown,
        sourceApp: ClipSourceApp? = nil
    ) async {
        guard let outputDirectory = selectedOutputDirectoryOrNotify() else {
            menuBarState.showSaveFailedBriefly()
            return
        }

        guard AppSettings.longBufferEnabled else {
            NotificationManager.shared.showOperationalNotification(
                title: "Long Buffer Disabled",
                body: "Enable Extended replay buffer in Settings > Video before saving a long clip."
            )
            return
        }

        guard isCaptureRunning else {
            let message = SavePreflight.notificationMessage(for: .notRecording)
            NotificationManager.shared.showOperationalNotification(title: message.title, body: message.body)
            menuBarState.showSaveFailedBriefly()
            return
        }

        guard replayBufferGate.isEnabled else {
            let message = SavePreflight.notificationMessage(for: .replayBufferUnavailable)
            NotificationManager.shared.showOperationalNotification(title: message.title, body: message.body)
            menuBarState.showSaveFailedBriefly()
            return
        }

        // Extended saves temporarily stage one copy of the selected segments
        // alongside the final exported clip, so reserve space for both.
        if let diskFailure = diskSpaceFailure(lastSeconds: lastSeconds, streamCount: 2) {
            let message = SavePreflight.notificationMessage(for: diskFailure)
            NotificationManager.shared.showOperationalNotification(title: message.title, body: message.body)
            menuBarState.showSaveFailedBriefly()
            return
        }

        guard menuBarState.beginSaving() else {
            return
        }
        statusItemController.refreshPresentation()

        do {
            let savedURL = try await longBufferRecorder.saveClip(
                lastSeconds: lastSeconds,
                outputDirectory: outputDirectory,
                mergeAudioTracks: AppSettings.mergeAudioTracks,
                baseName: resolvedClipBaseName(sourceApp: sourceApp)
            )

            recordCaptureMetadata(
                for: [savedURL],
                in: outputDirectory,
                kind: .extendedReplay,
                trigger: trigger,
                sourceApp: sourceApp,
                requestedDuration: lastSeconds
            )

            menuBarState.finishSaving(success: true)
            statusItemController.setLastClip(savedURL)
            statusItemController.refreshPresentation()

            if AppSettings.playAudioCueOnSave {
                AudioCue.playSaveSuccess()
            }

            if AppSettings.showNotificationOnSave {
                NotificationManager.shared.showClipSavedNotification(fileURL: savedURL, clipDuration: lastSeconds)
            }
            print("Long-buffer clip saved: \(savedURL.path)")
        } catch LongBufferRecorderError.longBufferExportAlreadyInProgress {
            menuBarState.finishSaving(success: false)
            statusItemController.refreshPresentation()
            NotificationManager.shared.showOperationalNotification(
                title: "Long Replay Already Saving",
                body: "A long replay is already saving. Wait for it to finish before saving another."
            )
        } catch {
            menuBarState.finishSaving(success: false)
            statusItemController.refreshPresentation()
            NotificationManager.shared.showSaveFailedNotification(error: error.localizedDescription)
            print("Failed to save long-buffer clip: \(error)")
        }
    }

    /// Estimates the clip size from the configured bitrate and checks it against
    /// free space on the output volume. Returns `nil` (allow the save) when
    /// capacity can't be determined, so this never blocks on a query failure.
    func diskSpaceFailure(lastSeconds: TimeInterval, streamCount: Int) -> SavePreflightFailure? {
        guard let available = availableDiskCapacityBytes() else {
            return nil
        }
        let estimate = SavePreflight.estimatedClipBytes(
            bitrateMbps: AppSettings.bitrateMbps,
            durationSeconds: lastSeconds,
            streamCount: streamCount
        )
        return SavePreflight.diskFailure(
            estimatedClipBytes: estimate,
            availableCapacityBytes: available
        )
    }

    /// Resolves the configured file-name template using the app that was
    /// frontmost when the save was triggered (typically the game being clipped).
    func resolvedClipBaseName(sourceApp: ClipSourceApp?) -> String {
        FilenameTemplate.resolve(
            template: AppSettings.clipFilenameTemplate,
            appName: sourceApp?.name,
            dateFormat: AppSettings.clipDateFormat,
            timeFormat: AppSettings.clipTimeFormat
        )
    }

    /// The app in front right now, or nil when that is ReplayCap itself (a
    /// save triggered from our own menu should not be attributed to us).
    func currentForegroundApp() -> ClipSourceApp? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            return nil
        }
        guard let name = app.localizedName, !name.isEmpty else {
            return nil
        }
        return ClipSourceApp(bundleIdentifier: app.bundleIdentifier, name: name)
    }

    /// Attaches capture facts (kind, trigger, source app) to freshly written
    /// clips so the library can group by game and filter by type. Best effort:
    /// a metadata failure must never turn a successful save into an error.
    func recordCaptureMetadata(
        for fileURLs: [URL],
        in outputDirectory: URL,
        kind: ClipCaptureKind,
        trigger: ClipTrigger,
        sourceApp: ClipSourceApp?,
        requestedDuration: TimeInterval?
    ) {
        let record = ClipCaptureRecord(
            kind: kind,
            trigger: trigger,
            sourceApp: sourceApp,
            capturedAt: Date(),
            requestedDurationSeconds: requestedDuration
        )
        for fileURL in fileURLs {
            ClipLibraryMetadataStore.recordCapture(record, for: fileURL, in: outputDirectory)
        }
    }

    private func availableDiskCapacityBytes() -> Int64? {
        // Probe the output directory if it exists, otherwise the home directory
        // (same volume), since the output folder is created lazily on first save.
        guard let outputURL = AppSettings.outputDirectoryURL else {
            return nil
        }
        let probeURL = FileManager.default.fileExists(atPath: outputURL.path)
            ? outputURL
            : FileManager.default.homeDirectoryForCurrentUser

        let values = try? probeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    func selectedOutputDirectoryOrNotify() -> URL? {
        guard let outputDirectory = AppSettings.outputDirectoryURL else {
            NotificationManager.shared.showOperationalNotification(
                title: "Choose an Output Folder",
                body: "Open Settings and choose the folder where clips should be saved."
            )
            return nil
        }
        return outputDirectory
    }

}
