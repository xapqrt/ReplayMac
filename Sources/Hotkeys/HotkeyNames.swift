import KeyboardShortcuts

public extension KeyboardShortcuts.Name {
    static let saveClip = Self("saveClip")
    static let toggleRecording = Self("toggleRecording")
    /// Quick presets. The first two keep their historical identifiers so
    /// shortcuts recorded by earlier versions survive; their lengths are
    /// configurable in Settings (`AppSettings.quickPresetSeconds`).
    static let saveLast15Seconds = Self("saveLast15Seconds")
    static let saveLast60Seconds = Self("saveLast60Seconds")
    static let saveQuickPreset3 = Self("saveQuickPreset3")
    static let saveLongBuffer = Self("saveLongBuffer")
    static let toggleSessionRecording = Self("toggleSessionRecording")
    static let openClipLibrary = Self("openClipLibrary")
}
