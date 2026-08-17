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

---

## 3. Implementation Details

### Native Linux Runner (`linux/runner/my_application.cc`)
1. **Window Type Hint**: Configured `gtk_window_set_type_hint(window, GDK_WINDOW_TYPE_HINT_TOOLBAR)` so GNOME Mutter treats the window as a toolbar/panel, removing the 200px minimum window height constraint.
2. **Widget Size Request**: Set `gtk_widget_set_size_request(GTK_WIDGET(window), -1, 50)` and `gtk_widget_set_size_request(GTK_WIDGET(view), -1, 50)` so GTK respects the 50px height while leaving width unconstrained for dynamic monitor resizing.
3. **RGBA Visual**: Enabled `gdk_screen_get_rgba_visual` for proper alpha channel and transparency compositing.
4. **Header Bar Removal**: Removed GTK client-side decoration header bar for a clean borderless window.

### Dart Application (`lib/main.dart`)
1. **Display Tracking**: Maintained active monitor list and index via `ScreenRetriever`, supporting cycling across connected displays.
2. **Dynamic Geometry Calculation**: Calculated exact workarea offset and visible width per monitor (`offset.dx`, `targetTop`, `visibleWidth`).
3. **Full-Bleed FocusBar**: Replaced the inner 50px `SizedBox` with a full-bleed `Container` filling 100% of the Scaffold background.
4. **Constraint Management**: Applied strict `min_width == max_width == monitor_width` and `min_height == max_height == 50` geometry constraints for each screen without calling `setResizable(false)` that collapsed width.
5. **UI & Prefix**: Shortened prefix label to `CF: ` and added an on-bar monitor switch button (`Icons.desktop_windows_outlined`) and tray menu item.

### Tests (`test/widget_test.dart`)
- Updated widget test assertions to match the `CF:` prefix.

---

## 4. Verification & Results
- Verified with `xwininfo`: Window geometry matches exactly `2494x50+1146+32` on the landscape monitor (50px height, full visible width).
- Verified multi-monitor cycling across landscape (2560px) and vertical (1080px) monitors without distortion or extra canvas boxes.
- `flutter analyze` and `flutter test` passed with 0 errors.
