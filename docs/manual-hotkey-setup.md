# Setting ReplayMac Hotkeys from the Terminal

Normally you set hotkeys in **Settings → Hotkeys**. Builds that used
`KeyboardShortcuts` 2.x could not record shortcuts on macOS 26/27 (the
recorder lost its event monitor; fixed in `KeyboardShortcuts` 3.1.0, which this
fork uses). If you ever need to bypass the recorder, you can set any hotkey
from the Terminal instead. This is completely safe and fully reversible — it
writes the same preference the Settings UI would.

Session recording uses `KeyboardShortcuts_toggleSessionRecording` (start/stop
and save one continuous file).

## How to set a hotkey

1. **Quit ReplayMac** (menu bar icon → Quit). This matters: if the app is
   running it can overwrite your change when it quits.
2. Open **Terminal** and paste one command (see below).
3. **Relaunch ReplayMac.** The shortcut is active immediately and will show up
   in Settings → Hotkeys.

The command looks like this (this example sets **Save clip** to **⌘⇧S**):

```bash
defaults write com.replaymac.app KeyboardShortcuts_saveClip -string '{"carbonKeyCode":1,"carbonModifiers":768}'
```

You only change three things: the **action name**, the **key code**, and the
**modifier number**. Look each up in the tables below.

## The actions

| Action | Name to use in the command |
|---|---|
| Save clip | `KeyboardShortcuts_saveClip` |
| Start/stop recording | `KeyboardShortcuts_toggleRecording` |
| Save last 15 seconds | `KeyboardShortcuts_saveLast15Seconds` |
| Save last 60 seconds | `KeyboardShortcuts_saveLast60Seconds` |
| Save extended replay | `KeyboardShortcuts_saveLongBuffer` |
| Start/stop session recording | `KeyboardShortcuts_toggleSessionRecording` |
| Open clip library | `KeyboardShortcuts_openClipLibrary` |

## The modifiers (`carbonModifiers`)

Add the numbers of the modifiers you want together:

| Modifier | Value |
|---|---|
| ⌘ Command | 256 |
| ⇧ Shift | 512 |
| ⌥ Option | 2048 |
| ⌃ Control | 4096 |

Examples: ⌘⇧ = 256 + 512 = **768** · ⌃⌥ = 4096 + 2048 = **6144** ·
⌘⌥⇧ = 256 + 2048 + 512 = **2816**.

Use at least one modifier with letters and numbers, or your shortcut will
fire while you type normally. Function keys (F1–F15) are fine on their own —
use `"carbonModifiers":0`.

## The keys (`carbonKeyCode`)

| Key | Code | | Key | Code | | Key | Code |
|---|---|---|---|---|---|---|---|
| A | 0 | | Q | 12 | | 1 | 18 |
| B | 11 | | R | 15 | | 2 | 19 |
| C | 8 | | S | 1 | | 3 | 20 |
| D | 2 | | T | 17 | | 4 | 21 |
| E | 14 | | U | 32 | | 5 | 23 |
| F | 3 | | V | 9 | | 6 | 22 |
| G | 5 | | W | 13 | | 7 | 26 |
| H | 4 | | X | 7 | | 8 | 28 |
| I | 34 | | Y | 16 | | 9 | 25 |
| J | 38 | | Z | 6 | | 0 | 29 |
| K | 40 | | F1 | 122 | | F7 | 98 |
| L | 37 | | F2 | 120 | | F8 | 100 |
| M | 46 | | F3 | 99 | | F9 | 101 |
| N | 45 | | F4 | 118 | | F10 | 109 |
| O | 31 | | F5 | 96 | | F11 | 103 |
| P | 35 | | F6 | 97 | | F12 | 111 |

## Ready-made examples

Save clip → **⌘⇧S**:

```bash
defaults write com.replaymac.app KeyboardShortcuts_saveClip -string '{"carbonKeyCode":1,"carbonModifiers":768}'
```

Save clip → **F9** (no modifiers):

```bash
defaults write com.replaymac.app KeyboardShortcuts_saveClip -string '{"carbonKeyCode":101,"carbonModifiers":0}'
```

Start/stop recording → **⌘⇧R**:

```bash
defaults write com.replaymac.app KeyboardShortcuts_toggleRecording -string '{"carbonKeyCode":15,"carbonModifiers":768}'
```

Save last 60 seconds → **⌃⌥6**:

```bash
defaults write com.replaymac.app KeyboardShortcuts_saveLast60Seconds -string '{"carbonKeyCode":22,"carbonModifiers":6144}'
```

Open clip library → **⌘⌥L**:

```bash
defaults write com.replaymac.app KeyboardShortcuts_openClipLibrary -string '{"carbonKeyCode":37,"carbonModifiers":2304}'
```

Start/stop session recording → **⌘⇧E**:

```bash
defaults write com.replaymac.app KeyboardShortcuts_toggleSessionRecording -string '{"carbonKeyCode":14,"carbonModifiers":768}'
```

## Removing a hotkey

```bash
defaults delete com.replaymac.app KeyboardShortcuts_saveClip
```

(Quit ReplayMac first, relaunch after — same as when setting one.)

## Tips

- Avoid combos macOS already uses (⌘⇧3/4/5 are screenshots, ⌘Space is
  Spotlight, etc.). If a shortcut doesn't fire, try a different combo first.
- Each action can only have one shortcut, and setting a new one replaces the
  old one.
- Once the Settings recorder works again on your macOS version, you can manage
  these from the app as usual — it edits the exact same values.
