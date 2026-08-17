# Installation Guide: Task Monitor

This guide covers all methods to install, package, and distribute **Task Monitor** on Linux.

---

## 1. Quick Install (From Source Repository)

If you have cloned the repository on your machine:

```bash
# Install for the current user (~/.local)
./scripts/install.sh

# Or install system-wide (/usr/local, requires sudo)
sudo ./scripts/install.sh --system
```

This will:
1. Build the release bundle (if not already built).
2. Install the binary and assets to `~/.local/lib/task_monitor/`.
3. Create a command-line shortcut `task_monitor` in `~/.local/bin/`.
4. Install the 1024x1024 application icon to standard XDG icon directories.
5. Create and validate `com.example.task_monitor.desktop` with `StartupWMClass=com.example.task_monitor` so GNOME Dash and the Ubuntu Dock display the custom icon properly.
6. Refresh system desktop and icon databases.

---

## 2. Installing via Debian Package (`.deb`)

For Ubuntu, Debian, Pop!_OS, Linux Mint, and derivatives:

```bash
# 1. Generate the Debian package (if building from source)
./scripts/package_linux.sh

# 2. Install the package
sudo dpkg -i dist/task-monitor_1.0.0_amd64.deb

# (Optional) Fix any missing dependencies if needed:
sudo apt-get install -f
```

To uninstall via `apt`/`dpkg`:
```bash
sudo apt remove task-monitor
```

---

## 3. Installing via Portable Release Tarball (`.tar.gz`)

For any Linux distribution without needing Flutter or developer tools:

1. Download or extract `task-monitor-linux-x64-v1.0.0.tar.gz`:
   ```bash
   tar -xzf task-monitor-linux-x64-v1.0.0.tar.gz
   cd task-monitor-1.0.0
   ```
2. Run the included installer:
   ```bash
   # User-space install (~/.local)
   ./install.sh

   # Or system-wide install (/usr/local)
   sudo ./install.sh --system
   ```

You can also run the application directly from the extracted archive without installing:
```bash
./bundle/task_monitor
```

---

## 4. Building Distributable Packages

To build both the standalone `.tar.gz` archive and the `.deb` package:

```bash
./scripts/package_linux.sh
```

The output packages will be placed in the `dist/` directory:
- `dist/task-monitor_1.0.0_amd64.deb`
- `dist/task-monitor-linux-x64-v1.0.0.tar.gz`

---

## 5. Uninstallation

To remove Task Monitor installed via `scripts/install.sh`:

```bash
# If installed for user:
./scripts/install.sh --uninstall

# If installed system-wide:
sudo ./scripts/install.sh --system --uninstall
```
