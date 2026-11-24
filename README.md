# AutoHotkey Scripts

A collection of [AutoHotkey v2](https://www.autohotkey.com/) scripts for Windows, each in its own folder.

## Scripts

| Script | What it does |
| --- | --- |
| [audio](audio/) | Per-app volume and mute, microphone mute, and hotkeys to mute selected apps. |

## Requirements

- Windows 10 (1809+) or Windows 11
- [AutoHotkey v2.0+](https://www.autohotkey.com/download/)

## Usage

Open a script's folder and double-click its `.ahk` file. Each script keeps its settings in an `.ini` file next to it, created on first save. Those files are local settings and are not tracked by git.

To start a script with Windows, put a shortcut to it in the Startup folder (`Win + R` → `shell:startup`).
