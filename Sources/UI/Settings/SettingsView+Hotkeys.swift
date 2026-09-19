import SwiftUI
import Hotkeys
import KeyboardShortcuts

extension SettingsView {
    var hotkeysTab: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Save clip", name: .saveClip)
                KeyboardShortcuts.Recorder("Start/stop recording", name: .toggleRecording)
            } header: {
                sectionHeader(icon: "bolt.fill", title: "Primary")
            }

            Section {
                quickPresetRow(name: .saveLast15Seconds, seconds: $quickPreset1Seconds)
                quickPresetRow(name: .saveLast60Seconds, seconds: $quickPreset2Seconds)
                quickPresetRow(name: .saveQuickPreset3, seconds: $quickPreset3Seconds)
                KeyboardShortcuts.Recorder("Save extended replay", name: .saveLongBuffer)
                Label(
                    "Each preset saves its own length from the replay buffer. A preset longer than the buffer duration (\(bufferDurationSeconds) s) saves what is available.",
                    systemImage: "info.circle"
                )
                .foregroundStyle(AppTheme.textSecondary)
                .font(.system(size: 12, design: .rounded))
            } header: {
                sectionHeader(icon: "stopwatch", title: "Quick Presets")
            }

            Section {
                KeyboardShortcuts.Recorder("Start/stop session recording", name: .toggleSessionRecording)
                Label(
                    "Records until you stop, then saves one file with screen, system audio, and mic. Separate from the instant-replay buffer.",
                    systemImage: "info.circle"
                )
                .foregroundStyle(AppTheme.textSecondary)
                .font(.system(size: 12, design: .rounded))
            } header: {
                sectionHeader(icon: "record.circle", title: "Session Recording")
            }

            Section {
                KeyboardShortcuts.Recorder("Add bookmark", name: .addBookmark)
                Label(
                    "Marks the current moment while recording. Bookmarks that fall inside a saved replay or session are attached to that clip so you can jump straight to them.",
                    systemImage: "info.circle"
                )
                .foregroundStyle(AppTheme.textSecondary)
                .font(.system(size: 12, design: .rounded))
            } header: {
                sectionHeader(icon: "bookmark.fill", title: "Bookmarks")
            }

            Section {
                KeyboardShortcuts.Recorder("Show or hide clip library", name: .openClipLibrary)
            } header: {
                sectionHeader(icon: "film.stack", title: "Library")
            }
        }
        .formStyle(.grouped)
    }

    /// A shortcut recorder whose label tracks the preset length, with a
    /// stepper to change that length (5 s steps, 5 s – 5 min).
    private func quickPresetRow(name: KeyboardShortcuts.Name, seconds: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            KeyboardShortcuts.Recorder(
                "Save last \(SettingsView.quickPresetLabel(seconds.wrappedValue))",
                name: name
            )
            Stepper(
                value: seconds,
                in: AppSettings.quickPresetRange,
                step: 5
            ) {
                Text("Length: \(SettingsView.quickPresetLabel(seconds.wrappedValue))")
                    .foregroundStyle(AppTheme.textSecondary)
                    .font(.system(size: 12, design: .rounded))
            }
        }
    }

    static func quickPresetLabel(_ seconds: Int) -> String {
        let clamped = AppSettings.clampQuickPreset(seconds)
        if clamped % 60 == 0 {
            let minutes = clamped / 60
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
        if clamped > 60 {
            return "\(clamped / 60) min \(clamped % 60) s"
        }
        return "\(clamped) seconds"
    }
}
