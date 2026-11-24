# Audio

Mute microphones and app audio from a hotkey, without opening the Windows sound settings.

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
| `Ctrl + Alt + H` | Mute/unmute the **microphone** of the selected apps |
| `Ctrl + Alt + N` | Mute/unmute the **sound** of the selected apps |

You can change or clear the hotkeys in the **Settings** tab. Hotkeys are paused while the window is focused, so a new hotkey can be recorded without triggering the old one.

Mute toggles as a group: if any selected item is active, all of them are muted. If all are muted, all are unmuted.

Run only one copy of the script. Two copies, for example one on the Desktop and one in this folder, both react to each hotkey and undo each other.

On Windows 11, Discord links its microphone to the device mute: muting or unmuting Discord's microphone in the list also mutes or unmutes the whole microphone. This is Discord/Windows behavior, not the script. Muting an app's sound never touches the microphone.

## Window

- **Sound**: the output device and every app playing sound, each with a mute button and a volume slider.
- **Microphone**: your microphones and every app using the microphone, each with a mute button and a Live/Muted state.
- **Settings**: hotkeys, theme, beep and on-screen notice.

Next to each app, the checkbox decides whether the hotkey mutes it. The menu beside the section title switches the hotkey between **Checked apps** and **All apps**.

Apps only show up while they use audio. An app you checked stays listed as "not running" after it closes, so you can uncheck it. The window refreshes by itself while it is open.

The tray icon shows the state of your microphones. Double-click it to open the window. Right-click it to mute all microphones, reload or exit.

## Theme

Follow the Windows setting (default), light or dark. In "follow system" mode the window switches by itself when the Windows theme changes.

The hotkey input fields stay light in dark mode because Windows does not provide a dark style for that control.
