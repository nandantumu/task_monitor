<div align="center">
<img src="https://raw.githubusercontent.com/nandantumu/task_monitor/refs/heads/main/icon_design/task_monitor_icon_1024x1024.png" alt="logo" style="width: 30%; height: auto;"></img>
</div>

# Task Monitor
Task Monitor keeps a thin yellow bar docked at the top of your desktop so you can see your current focus and a Pomodoro-style countdown at a glance. It is intentionally minimal (well under 500 lines of Dart) and targets macOS, Windows, and Linux desktop builds.

## Features
- Always-on-top, borderless focus bar docked at the top or bottom of your screen.
- Multi-monitor support with dynamic cycling across displays (including mixed landscape and vertical/portrait setups).
- System tray integration with live countdown tooltip and stable context menu.
- Editable "CF" (Current Focus) text prompt to keep tasks in sight.
- 25-minute Pomodoro timer with pause/play, quick time editing, and flashing completion alert.
- Native Linux desktop integration with high-resolution app icon and `.desktop` launcher.

## Requirements
- Flutter 3.19+ with desktop support enabled for your platform
- macOS 12+, Windows 10+, or a modern Linux distribution (Ubuntu, Debian, Fedora, Arch, etc.) with GTK3

## Getting Started

1. Clone the repo and install dependencies:
   ```bash
   flutter pub get
   ```
2. Run in development:
   ```bash
   flutter run -d linux
   ```

## Quick Installation (Linux)

Install Task Monitor locally with full desktop menu and icon integration:

```bash
./scripts/install.sh
```

See [INSTALL.md](INSTALL.md) for full instructions, including `.deb` installation, portable tarball usage, and system-wide installation.

## Packaging & Distribution

To generate standalone distributable packages for Linux (`.deb` and portable `.tar.gz` with embedded installer):

```bash
./scripts/package_linux.sh
```

Packages are generated in the `dist/` directory:
- `dist/task-monitor_1.0.0_amd64.deb`
- `dist/task-monitor-linux-x64-v1.0.0.tar.gz`

Refer to the [Flutter desktop docs](https://docs.flutter.dev/platform-integration/desktop) for macOS and Windows packaging.
