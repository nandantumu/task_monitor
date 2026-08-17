#!/usr/bin/env bash
# ==============================================================================
# Task Monitor - Linux Packaging Script
# ==============================================================================
# Builds release binary and generates distributable packages:
#   1. Portable Tarball (.tar.gz) with embedded installer
#   2. Debian Package (.deb) for Ubuntu/Debian/Pop!_OS/Mint
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${REPO_DIR}/dist"
APP_NAME="task-monitor"
VERSION="1.0.0"
ARCH="amd64"

echo "=============================================================================="
echo " Packaging Task Monitor v${VERSION} (${ARCH})"
echo "=============================================================================="

# Ensure flutter is in PATH
if ! command -v flutter >/dev/null 2>&1; then
  if [ -x "/home/nandan/SourceCode/999_OLD_PROJECTS/flutter/bin/flutter" ]; then
    export PATH="/home/nandan/SourceCode/999_OLD_PROJECTS/flutter/bin:$PATH"
  elif [ -d "${HOME}/flutter/bin" ]; then
    export PATH="${HOME}/flutter/bin:$PATH"
  fi
fi

# 1. Build Flutter Release Bundle
echo "Building Flutter Linux release bundle..."
(cd "${REPO_DIR}" && flutter build linux --release)

BUNDLE_DIR="${REPO_DIR}/build/linux/x64/release/bundle"
if [ ! -d "${BUNDLE_DIR}" ] || [ ! -f "${BUNDLE_DIR}/task_monitor" ]; then
  echo "Error: Release bundle build failed." >&2
  exit 1
fi

mkdir -p "${DIST_DIR}"

# ==============================================================================
# 2. CREATE PORTABLE TARBALL (.tar.gz)
# ==============================================================================
TAR_BUILD_DIR="${REPO_DIR}/build/tar_pkg"
rm -rf "${TAR_BUILD_DIR}"
mkdir -p "${TAR_BUILD_DIR}/${APP_NAME}-${VERSION}"

echo "Creating portable release archive..."
cp -r "${BUNDLE_DIR}" "${TAR_BUILD_DIR}/${APP_NAME}-${VERSION}/bundle"
cp "${REPO_DIR}/icon_design/task_monitor_icon_1024x1024.png" "${TAR_BUILD_DIR}/${APP_NAME}-${VERSION}/"
cp "${REPO_DIR}/scripts/install.sh" "${TAR_BUILD_DIR}/${APP_NAME}-${VERSION}/install.sh"
chmod +x "${TAR_BUILD_DIR}/${APP_NAME}-${VERSION}/install.sh"

cat << EOF > "${TAR_BUILD_DIR}/${APP_NAME}-${VERSION}/README.txt"
Task Monitor v${VERSION}
========================

An obnoxious taskbar that reminds you what you're supposed to be doing.

INSTALLATION:
  To install for the current user (~/.local):
    ./install.sh

  To install system-wide (/usr/local, requires sudo):
    sudo ./install.sh --system

  To uninstall:
    ./install.sh --uninstall

RUNNING DIRECTLY:
  You can also run the application directly without installing:
    ./bundle/task_monitor
EOF

TAR_OUTPUT="${DIST_DIR}/${APP_NAME}-linux-x64-v${VERSION}.tar.gz"
(cd "${TAR_BUILD_DIR}" && tar -czf "${TAR_OUTPUT}" "${APP_NAME}-${VERSION}")
rm -rf "${TAR_BUILD_DIR}"
echo "✓ Portable tarball created: ${TAR_OUTPUT}"

# ==============================================================================
# 3. CREATE DEBIAN PACKAGE (.deb)
# ==============================================================================
if command -v dpkg-deb >/dev/null 2>&1; then
  echo "Creating Debian package (.deb)..."
  DEB_BUILD_DIR="${REPO_DIR}/build/deb_pkg"
  rm -rf "${DEB_BUILD_DIR}"
  
  # Directory structure
  INSTALL_LIB="${DEB_BUILD_DIR}/usr/lib/task_monitor"
  INSTALL_BIN="${DEB_BUILD_DIR}/usr/bin"
  INSTALL_APP="${DEB_BUILD_DIR}/usr/share/applications"
  INSTALL_ICON="${DEB_BUILD_DIR}/usr/share/icons/hicolor/1024x1024/apps"
  INSTALL_PIXMAP="${DEB_BUILD_DIR}/usr/share/pixmaps"
  INSTALL_DEBIAN="${DEB_BUILD_DIR}/DEBIAN"

  mkdir -p "${INSTALL_LIB}" "${INSTALL_BIN}" "${INSTALL_APP}" "${INSTALL_ICON}" "${INSTALL_PIXMAP}" "${INSTALL_DEBIAN}"

  # Copy files
  cp -r "${BUNDLE_DIR}/"* "${INSTALL_LIB}/"
  chmod +x "${INSTALL_LIB}/task_monitor"

  # Symlink in /usr/bin
  ln -sf "/usr/lib/task_monitor/task_monitor" "${INSTALL_BIN}/task_monitor"
  ln -sf "/usr/lib/task_monitor/task_monitor" "${INSTALL_BIN}/task-monitor"

  # Icons
  cp "${REPO_DIR}/icon_design/task_monitor_icon_1024x1024.png" "${INSTALL_ICON}/task_monitor.png"
  cp "${REPO_DIR}/icon_design/task_monitor_icon_1024x1024.png" "${INSTALL_PIXMAP}/task_monitor.png"

  # Desktop Entry
  cat << EOF > "${INSTALL_APP}/com.example.task_monitor.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Task Monitor
GenericName=Focus Bar
Comment=An obnoxious taskbar that reminds you what you're supposed to be doing.
Exec=/usr/lib/task_monitor/task_monitor
Icon=task_monitor
Terminal=false
Categories=Utility;
StartupWMClass=com.example.task_monitor
StartupNotify=true
Keywords=task;monitor;focus;pomodoro;timer;
EOF
  chmod 644 "${INSTALL_APP}/com.example.task_monitor.desktop"

  # Control File
  INSTALLED_SIZE=$(du -sk "${DEB_BUILD_DIR}" | cut -f1)
  cat << EOF > "${INSTALL_DEBIAN}/control"
Package: ${APP_NAME}
Version: ${VERSION}
Architecture: ${ARCH}
Maintainer: Nandan Tumu <nandan@nandantumu.com>
Installed-Size: ${INSTALLED_SIZE}
Depends: libgtk-3-0, libglib2.0-0
Section: utils
Priority: optional
Homepage: https://github.com/nandantumu/task_monitor
Description: An obnoxious taskbar that reminds you what you're supposed to be doing.
 A desktop productivity taskbar that locks to the top or bottom of your
 display to keep your current focus and timer in constant view.
EOF

  # Post-install & Post-remove hooks
  cat << 'EOF' > "${INSTALL_DEBIAN}/postinst"
#!/bin/sh
set -e
if [ -x /usr/bin/update-desktop-database ]; then
  /usr/bin/update-desktop-database -q /usr/share/applications || true
fi
if [ -x /usr/bin/gtk-update-icon-cache ]; then
  /usr/bin/gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
EOF
  chmod 755 "${INSTALL_DEBIAN}/postinst"

  cat << 'EOF' > "${INSTALL_DEBIAN}/postrm"
#!/bin/sh
set -e
if [ -x /usr/bin/update-desktop-database ]; then
  /usr/bin/update-desktop-database -q /usr/share/applications || true
fi
if [ -x /usr/bin/gtk-update-icon-cache ]; then
  /usr/bin/gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
EOF
  chmod 755 "${INSTALL_DEBIAN}/postrm"

  # Build .deb
  DEB_OUTPUT="${DIST_DIR}/${APP_NAME}_${VERSION}_${ARCH}.deb"
  dpkg-deb --build --root-owner-group "${DEB_BUILD_DIR}" "${DEB_OUTPUT}"
  rm -rf "${DEB_BUILD_DIR}"
  echo "✓ Debian package created: ${DEB_OUTPUT}"
fi

echo "=============================================================================="
echo " Packaging Complete! Distributable files are located in '${DIST_DIR}':"
ls -lh "${DIST_DIR}"
echo "=============================================================================="
