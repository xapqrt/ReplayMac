import AppKit
import AudioToolbox

public enum AudioCue {
    public static func playSaveSuccess() {
        AudioServicesPlaySystemSound(1113)
    }

    /// Short, distinct from the save cue, so a bookmark press is confirmed
    /// without being mistaken for a save.
    public static func playBookmarkAdded() {
        if let sound = NSSound(named: NSSound.Name("Pop")) {
            sound.play()
        } else {
            AudioServicesPlaySystemSound(1113)
        }
    }
}
