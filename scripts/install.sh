#!/usr/bin/env bash
# ==============================================================================
# Task Monitor - Linux Installation Script
# ==============================================================================
# Installs Task Monitor with desktop entry, icons, and binary symlink.
#
# Usage:
#   ./scripts/install.sh               # Install for current user (~/.local)
#   ./scripts/install.sh --system      # Install system-wide (/usr/local)
#   ./scripts/install.sh --uninstall   # Uninstall Task Monitor
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

SYSTEM_INSTALL=false
UNINSTALL=false

for arg in "$@"; do
  case "$arg" in
    --system)
      SYSTEM_INSTALL=true
      ;;
    --uninstall)
      UNINSTALL=true
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --system     Install system-wide to /usr/local (requires sudo)"
      echo "  --uninstall  Uninstall Task Monitor"
      echo "  -h, --help   Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg"
      exit 1
      ;;
  esac
done

if [ "$SYSTEM_INSTALL" = true ]; then
  PREFIX="/usr/local"
  LIB_DIR="${PREFIX}/lib/task_monitor"
  BIN_DIR="${PREFIX}/bin"
  APP_DIR="/usr/share/applications"
  ICON_DIR="/usr/share/icons/hicolor"
  PIXMAPS_DIR="/usr/share/pixmaps"
  
  if [ "$(id -u)" -ne 0 ]; then
    echo "Error: System-wide installation requires root privileges. Please run with sudo." >&2
    exit 1
  fi
else
  PREFIX="${HOME}/.local"
  LIB_DIR="${PREFIX}/lib/task_monitor"
  BIN_DIR="${PREFIX}/bin"
  APP_DIR="${HOME}/.local/share/applications"
  ICON_DIR="${HOME}/.local/share/icons/hicolor"
  PIXMAPS_DIR="${HOME}/.local/share/pixmaps"
fi

# ==============================================================================
# UNINSTALLATION
# ==============================================================================
if [ "$UNINSTALL" = true ]; then
  echo "Uninstalling Task Monitor..."
  
  rm -rf "${LIB_DIR}"
  rm -f "${BIN_DIR}/task_monitor"
  rm -f "${BIN_DIR}/task-monitor"
  rm -f "${APP_DIR}/com.example.task_monitor.desktop"
  rm -f "${APP_DIR}/task_monitor.desktop"
  rm -f "${ICON_DIR}/1024x1024/apps/task_monitor.png"
  rm -f "${ICON_DIR}/1024x1024/apps/com.example.task_monitor.png"
  rm -f "${PIXMAPS_DIR}/task_monitor.png"
  rm -f "${PIXMAPS_DIR}/com.example.task_monitor.png"

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${APP_DIR}" 2>/dev/null || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f "${ICON_DIR}" 2>/dev/null || true
  fi

  echo "Task Monitor has been successfully uninstalled."
  exit 0
fi

# ==============================================================================
# LOCATE OR BUILD BUNDLE
# ==============================================================================
BUNDLE_DIR=""

if [ -d "${SCRIPT_DIR}/bundle" ] && [ -f "${SCRIPT_DIR}/bundle/task_monitor" ]; then
  BUNDLE_DIR="${SCRIPT_DIR}/bundle"
elif [ -d "${REPO_DIR}/build/linux/x64/release/bundle" ] && [ -f "${REPO_DIR}/build/linux/x64/release/bundle/task_monitor" ]; then
  BUNDLE_DIR="${REPO_DIR}/build/linux/x64/release/bundle"
else
  echo "Release bundle not found. Building with Flutter..."
  if command -v flutter >/dev/null 2>&1; then
    (cd "${REPO_DIR}" && flutter build linux --release)
    BUNDLE_DIR="${REPO_DIR}/build/linux/x64/release/bundle"
  else
    echo "Error: Flutter SDK not found in PATH and no prebuilt bundle found in '${REPO_DIR}/build/linux/x64/release/bundle'." >&2
    exit 1
  fi
fi

ICON_SRC=""
if [ -f "${SCRIPT_DIR}/task_monitor_icon_1024x1024.png" ]; then
  ICON_SRC="${SCRIPT_DIR}/task_monitor_icon_1024x1024.png"
elif [ -f "${REPO_DIR}/icon_design/task_monitor_icon_1024x1024.png" ]; then
  ICON_SRC="${REPO_DIR}/icon_design/task_monitor_icon_1024x1024.png"
fi

# ==============================================================================
# INSTALLATION
# ==============================================================================
echo "Installing Task Monitor to ${PREFIX}..."

mkdir -p "${LIB_DIR}"
mkdir -p "${BIN_DIR}"
mkdir -p "${APP_DIR}"
mkdir -p "${ICON_DIR}/1024x1024/apps"
mkdir -p "${PIXMAPS_DIR}"

# 1. Copy Application Bundle
echo "Copying application bundle to ${LIB_DIR}..."
cp -r "${BUNDLE_DIR}/"* "${LIB_DIR}/"
chmod +x "${LIB_DIR}/task_monitor"

# 2. Create Binary Symlinks
ln -sf "${LIB_DIR}/task_monitor" "${BIN_DIR}/task_monitor"
ln -sf "${LIB_DIR}/task_monitor" "${BIN_DIR}/task-monitor"

# 3. Install Icons
if [ -n "${ICON_SRC}" ] && [ -f "${ICON_SRC}" ]; then
  echo "Installing application icons..."
  cp "${ICON_SRC}" "${ICON_DIR}/1024x1024/apps/task_monitor.png"
  cp "${ICON_SRC}" "${ICON_DIR}/1024x1024/apps/com.example.task_monitor.png"
  cp "${ICON_SRC}" "${PIXMAPS_DIR}/task_monitor.png"
  cp "${ICON_SRC}" "${PIXMAPS_DIR}/com.example.task_monitor.png"
fi

# 4. Create Desktop Entry
echo "Creating desktop entry at ${APP_DIR}/com.example.task_monitor.desktop..."
cat << EOF > "${APP_DIR}/com.example.task_monitor.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Task Monitor
GenericName=Focus Bar
Comment=An obnoxious taskbar that reminds you what you're supposed to be doing.
Exec=${LIB_DIR}/task_monitor
Icon=task_monitor
Terminal=false
Categories=Utility;
StartupWMClass=com.example.task_monitor
StartupNotify=true
Keywords=task;monitor;focus;pomodoro;timer;
EOF

chmod +x "${APP_DIR}/com.example.task_monitor.desktop"
cp "${APP_DIR}/com.example.task_monitor.desktop" "${APP_DIR}/task_monitor.desktop"

# 5. Update Caches
echo "Updating desktop and icon caches..."
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "${APP_DIR}" 2>/dev/null || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f "${ICON_DIR}" 2>/dev/null || true
fi

echo "=============================================================================="
echo " Installation Complete!"
echo " Task Monitor is now installed in: ${PREFIX}"
echo " You can launch it by running: task_monitor"
echo " Or find 'Task Monitor' in your application menu."
echo "=============================================================================="
