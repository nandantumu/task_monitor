import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Represents the evaluation result from Gemma VLM.
class FocusVerificationResult {
  final double matchPercentage;
  final String reason;
  final bool isSuccess;
  final String? errorMessage;
  final DateTime timestamp;

  const FocusVerificationResult({
    required this.matchPercentage,
    required this.reason,
    this.isSuccess = true,
    this.errorMessage,
    required this.timestamp,
  });

  bool get isHighMatch => matchPercentage > 50.0;
  bool get isMediumMatch => matchPercentage >= 20.0 && matchPercentage <= 50.0;
  bool get isLowMatch => matchPercentage < 20.0;

  factory FocusVerificationResult.error(String message) {
    return FocusVerificationResult(
      matchPercentage: 0.0,
      reason: message,
      isSuccess: false,
      errorMessage: message,
      timestamp: DateTime.now(),
    );
  }

  factory FocusVerificationResult.simulated(String focusText) {
    // Deterministic simulation based on text length for testing/offline environments
    final trimmed = focusText.trim();
    if (trimmed.isEmpty) {
      return FocusVerificationResult(
        matchPercentage: 0.0,
        reason: 'No focus objective defined.',
        timestamp: DateTime.now(),
      );
    }
    return FocusVerificationResult(
      matchPercentage: 85.0,
      reason: 'On-screen activity matches current focus: "$trimmed".',
      timestamp: DateTime.now(),
    );
  }
}

/// Service for verifying screen activity against the current focus objective using local VLM + LLM.
class FocusVerifierService {
  final String baseUrl;
  final String visionModel;
  final String textModel;
  final http.Client _client;

  FocusVerifierService({
    this.baseUrl = 'http://127.0.0.1:11434',
    this.visionModel = 'moondream',
    this.textModel = 'gemma:2b',
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Evaluates screen image against the target focus objective.
  Future<FocusVerificationResult> verifyFocus({
    required String focusText,
    required String base64Image,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final trimmedFocus = focusText.trim();
    if (trimmedFocus.isEmpty) {
      return FocusVerificationResult(
        matchPercentage: 0.0,
        reason: 'No focus objective specified.',
        timestamp: DateTime.now(),
      );
    }

    try {
      // Step 1: Extract screen description using fast vision model (moondream)
      final visionDescription = await _getScreenDescription(base64Image, timeout);
      if (visionDescription.isEmpty) {
        return FocusVerificationResult.error('Failed to analyze screen image');
      }

      // Step 2: Evaluate match between focus text and screen description using Gemma
      return await _evaluateFocusMatch(trimmedFocus, visionDescription, timeout);
    } catch (e) {
      final errMsg = 'Focus verification error: $e';
      if (kDebugMode) {
        debugPrint(errMsg);
      }
      return FocusVerificationResult.error(errMsg);
    }
  }

  /// Step 1: Get detailed visual description of screen snapshot
  Future<String> _getScreenDescription(String base64Image, Duration timeout) async {
    final uri = Uri.parse('$baseUrl/api/generate');
    final body = jsonEncode({
      'model': visionModel,
      'prompt': 'Question: Describe this image in detail, including open windows, applications, text, and user activity.\n\nAnswer:',
      'images': [base64Image],
      'stream': false,
    });

    final response = await _client
        .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['response'] as String? ?? '').trim();
    }
    return '';
  }

  /// Step 2: Use Gemma to score how well the screen description matches the focus objective
  Future<FocusVerificationResult> _evaluateFocusMatch(
    String focusObjective,
    String screenDescription,
    Duration timeout,
  ) async {
    final prompt = '''You are a strict, skeptical productivity focus auditor.
The user's stated focus objective is: "$focusObjective"
The user's computer screen currently shows:
"$screenDescription"

Evaluate whether the screen activity is DIRECTLY and SPECIFICALLY about the stated objective:
- 80-100%: The screen specifically shows tools, files, or documents directly solving the stated objective.
- 30-50%: Tangentially related or ambiguous research.
- 0-15%: Completely different domain or unrelated task (e.g. programming/code when objective is math proof/writing, or entertainment/social media/idle desktop).

Be strict: generic work or having a code editor open is NOT a match if the objective is completely different (e.g. working through proof vs software programming).

Respond ONLY with a JSON object in this format:
{"match_percentage": <0-100>, "reason": "<1-sentence explanation of what is on screen and why it specifically matches or fails to match the objective>"}''';

    try {
      final uri = Uri.parse('$baseUrl/api/generate');
      final body = jsonEncode({
        'model': textModel,
        'prompt': prompt,
        'stream': false,
      });

      final response = await _client
          .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final text = (data['response'] as String? ?? '').trim();
        return _parseGemmaResponse(text, focusObjective, screenDescription);
      }
    } catch (_) {}

    // Heuristic fallback if text LLM query fails
    return _heuristicEvaluation(focusObjective, screenDescription);
  }

  FocusVerificationResult _parseGemmaResponse(
    String text,
    String focusObjective,
    String screenDescription,
  ) {
    try {
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (jsonMatch != null) {
        final parsed = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;

        double percentage = 0.0;
        if (parsed.containsKey('match_percentage')) {
          final val = parsed['match_percentage'];
          if (val is num) {
            percentage = val.toDouble();
          } else if (val is String) {
            percentage = double.tryParse(val.replaceAll('%', '').trim()) ?? 0.0;
          }
        }

        final reason = (parsed['reason'] as String? ?? '').trim();

        return FocusVerificationResult(
          matchPercentage: percentage.clamp(0.0, 100.0),
          reason: reason.isNotEmpty ? reason : 'Evaluated against "$focusObjective"',
          timestamp: DateTime.now(),
        );
      }
    } catch (_) {}

    return _heuristicEvaluation(focusObjective, screenDescription);
  }

  FocusVerificationResult _heuristicEvaluation(
    String focusObjective,
    String screenDescription,
  ) {
    final lowerDesc = screenDescription.toLowerCase();
    final words = focusObjective
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 3)
        .toList();

    int matchedWords = 0;
    for (final word in words) {
      if (lowerDesc.contains(word)) {
        matchedWords++;
      }
    }

    double score = 0.0;
    if (words.isNotEmpty && matchedWords > 0) {
      score = (matchedWords / words.length) * 100.0;
    } else if (lowerDesc.contains('browser') || lowerDesc.contains('desktop') || lowerDesc.contains('mountain')) {
      score = 10.0; // Distracted / unrelated wallpaper / browser
    }

    return FocusVerificationResult(
      matchPercentage: score.clamp(0.0, 100.0),
      reason: screenDescription.length > 100
          ? '${screenDescription.substring(0, 97)}…'
          : screenDescription,
      timestamp: DateTime.now(),
    );
  }

  void dispose() {
    _client.close();
  }
}
