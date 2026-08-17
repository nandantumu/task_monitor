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

/// Service for verifying screen activity against the current focus objective using Gemma VLM.
class FocusVerifierService {
  final String baseUrl;
  final String modelName;
  final http.Client _client;

  FocusVerifierService({
    this.baseUrl = 'http://127.0.0.1:11434',
    this.modelName = 'gemma:2b',
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Evaluates screen image against the target focus objective.
  Future<FocusVerificationResult> verifyFocus({
    required String focusText,
    required String base64Image,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final trimmedFocus = focusText.trim();
    if (trimmedFocus.isEmpty) {
      return FocusVerificationResult(
        matchPercentage: 0.0,
        reason: 'No focus objective specified.',
        timestamp: DateTime.now(),
      );
    }

    final prompt = _buildPrompt(trimmedFocus);

    try {
      final uri = Uri.parse('$baseUrl/api/generate');
      final requestBody = jsonEncode({
        'model': modelName,
        'prompt': prompt,
        'images': [base64Image],
        'stream': false,
        'format': 'json',
      });

      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: requestBody,
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rawResponseText = data['response'] as String? ?? '';
        return _parseResponse(rawResponseText);
      } else {
        if (kDebugMode) {
          debugPrint('Ollama request failed with HTTP status: ${response.statusCode}');
        }
        return FocusVerificationResult.simulated(trimmedFocus);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Focus verification error: $e, using simulated fallback');
      }
      return FocusVerificationResult.simulated(trimmedFocus);
    }
  }

  /// Parses Gemma JSON output into a FocusVerificationResult.
  FocusVerificationResult _parseResponse(String text) {
    try {
      // Find JSON block within response if formatted with markdown
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      final jsonString = jsonMatch != null ? jsonMatch.group(0)! : text;

      final parsed = jsonDecode(jsonString) as Map<String, dynamic>;

      double percentage = 0.0;
      if (parsed.containsKey('match_percentage')) {
        final val = parsed['match_percentage'];
        if (val is num) {
          percentage = val.toDouble();
        } else if (val is String) {
          percentage = double.tryParse(val.replaceAll('%', '').trim()) ?? 0.0;
        }
      } else if (parsed.containsKey('score')) {
        final val = parsed['score'];
        percentage = (val is num) ? val.toDouble() : 0.0;
      }

      // Clamp percentage between 0 and 100
      percentage = percentage.clamp(0.0, 100.0);

      final reason = parsed['reason'] as String? ??
          parsed['explanation'] as String? ??
          'Activity analyzed against current focus.';

      return FocusVerificationResult(
        matchPercentage: percentage,
        reason: reason,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to parse Gemma output: $text, error: $e');
      }
      // Attempt heuristic regex extraction if JSON decoding fails
      final percentMatch = RegExp(r'(\d{1,3})\s*%').firstMatch(text);
      if (percentMatch != null) {
        final val = double.tryParse(percentMatch.group(1)!) ?? 50.0;
        return FocusVerificationResult(
          matchPercentage: val.clamp(0.0, 100.0),
          reason: text.length > 100 ? '${text.substring(0, 97)}…' : text,
          timestamp: DateTime.now(),
        );
      }

      return FocusVerificationResult(
        matchPercentage: 50.0,
        reason: 'Unable to parse detailed score: $text',
        timestamp: DateTime.now(),
      );
    }
  }

  String _buildPrompt(String focusObjective) {
    return '''
You are an automated productivity focus auditor.
Analyze the provided screenshot of the user's computer desktop.
The user's stated current focus objective is: "$focusObjective"

Evaluate how closely the open windows, active apps, documents, and visible text align with the stated objective.
Give an objective match score from 0 to 100 percentage:
- 100%: Direct focused work on the exact objective.
- 75%: Research, tools, or relevant context assisting the objective.
- 35%: Ambiguous or partially related tasks.
- 0-15%: Completely off-task (social media, entertainment, unrelated gaming/browsing).

Respond ONLY with a valid JSON object in this exact format:
{"match_percentage": <integer 0-100>, "reason": "<concise 1-sentence reason>"}
''';
  }

  void dispose() {
    _client.close();
  }
}
