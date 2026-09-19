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
        hotkeyManager.onSaveLast15Seconds = { [weak self] in
            self?.saveClip(lastSeconds: 15, trigger: .hotkey)
        }
        hotkeyManager.onSaveLast60Seconds = { [weak self] in
            self?.saveClip(lastSeconds: 60, trigger: .hotkey)
        }
        hotkeyManager.onSaveLongBuffer = { [weak self] in
            self?.saveLongBufferFromUI(trigger: .hotkey)
        }
        hotkeyManager.onToggleSessionRecording = { [weak self] in
            self?.toggleSessionRecording()
        }
        hotkeyManager.onOpenClipLibrary = { [weak self] in
            self?.toggleClipLibraryWindow()
        }
        hotkeyManager.start()
    }

}
