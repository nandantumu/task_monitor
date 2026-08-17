import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_monitor/services/focus_verifier_service.dart';

void main() {
  group('FocusVerificationResult', () {
    test('classifies high match (> 50%) as green', () {
      final res = FocusVerificationResult(
        matchPercentage: 85.0,
        reason: 'User is editing code in IDE',
        timestamp: DateTime.now(),
      );
      expect(res.isHighMatch, isTrue);
      expect(res.isMediumMatch, isFalse);
      expect(res.isLowMatch, isFalse);
    });

    test('classifies medium match (20% - 50%) as yellow', () {
      final res = FocusVerificationResult(
        matchPercentage: 35.0,
        reason: 'User is searching for documentation',
        timestamp: DateTime.now(),
      );
      expect(res.isHighMatch, isFalse);
      expect(res.isMediumMatch, isTrue);
      expect(res.isLowMatch, isFalse);
    });

    test('classifies low match (< 20%) as red', () {
      final res = FocusVerificationResult(
        matchPercentage: 10.0,
        reason: 'User is on unrelated social media',
        timestamp: DateTime.now(),
      );
      expect(res.isHighMatch, isFalse);
      expect(res.isMediumMatch, isFalse);
      expect(res.isLowMatch, isTrue);
    });

    test('handles boundary score 50% correctly', () {
      final res = FocusVerificationResult(
        matchPercentage: 50.0,
        reason: 'Borderline relevant activity',
        timestamp: DateTime.now(),
      );
      expect(res.isMediumMatch, isTrue);
      expect(res.isHighMatch, isFalse);
    });

    test('handles boundary score 20% correctly', () {
      final res = FocusVerificationResult(
        matchPercentage: 20.0,
        reason: 'Barely relevant activity',
        timestamp: DateTime.now(),
      );
      expect(res.isMediumMatch, isTrue);
      expect(res.isLowMatch, isFalse);
    });
  });

  group('FocusVerifierService', () {
    test('parses JSON response accurately', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'response': jsonEncode({
              'match_percentage': 92,
              'reason': 'Direct match with task requirements',
            }),
          }),
          200,
        );
      });

      final service = FocusVerifierService(client: mockClient);
      final result = await service.verifyFocus(
        focusText: 'Implement focus verifier',
        base64Image: 'dGVzdA==',
      );

      expect(result.matchPercentage, 92.0);
      expect(result.reason, 'Direct match with task requirements');
      expect(result.isHighMatch, isTrue);
    });

    test('returns error result if endpoint is unreachable', () async {
      final mockClient = MockClient((request) async {
        throw Exception('Connection refused');
      });

      final service = FocusVerifierService(client: mockClient);
      final result = await service.verifyFocus(
        focusText: 'Fix layout bug',
        base64Image: 'dGVzdA==',
      );

      expect(result.isSuccess, isFalse);
      expect(result.matchPercentage, 0.0);
      expect(result.reason, contains('Connection refused'));
    });

    test('handles empty focus text gracefully', () async {
      final service = FocusVerifierService();
      final result = await service.verifyFocus(
        focusText: '   ',
        base64Image: 'dGVzdA==',
      );

      expect(result.matchPercentage, 0.0);
    });
  });
}
