import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Holds the captured screen data and active desktop context.
class ScreenCaptureResult {
  final String base64Image;
  final List<int> bytes;
  final String format;
  final String activeWindowTitle;
  final List<String> openWindowTitles;

  const ScreenCaptureResult({
    required this.base64Image,
    required this.bytes,
    this.format = 'jpeg',
    this.activeWindowTitle = '',
    this.openWindowTitles = const [],
  });
}

/// Headless cross-platform screen capture service.
class ScreenCaptureService {
  /// Captures the current primary display screen and returns downscaled image data.
  static Future<ScreenCaptureResult?> captureScreen({
    int targetWidth = 768,
    int quality = 80,
  }) async {
    try {
      final tempDir = Directory.systemTemp;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final rawPath = '${tempDir.path}/task_monitor_screen_$timestamp.png';
      final scaledPath = '${tempDir.path}/task_monitor_screen_scaled_$timestamp.jpg';

      var captureSuccess = false;

      if (Platform.isLinux) {
        captureSuccess = await _captureLinux(rawPath);
      } else if (Platform.isMacOS) {
        captureSuccess = await _captureMacOS(rawPath);
      } else if (Platform.isWindows) {
        captureSuccess = await _captureWindows(rawPath);
      }

      if (!captureSuccess || !File(rawPath).existsSync()) {
        if (kDebugMode) {
          debugPrint('Screen capture failed: output file not generated');
        }
        return null;
      }

      // Collect desktop window titles on Linux for ground-truth context
      var activeTitle = '';
      var openTitles = <String>[];
      if (Platform.isLinux) {
        activeTitle = await _getActiveWindowTitleLinux();
        openTitles = await _getOpenWindowTitlesLinux();
      }

      // Downscale image if 'convert' or 'ffmpeg' is available to accelerate VLM inference
      final finalFile = await _downscaleImage(rawPath, scaledPath, targetWidth, quality);
      final bytes = await finalFile.readAsBytes();
      final base64String = base64Encode(bytes);

      // Clean up temporary files
      try {
        if (File(rawPath).existsSync()) {
          File(rawPath).deleteSync();
        }
        if (File(scaledPath).existsSync() && scaledPath != finalFile.path) {
          File(scaledPath).deleteSync();
        }
        if (finalFile.existsSync() && finalFile.path != rawPath && finalFile.path != scaledPath) {
          finalFile.deleteSync();
        }
      } catch (_) {}

      return ScreenCaptureResult(
        base64Image: base64String,
        bytes: bytes,
        activeWindowTitle: activeTitle,
        openWindowTitles: openTitles,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Screen capture error: $e');
      }
      return null;
    }
  }

  static String _categorizeWindowClass(String wmClass) {
    final lower = wmClass.toLowerCase();
    if (lower.contains('code') || lower.contains('cursor') || lower.contains('antigravity') ||
        lower.contains('idea') || lower.contains('pycharm') || lower.contains('clion') ||
        lower.contains('sublime') || lower.contains('emacs') || lower.contains('vim')) {
      return 'Code Editor / IDE';
    }
    if (lower.contains('ghostty') || lower.contains('terminal') || lower.contains('kitty') ||
        lower.contains('alacritty') || lower.contains('xterm') || lower.contains('bash') || lower.contains('zsh')) {
      return 'Terminal';
    }
    if (lower.contains('firefox') || lower.contains('chrome') || lower.contains('chromium') ||
        lower.contains('brave') || lower.contains('edge') || lower.contains('navigator')) {
      return 'Web Browser';
    }
    if (lower.contains('texstudio') || lower.contains('overleaf') || lower.contains('kile') ||
        lower.contains('lyx') || lower.contains('xournal') || lower.contains('obsidian') ||
        lower.contains('libreoffice') || lower.contains('writer') || lower.contains('pdf') ||
        lower.contains('evince') || lower.contains('okular') || lower.contains('zathura')) {
      return 'Document / Notes / LaTeX';
    }
    if (lower.contains('slack') || lower.contains('discord') || lower.contains('telegram') ||
        lower.contains('signal') || lower.contains('teams') || lower.contains('zoom')) {
      return 'Communication';
    }
    if (lower.contains('spotify') || lower.contains('vlc') || lower.contains('steam')) {
      return 'Media / Entertainment';
    }
    return '';
  }

  static Future<String> _getActiveWindowTitleLinux() async {
    try {
      final res = await Process.run('xprop', ['-root', '_NET_ACTIVE_WINDOW']);
      if (res.exitCode == 0) {
        final match = RegExp(r'0x[0-9a-fA-F]+').firstMatch(res.stdout.toString());
        if (match != null) {
          final winId = match.group(0)!;
          final propRes = await Process.run('xprop', ['-id', winId, '_NET_WM_NAME', 'WM_NAME', 'WM_CLASS']);
          if (propRes.exitCode == 0) {
            final out = propRes.stdout.toString();
            final titleMatch = RegExp(r'(?:_NET_WM_NAME|WM_NAME)\s*\(.*?\)\s*=\s*"(.*)"').firstMatch(out);
            final classMatch = RegExp(r'WM_CLASS\s*\(.*?\)\s*=\s*(.*)').firstMatch(out);
            final title = titleMatch?.group(1)?.trim() ?? '';
            final cls = classMatch?.group(1)?.trim() ?? '';
            final cat = _categorizeWindowClass(cls);
            if (title.isNotEmpty) {
              return cat.isNotEmpty ? '$title [$cat]' : title;
            }
          }
        }
      }
    } catch (_) {}
    return '';
  }

  static Future<List<String>> _getOpenWindowTitlesLinux() async {
    try {
      final res = await Process.run('xprop', ['-root', '_NET_CLIENT_LIST']);
      if (res.exitCode == 0) {
        final matches = RegExp(r'0x[0-9a-fA-F]+').allMatches(res.stdout.toString());
        final titles = <String>[];
        for (final m in matches) {
          final wid = m.group(0)!;
          final propRes = await Process.run('xprop', ['-id', wid, '_NET_WM_NAME', 'WM_NAME', 'WM_CLASS']);
          if (propRes.exitCode == 0) {
            final out = propRes.stdout.toString();
            final titleMatch = RegExp(r'(?:_NET_WM_NAME|WM_NAME)\s*\(.*?\)\s*=\s*"(.*)"').firstMatch(out);
            final classMatch = RegExp(r'WM_CLASS\s*\(.*?\)\s*=\s*(.*)').firstMatch(out);
            final title = titleMatch?.group(1)?.trim() ?? '';
            final cls = classMatch?.group(1)?.trim() ?? '';
            if (title.isNotEmpty && !title.startsWith('Desktop Icons') && title != 'task_monitor') {
              final cat = _categorizeWindowClass(cls);
              titles.add(cat.isNotEmpty ? '$title [$cat]' : title);
            }
          }
        }
        return titles;
      }
    } catch (_) {}
    return const [];
  }

  static Future<bool> _captureLinux(String outputPath) async {
    // Try gnome-screenshot first
    try {
      final result = await Process.run('gnome-screenshot', ['-f', outputPath]);
      if (result.exitCode == 0 && File(outputPath).existsSync()) {
        return true;
      }
    } catch (_) {}

    // Try ImageMagick import (standard X11)
    try {
      final result = await Process.run('import', ['-window', 'root', outputPath]);
      if (result.exitCode == 0 && File(outputPath).existsSync()) {
        return true;
      }
    } catch (_) {}

    // Try grim (Wayland)
    try {
      final result = await Process.run('grim', [outputPath]);
      if (result.exitCode == 0 && File(outputPath).existsSync()) {
        return true;
      }
    } catch (_) {}

    // Try scrot
    try {
      final result = await Process.run('scrot', [outputPath]);
      if (result.exitCode == 0 && File(outputPath).existsSync()) {
        return true;
      }
    } catch (_) {}

    return false;
  }

  static Future<bool> _captureMacOS(String outputPath) async {
    try {
      final result = await Process.run('screencapture', ['-x', outputPath]);
      return result.exitCode == 0 && File(outputPath).existsSync();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _captureWindows(String outputPath) async {
    // For Windows desktop, fallback to powershell snippet or existing tool
    return false;
  }

  static Future<File> _downscaleImage(
    String inputPath,
    String outputPath,
    int targetWidth,
    int quality,
  ) async {
    // Try ImageMagick convert
    try {
      final result = await Process.run('convert', [
        inputPath,
        '-resize',
        '${targetWidth}x',
        '-quality',
        '$quality',
        outputPath,
      ]);
      if (result.exitCode == 0 && File(outputPath).existsSync()) {
        return File(outputPath);
      }
    } catch (_) {}

    // Try ffmpeg
    try {
      final result = await Process.run('ffmpeg', [
        '-y',
        '-i',
        inputPath,
        '-vf',
        'scale=$targetWidth:-1',
        '-q:v',
        '3',
        outputPath,
      ]);
      if (result.exitCode == 0 && File(outputPath).existsSync()) {
        return File(outputPath);
      }
    } catch (_) {}

    // Fallback to raw captured file
    return File(inputPath);
  }
}
