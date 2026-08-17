import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:ui' show Size;
import 'package:flutter/foundation.dart';

typedef _XOpenDisplayC = Pointer<Void> Function(Pointer<Void> displayName);
typedef _XOpenDisplayDart = Pointer<Void> Function(Pointer<Void> displayName);

typedef _XMoveResizeWindowC = Int32 Function(Pointer<Void> display, Uint64 window, Int32 x, Int32 y, Uint32 width, Uint32 height);
typedef _XMoveResizeWindowDart = int Function(Pointer<Void> display, int window, int x, int y, int width, int height);

typedef _XFlushC = Int32 Function(Pointer<Void> display);
typedef _XFlushDart = int Function(Pointer<Void> display);

typedef _XCloseDisplayC = Int32 Function(Pointer<Void> display);
typedef _XCloseDisplayDart = int Function(Pointer<Void> display);

/// Represents a physical monitor's geometry and placement.
class PhysicalMonitor {
  final String name;
  final double x;
  final double y;
  final double width;
  final double height;
  final bool isPrimary;

  const PhysicalMonitor({
    required this.name,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.isPrimary,
  });
}

/// Calculation result containing 12-element STRUT_PARTIAL and 4-element STRUT.
class StrutCalculation {
  final List<int> strutPartial;
  final List<int> strut;

  const StrutCalculation({
    required this.strutPartial,
    required this.strut,
  });
}

/// Service for managing Linux X11 workarea reservation (EWMH struts).
/// Reserves screen edge space so other application windows do not overlap with the taskbar,
/// and maximizing windows fills all remaining screen space.
class WindowStrutService {
  String? _cachedWindowId;

  /// Finds the X11 window ID for Task Monitor.
  Future<String?> findWindowId({bool forceRefresh = false, int retries = 5}) async {
    if (!Platform.isLinux) return null;
    if (_cachedWindowId != null && !forceRefresh) {
      return _cachedWindowId;
    }

    for (int attempt = 0; attempt < retries; attempt++) {
      try {
        final res = await Process.run('xwininfo', ['-root', '-tree'], environment: Platform.environment);
        if (res.exitCode == 0) {
          final match = RegExp(r'(0x[0-9a-fA-F]+)\s+"task_monitor":').firstMatch(res.stdout.toString());
          if (match != null) {
            final wid = match.group(1)!;
            _cachedWindowId = wid;
            return wid;
          }
        }
      } catch (_) {}

      try {
        final res = await Process.run('xprop', ['-root', '_NET_CLIENT_LIST'], environment: Platform.environment);
        if (res.exitCode == 0) {
          final matches = RegExp(r'0x[0-9a-fA-F]+').allMatches(res.stdout.toString());
          for (final m in matches) {
            final wid = m.group(0)!;
            final propRes = await Process.run('xprop', ['-id', wid, 'WM_CLASS', 'WM_NAME'], environment: Platform.environment);
            if (propRes.exitCode == 0) {
              final out = propRes.stdout.toString();
              if (out.contains('com.example.task_monitor') || out.contains('task_monitor')) {
                _cachedWindowId = wid;
                return wid;
              }
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('WindowStrutService: Error finding window ID: $e');
        }
      }

      if (attempt < retries - 1) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    return null;
  }

  /// Moves and resizes the X11 window directly via libX11 to avoid Mutter panel clamping.
  Future<bool> moveResizeWindow({
    required int x,
    required int y,
    required int width,
    required int height,
    String? explicitWindowId,
  }) async {
    if (!Platform.isLinux) return false;
    final widStr = explicitWindowId ?? await findWindowId();
    if (widStr == null) return false;
    final wid = int.tryParse(widStr) ??
        (widStr.startsWith('0x') ? int.tryParse(widStr.substring(2), radix: 16) : null);
    if (wid == null) return false;

    try {
      final x11 = DynamicLibrary.open('libX11.so.6');
      final xOpenDisplay = x11.lookupFunction<_XOpenDisplayC, _XOpenDisplayDart>('XOpenDisplay');
      final xMoveResizeWindow = x11.lookupFunction<_XMoveResizeWindowC, _XMoveResizeWindowDart>('XMoveResizeWindow');
      final xFlush = x11.lookupFunction<_XFlushC, _XFlushDart>('XFlush');
      final xCloseDisplay = x11.lookupFunction<_XCloseDisplayC, _XCloseDisplayDart>('XCloseDisplay');

      final display = xOpenDisplay(nullptr);
      if (display != nullptr) {
        xMoveResizeWindow(display, wid, x, y, width, height);
        xFlush(display);
        xCloseDisplay(display);
        return true;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('WindowStrutService: Error moving window via X11: $e');
      }
    }
    return false;
  }

  /// Discovers the physical connected monitors via xrandr on Linux.
  Future<List<PhysicalMonitor>> getPhysicalMonitors() async {
    if (!Platform.isLinux) return [];
    try {
      ProcessResult res;
      try {
        res = await Process.run('xrandr', ['--current'], environment: Platform.environment, runInShell: true);
      } catch (_) {
        res = await Process.run('/usr/bin/xrandr', ['--current'], environment: Platform.environment);
      }
      if (res.exitCode == 0) {
        final lines = res.stdout.toString().split('\n');
        final monitors = <PhysicalMonitor>[];
        final regex = RegExp(r'(\S+)\s+connected\s+(?:primary\s+)?(\d+)x(\d+)\+(\d+)\+(\d+)');
        for (final line in lines) {
          if (line.contains(' connected ')) {
            final match = regex.firstMatch(line);
            if (match != null) {
              final name = match.group(1)!;
              final width = double.tryParse(match.group(2)!) ?? 1920.0;
              final height = double.tryParse(match.group(3)!) ?? 1080.0;
              final x = double.tryParse(match.group(4)!) ?? 0.0;
              final y = double.tryParse(match.group(5)!) ?? 0.0;
              final isPrimary = line.contains('primary');
              monitors.add(PhysicalMonitor(
                name: name,
                x: x,
                y: y,
                width: width,
                height: height,
                isPrimary: isPrimary,
              ));
            }
          }
        }
        if (monitors.isNotEmpty) {
          return monitors;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('WindowStrutService: Error getting physical monitors: $e');
      }
    }
    return [];
  }

  /// Discovers the root screen geometry (virtual desktop width & height) on X11.
  Future<Size> getRootGeometry() async {
    if (!Platform.isLinux) return const Size(1920, 1080);
    try {
      final res = await Process.run('xprop', ['-root', '_NET_DESKTOP_GEOMETRY'], environment: Platform.environment);
      if (res.exitCode == 0) {
        final match = RegExp(r'=\s*(\d+),\s*(\d+)').firstMatch(res.stdout.toString());
        if (match != null) {
          final w = double.tryParse(match.group(1)!) ?? 1920.0;
          final h = double.tryParse(match.group(2)!) ?? 1080.0;
          return Size(w, h);
        }
      }
    } catch (_) {}
    return const Size(1920, 1080);
  }

  /// Pure function calculating the 12-element _NET_WM_STRUT_PARTIAL and 4-element _NET_WM_STRUT.
  static StrutCalculation calculateStrut({
    required bool attachTop,
    required double displayX,
    required double displayY,
    required double displayWidth,
    required double displayHeight,
    required double barHeight,
    required double rootHeight,
  }) {
    int left = 0, right = 0, top = 0, bottom = 0;
    int leftStartY = 0, leftEndY = 0;
    int rightStartY = 0, rightEndY = 0;
    int topStartX = 0, topEndX = 0;
    int bottomStartX = 0, bottomEndX = 0;

    final startX = displayX.round();
    final endX = (displayX + displayWidth - 1).round();

    if (attachTop) {
      top = (displayY + barHeight).round();
      topStartX = startX;
      topEndX = endX;
    } else {
      final distanceFromRootBottom = (rootHeight - (displayY + displayHeight)).round();
      bottom = distanceFromRootBottom + barHeight.round();
      bottomStartX = startX;
      bottomEndX = endX;
    }

    final strutPartial = [
      left,
      right,
      top,
      bottom,
      leftStartY,
      leftEndY,
      rightStartY,
      rightEndY,
      topStartX,
      topEndX,
      bottomStartX,
      bottomEndX,
    ];

    final strut = [left, right, top, bottom];

    return StrutCalculation(
      strutPartial: strutPartial,
      strut: strut,
    );
  }

  /// Reserves screen space so other applications do not overlap with Task Monitor.
  Future<bool> reserveStrut({
    required bool attachTop,
    required double displayX,
    required double displayY,
    required double displayWidth,
    required double displayHeight,
    required double barHeight,
    String? explicitWindowId,
  }) async {
    if (!Platform.isLinux) return false;

    final wid = explicitWindowId ?? await findWindowId();
    if (wid == null) return false;

    try {
      final rootGeom = await getRootGeometry();
      final calc = calculateStrut(
        attachTop: attachTop,
        displayX: displayX,
        displayY: displayY,
        displayWidth: displayWidth,
        displayHeight: displayHeight,
        barHeight: barHeight,
        rootHeight: rootGeom.height,
      );

      final strutPartialStr = calc.strutPartial.join(', ');

      await Process.run('xprop', [
        '-id',
        wid,
        '-f',
        '_NET_WM_WINDOW_TYPE',
        '32a',
        '-set',
        '_NET_WM_WINDOW_TYPE',
        '_NET_WM_WINDOW_TYPE_DOCK',
      ], environment: Platform.environment);

      // Remove legacy 4-element strut so only the partial region beside the dock is affected
      await Process.run('xprop', ['-id', wid, '-remove', '_NET_WM_STRUT'], environment: Platform.environment);

      await Process.run('xprop', [
        '-id',
        wid,
        '-f',
        '_NET_WM_STRUT_PARTIAL',
        '32c',
        '-set',
        '_NET_WM_STRUT_PARTIAL',
        strutPartialStr,
      ], environment: Platform.environment);

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('WindowStrutService: Error applying strut: $e');
      }
      return false;
    }
  }

  /// Clears reserved space and returns window to normal type.
  Future<bool> clearStrut({String? explicitWindowId}) async {
    if (!Platform.isLinux) return false;

    final wid = explicitWindowId ?? await findWindowId();
    if (wid == null) return false;

    try {
      await Process.run('xprop', ['-id', wid, '-remove', '_NET_WM_STRUT'], environment: Platform.environment);
      await Process.run('xprop', ['-id', wid, '-remove', '_NET_WM_STRUT_PARTIAL'], environment: Platform.environment);
      await Process.run('xprop', [
        '-id',
        wid,
        '-f',
        '_NET_WM_WINDOW_TYPE',
        '32a',
        '-set',
        '_NET_WM_WINDOW_TYPE',
        '_NET_WM_WINDOW_TYPE_NORMAL',
      ], environment: Platform.environment);
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('WindowStrutService: Error clearing strut: $e');
      }
      return false;
    }
  }
}
