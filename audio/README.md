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

- **Microphone**: microphone devices (mute the whole device for every app) and the apps currently capturing the microphone.
- **Mixer**: system output volume and mute, and the apps currently playing sound.
- **Settings**: hotkeys, theme, beep and on-screen notice.

Check the apps you want a hotkey to control, or tick **All apps**. An app only shows up in a list while it is using audio. Apps you checked earlier stay listed as "not found" so you can uncheck them.

The tray icon shows the state of the selected microphones. Double-click it to open the window. Right-click it to mute the microphones, reload or exit.

## Theme

Follow the Windows setting (default), light or dark. In "follow system" mode the window switches by itself when the Windows theme changes.

The hotkey input fields stay light in dark mode because Windows does not provide a dark style for that control.
