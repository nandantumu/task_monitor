import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Holds the captured screen data.
class ScreenCaptureResult {
  final String base64Image;
  final List<int> bytes;
  final String format;

  const ScreenCaptureResult({
    required this.base64Image,
    required this.bytes,
    this.format = 'jpeg',
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
        if (finalFile.existsSync()) {
          finalFile.deleteSync();
        }
      } catch (_) {}

      return ScreenCaptureResult(
        base64Image: base64String,
        bytes: bytes,
        format: 'jpeg',
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error during screen capture: $e');
      }
      return null;
    }
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
