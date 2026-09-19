import Hotkeys
import UI

@MainActor
extension AppDelegate {
    func configureHotkeys() {
        hotkeyManager.onSaveClip = { [weak self] in
            self?.saveClipFromUI(trigger: .hotkey)
        }
        hotkeyManager.onToggleRecording = { [weak self] in
            self?.toggleCapturePipeline()
        }
        // Preset lengths are read on each press so Settings changes apply
        // immediately without re-registering the shortcuts.
        hotkeyManager.onSaveLast15Seconds = { [weak self] in
            self?.saveQuickPreset(index: 0)
        }
        hotkeyManager.onSaveLast60Seconds = { [weak self] in
            self?.saveQuickPreset(index: 1)
        }
        hotkeyManager.onSaveQuickPreset3 = { [weak self] in
            self?.saveQuickPreset(index: 2)
        }
        hotkeyManager.onSaveLongBuffer = { [weak self] in
            self?.saveLongBufferFromUI(trigger: .hotkey)
        }
        hotkeyManager.onToggleSessionRecording = { [weak self] in
            self?.toggleSessionRecording()
        }
        hotkeyManager.onAddBookmark = { [weak self] in
            self?.addBookmark()
        }
        hotkeyManager.onTakeScreenshot = { [weak self] in
            self?.takeScreenshot(trigger: .hotkey)
        }
        hotkeyManager.onOpenClipLibrary = { [weak self] in
            self?.toggleClipLibraryWindow()
        }
        hotkeyManager.start()
    }

    private func saveQuickPreset(index: Int) {
        let presets = AppSettings.quickPresetSeconds
        guard presets.indices.contains(index) else { return }
        saveClip(lastSeconds: TimeInterval(presets[index]), trigger: .hotkey)
    }
}
