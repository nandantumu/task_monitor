# Dev Log: Multi-Monitor Support & Linux Window Geometry Fix

**Date**: 2026-08-17  
**Author**: Pair Programming with Antigravity  

---

## 1. Overview & Objective
Add multi-monitor detection and dynamic monitor switching support to Task Monitor, allowing the focus bar to move between multiple displays with different orientations (e.g. landscape and vertical/portrait displays), while resolving Linux/GNOME window height constraints and background rendering issues.

---

## 2. Issues Encountered & Root Cause Analysis

### A. Multi-Monitor Switching
- The bar needed the ability to switch between multiple monitors via both an on-bar UI button and the system tray menu.
- On Linux, `ScreenRetriever.instance.getAllDisplays()` returns empty string IDs (`id: ""`), so display matching needed to be based on coordinates (`visiblePosition`) and geometry (`size`).

### B. Window Height Constraint (200px Black/White Box on GNOME)
- **Root Cause**: GNOME Mutter and GTK enforce a minimum size of `200x200` pixels for standard top-level application windows (`_NET_WM_WINDOW_TYPE_NORMAL`).
- Even though Dart requested 50px height, GTK/Mutter clamped the window height to 200px.
- In Dart, the UI container was placed in an `Align(topCenter, child: SizedBox(height: 50))`, leaving the bottom 150px of the 200px window unpainted (rendering as white or opaque black canvas).

### C. Width Collapsing on GTK
- Calling `setResizable(false)` on GTK caused GTK to collapse the window width down to the widget's minimal preferred size rather than maintaining the multi-monitor width request.

### D. System Tray Menu Disappearing / Glitching (DBus Race Condition)
- **Root Cause**: The 1-second countdown timer interval was updating the menu item timer label (`Timer: 24:59`, `Timer: 24:58`, etc.), calling `_trayMenu.buildFrom()` and `_systemTray.setContextMenu()` every second.
- On Linux (GNOME Shell AppIndicator), tearing down and recreating the DBus menu hierarchy every single second destroyed the active menu popup mid-click / mid-hover, leaving behind a blank/empty outline or failing to render.
- **Fix**: Decoupled tooltip updates (`setSystemTrayInfo`) from context menu rebuilds (`setContextMenu`). The live countdown is displayed in the tray icon hover tooltip, while the context menu retains stable action items (`Pause/Start Timer`, `Restart Session`, `Attach Top/Bottom`, `Switch Monitor`, `Show Bar`, `Quit`) and is only updated on actual state transitions.

---

## 3. Implementation Details

### Native Linux Runner (`linux/runner/my_application.cc`)
1. **Window Type Hint**: Configured `gtk_window_set_type_hint(window, GDK_WINDOW_TYPE_HINT_TOOLBAR)` so GNOME Mutter treats the window as a toolbar/panel, removing the 200px minimum window height constraint.
2. **Widget Size Request**: Set `gtk_widget_set_size_request(GTK_WIDGET(window), -1, 50)` and `gtk_widget_set_size_request(GTK_WIDGET(view), -1, 50)` so GTK respects the 50px height while leaving width unconstrained for dynamic monitor resizing.
3. **RGBA Visual**: Enabled `gdk_screen_get_rgba_visual` for proper alpha channel and transparency compositing.
4. **Header Bar Removal**: Removed GTK client-side decoration header bar for a clean borderless window.
5. **Window Icon**: Programmatically loaded the bundled 1024x1024 icon via `gtk_window_set_icon_from_file` so window managers and task switchers display the custom icon.

### Dart Application (`lib/main.dart`)
1. **Display Tracking**: Maintained active monitor list and index via `ScreenRetriever`, supporting cycling across connected displays.
2. **Dynamic Geometry Calculation**: Calculated exact workarea offset and visible width per monitor (`offset.dx`, `targetTop`, `visibleWidth`).
3. **Full-Bleed FocusBar**: Replaced the inner 50px `SizedBox` with a full-bleed `Container` filling 100% of the Scaffold background.
4. **Constraint Management**: Applied strict `min_width == max_width == monitor_width` and `min_height == max_height == 50` geometry constraints for each screen without calling `setResizable(false)` that collapsed width.
5. **UI & Prefix**: Shortened prefix label to `CF: ` and added an on-bar monitor switch button (`Icons.desktop_windows_outlined`) and tray menu item.
6. **System Tray Stability**: Decoupled hover tooltip updates from DBus context menu rebuilds, ensuring persistent, glitch-free tray menus on GNOME AppIndicator.

### Local Installation & Desktop Entry
- Release bundle built and installed to `~/.local/lib/task_monitor/` with executable symlinked to `~/.local/bin/task_monitor`.
- High-res icons installed into standard XDG directories: `~/.local/share/icons/hicolor/1024x1024/apps/`, `~/.local/share/pixmaps/`, and `~/.icons/`.
- Validated desktop entry created at `~/.local/share/applications/com.example.task_monitor.desktop` with `StartupWMClass=com.example.task_monitor` to map running windows to the custom dock icon.

### Tests (`test/widget_test.dart`)
- Updated widget test assertions to match the `CF:` prefix.

---

## 4. Verification & Results
- Verified with `xwininfo`: Window geometry matches exactly `2494x50+1146+32` on the landscape monitor (50px height, full visible width).
- Verified multi-monitor cycling across landscape (2560px) and vertical (1080px) monitors without distortion or extra canvas boxes.
- Verified system tray: Menu is created once and remains stable without continuous DBus teardowns; tooltip updates smoothly every second.
- Verified release build and local desktop launcher integration with full icon association.
- `flutter analyze` and `flutter test` passed with 0 errors.
