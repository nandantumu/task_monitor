# Task Monitor
Task Monitor keeps a thin yellow bar docked at the top of your desktop so you can see your current focus and a Pomodoro-style countdown at a glance. It is intentionally minimal (well under 500 lines of Dart) and targets macOS, Windows, and Linux desktop builds.

## Features
- Always-on-top, borderless window that spans the top of the primary display.
- Editable "Current Focus" text so you can remind yourself what you should be doing.
- 25-minute countdown timer with pause/play control, text editing while paused, and a flashing red state when time expires.
- Configurable defaults: tweak the initial focus text, colors, or session length directly in `lib/main.dart`.

## Requirements
- Flutter 3.19+ with desktop support enabled for your platform
- macOS 12+, Windows 10+, or a modern Linux distribution with GTK support

## Getting Started
1. Clone the repo and install dependencies:
   ```bash
   flutter pub get
   ```
2. Run on your desktop target (examples shown for macOS and Windows):
   ```bash
   flutter run -d macos
   flutter run -d windows
   ```
3. The window will snap to the top of your primary display. Click the focus text to edit it, click the time to pause and adjust the remaining minutes, or use the control button on the right to pause/play/reset.

## Customization
- **Session length**: update `_sessionDuration` near the top of `lib/main.dart`.
- **Default focus text**: change the `TextEditingController` seed string in `_FocusBarState`.
- **Colors/height**: tweak `_barColor`, `_flashColor`, and `_focusBarHeight` to better match your desktop.

## Packaging
When you are ready to distribute the bar:
- macOS: `flutter build macos`
- Windows: `flutter build windows`
- Linux: `flutter build linux`

Refer to the [Flutter desktop docs](https://docs.flutter.dev/platform-integration/desktop) for signing, notarization, or installer creation guidance.
