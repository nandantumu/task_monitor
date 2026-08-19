import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_monitor/services/window_strut_service.dart';

void main() {
  group('WindowStrutService calculateStrut', () {
    test('calculates Top strut on primary monitor (offset X=1080, Y=0)', () {
      final calc = WindowStrutService.calculateStrut(
        attachTop: true,
        displayX: 1080,
        displayY: 0,
        displayWidth: 2560,
        displayHeight: 1440,
        barHeight: 50,
        rootHeight: 1920,
      );

      // Top value is 50
      expect(calc.strut[2], equals(50));
      expect(calc.strut[0], equals(0)); // left
      expect(calc.strut[1], equals(0)); // right
      expect(calc.strut[3], equals(0)); // bottom

      // Strut partial: [left, right, top, bottom, left_start_y, left_end_y, right_start_y, right_end_y, top_start_x, top_end_x, bottom_start_x, bottom_end_x]
      expect(calc.strutPartial[2], equals(50));
      expect(calc.strutPartial[8], equals(1080)); // top_start_x
      expect(calc.strutPartial[9], equals(3639)); // top_end_x (1080 + 2560 - 1)
      expect(calc.strutPartial[10], equals(0)); // bottom_start_x
      expect(calc.strutPartial[11], equals(0)); // bottom_end_x
    });

    test('calculates Bottom strut on primary monitor (offset X=1080, Y=0, H=1440 in 1920 root)', () {
      final calc = WindowStrutService.calculateStrut(
        attachTop: false,
        displayX: 1080,
        displayY: 0,
        displayWidth: 2560,
        displayHeight: 1440,
        barHeight: 50,
        rootHeight: 1920,
      );

      // Bottom value: (1920 - 1440) + 50 = 530
      expect(calc.strut[3], equals(530));
      expect(calc.strut[2], equals(0)); // top

      // Strut partial
      expect(calc.strutPartial[3], equals(530)); // bottom
      expect(calc.strutPartial[10], equals(1080)); // bottom_start_x
      expect(calc.strutPartial[11], equals(3639)); // bottom_end_x
      expect(calc.strutPartial[8], equals(0)); // top_start_x
      expect(calc.strutPartial[9], equals(0)); // top_end_x
    });

    test('calculates Top strut on secondary full-height monitor (X=0, Y=0, W=1080, H=1920)', () {
      final calc = WindowStrutService.calculateStrut(
        attachTop: true,
        displayX: 0,
        displayY: 0,
        displayWidth: 1080,
        displayHeight: 1920,
        barHeight: 50,
        rootHeight: 1920,
      );

      expect(calc.strut[2], equals(50));
      expect(calc.strutPartial[8], equals(0));
      expect(calc.strutPartial[9], equals(1079));
    });

    test('calculates Bottom strut on secondary full-height monitor (X=0, Y=0, W=1080, H=1920)', () {
      final calc = WindowStrutService.calculateStrut(
        attachTop: false,
        displayX: 0,
        displayY: 0,
        displayWidth: 1080,
        displayHeight: 1920,
        barHeight: 50,
        rootHeight: 1920,
      );

      // (1920 - 1920) + 50 = 50
      expect(calc.strut[3], equals(50));
      expect(calc.strutPartial[10], equals(0));
      expect(calc.strutPartial[11], equals(1079));
    });
  });

  group('WindowStrutService method channel delegation', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final service = WindowStrutService();
    final log = <MethodCall>[];

    setUp(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.example.task_monitor/macos_window'),
        (MethodCall methodCall) async {
          log.add(methodCall);
          switch (methodCall.method) {
            case 'setAlwaysOnTop':
            case 'reserveStrut':
            case 'clearStrut':
            case 'checkAccessibilityPermission':
            case 'requestAccessibilityPermission':
              return true;
            default:
              return null;
          }
        },
      );
    });

    test('setAlwaysOnTop calls native method on macOS', () async {
      final res = await service.setAlwaysOnTop(true);
      expect(res, isTrue);
    });

    test('reserveStrut calls native method on macOS', () async {
      final res = await service.reserveStrut(
        attachTop: true,
        displayX: 0,
        displayY: 0,
        displayWidth: 1920,
        displayHeight: 1080,
        barHeight: 50,
      );
      expect(res, isTrue);
    });

    test('clearStrut calls native method on macOS', () async {
      final res = await service.clearStrut();
      expect(res, isTrue);
    });

    test('accessibility permission methods execute', () async {
      final check = await service.checkAccessibilityPermission();
      expect(check, isTrue);

      final req = await service.requestAccessibilityPermission();
      expect(req, isTrue);
    });
  }, skip: !Platform.isMacOS);
}
