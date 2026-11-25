# Audio

Mute your microphone and control each app's volume from a hotkey or a small mixer window, without opening the Windows sound settings.

The microphone mute is applied to the device itself, the same as the Windows "Mute" button, so the device stays active. Apps like Discord keep the microphone after you unmute.

## Files

| File | Purpose |
| --- | --- |
| `Audio.ahk` | The script. Run this one. |
| `Audio.ini` | Your settings. Created automatically, not tracked by git. |

## Hotkeys

| Default | Action |
| --- | --- |
| `Ctrl + Alt + G` | Open the window |
| `Ctrl + Alt + H` | Mute/unmute the **microphone** (all microphones) |
| `Ctrl + Alt + N` | Mute/unmute the **sound** of the selected apps |

You can change or clear the hotkeys in the **Settings** tab. Hotkeys are paused while the window is focused, so a new hotkey can be recorded without triggering the old one.

Mute toggles as a group: if any item is active, all of them are muted. If all are muted, all are unmuted.

Run only one copy of the script. Two copies, for example one on the Desktop and one in this folder, both react to each hotkey and undo each other.

There is no per-app microphone mute. Windows ties every app's microphone mute to the device, so muting one app would mute the microphone for all of them. Windows microphone permissions can't help either: for regular desktop apps they are a single switch for all apps, not one per app.

## Window

- **Sound**: the output device and every app playing sound, each with a mute button and a volume slider.
- **Microphone**: your microphones, each with a mute button and a Live/Muted state, and a list of the apps using the microphone right now.
- **Settings**: hotkeys, theme, beep and on-screen notice.

In the Sound tab, the checkbox next to each app decides whether the sound hotkey mutes it. The menu beside the section title switches the hotkey between **Checked apps** and **All apps**.

Apps only show up while they use audio. Your checks are saved, so an app comes back checked the next time it plays sound. The window refreshes by itself while it is open.

The tray icon shows the state of your microphones. Double-click it to open the window. Right-click it to mute all microphones, reload or exit.

## Theme

Follow the Windows setting (default), light or dark. In "follow system" mode the window switches by itself when the Windows theme changes.

The hotkey input fields stay light in dark mode because Windows does not provide a dark style for that control.
