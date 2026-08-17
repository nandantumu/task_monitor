import 'dart:io';
import 'dart:ui' show Size;
import 'package:flutter/foundation.dart';

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
  Future<String?> findWindowId({bool forceRefresh = false}) async {
    if (!Platform.isLinux) return null;
    if (_cachedWindowId != null && !forceRefresh) {
      return _cachedWindowId;
    }

    try {
      final res = await Process.run('xprop', ['-root', '_NET_CLIENT_LIST']);
      if (res.exitCode == 0) {
        final matches = RegExp(r'0x[0-9a-fA-F]+').allMatches(res.stdout.toString());
        for (final m in matches) {
          final wid = m.group(0)!;
          final propRes = await Process.run('xprop', ['-id', wid, 'WM_CLASS', 'WM_NAME']);
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
    return null;
  }

  /// Discovers the root screen geometry (virtual desktop width & height) on X11.
  Future<Size> getRootGeometry() async {
    if (!Platform.isLinux) return const Size(1920, 1080);
    try {
      final res = await Process.run('xprop', ['-root', '_NET_DESKTOP_GEOMETRY']);
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
      final strutStr = calc.strut.join(', ');

      await Process.run('xprop', [
        '-id',
        wid,
        '-f',
        '_NET_WM_WINDOW_TYPE',
        '32a',
        '-set',
        '_NET_WM_WINDOW_TYPE',
        '_NET_WM_WINDOW_TYPE_DOCK',
      ]);

      await Process.run('xprop', [
        '-id',
        wid,
        '-f',
        '_NET_WM_STRUT_PARTIAL',
        '32c',
        '-set',
        '_NET_WM_STRUT_PARTIAL',
        strutPartialStr,
      ]);

      await Process.run('xprop', [
        '-id',
        wid,
        '-f',
        '_NET_WM_STRUT',
        '32c',
        '-set',
        '_NET_WM_STRUT',
        strutStr,
      ]);

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
      await Process.run('xprop', ['-id', wid, '-remove', '_NET_WM_STRUT']);
      await Process.run('xprop', ['-id', wid, '-remove', '_NET_WM_STRUT_PARTIAL']);
      await Process.run('xprop', [
        '-id',
        wid,
        '-f',
        '_NET_WM_WINDOW_TYPE',
        '32a',
        '-set',
        '_NET_WM_WINDOW_TYPE',
        '_NET_WM_WINDOW_TYPE_NORMAL',
      ]);
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('WindowStrutService: Error clearing strut: $e');
      }
      return false;
    }
  }
}
