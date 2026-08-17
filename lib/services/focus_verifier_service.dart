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
    String activeWindowTitle = '',
    List<String> openWindowTitles = const [],
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

      // Step 2: Evaluate match between focus text and desktop state using Gemma
      return await _evaluateFocusMatch(
        trimmedFocus,
        activeWindowTitle,
        openWindowTitles,
        visionDescription,
        timeout,
      );
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
    try {
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
    } catch (_) {}
    return '';
  }

  /// Step 2: Use Gemma with verdict-first chain-of-thought to score focus match
  Future<FocusVerificationResult> _evaluateFocusMatch(
    String focusObjective,
    String activeWindowTitle,
    List<String> openWindowTitles,
    String screenDescription,
    Duration timeout,
  ) async {
    final windowSummary = [
      if (activeWindowTitle.isNotEmpty) 'Active Window: "$activeWindowTitle"',
      if (openWindowTitles.isNotEmpty)
        'Open Desktop Windows: ${openWindowTitles.map((t) => '"$t"').join(', ')}',
    ].join('\n');

    final prompt = '''You are a strict, skeptical productivity focus auditor.

USER FOCUS OBJECTIVE: "$focusObjective"

DESKTOP WINDOWS & APPLICATIONS:
$windowSummary

VISUAL SCREEN DESCRIPTION:
"$screenDescription"

YOUR TASK:
Determine if the user is actively working on the objective ("$focusObjective").
- If the active window or open documents/tools are completely unrelated (e.g. IDE/terminal vs math proof, or social media/gaming/random browsing), mark verdict as NO.
- If the user is actively using tools/files directly matching the objective, mark verdict as YES.
- If ambiguous or partially related research, mark verdict as PARTIAL.

FORMAT YOUR RESPONSE EXACTLY AS:
Verdict: [YES/NO/PARTIAL]
Reason: [1-sentence explanation of what is open and why it matches or does not match]
Score: [0-100] (Rules: If NO -> 0-15. If PARTIAL -> 25-45. If YES -> 75-100)''';

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
        return _parseVerdictResponse(text, focusObjective, screenDescription);
      } else {
        return FocusVerificationResult.error('Ollama HTTP ${response.statusCode}');
      }
    } catch (e) {
      return FocusVerificationResult.error('Connection error: $e');
    }
  }

  FocusVerificationResult _parseVerdictResponse(
    String text,
    String focusObjective,
    String screenDescription,
  ) {
    try {
      final upper = text.toUpperCase();
      String? verdict;
      if (upper.contains('VERDICT: YES') || upper.contains('VERDICT:YES') || upper.contains('**VERDICT: YES**')) {
        verdict = 'YES';
      } else if (upper.contains('VERDICT: NO') || upper.contains('VERDICT:NO') || upper.contains('**VERDICT: NO**')) {
        verdict = 'NO';
      } else if (upper.contains('VERDICT: PARTIAL') || upper.contains('VERDICT:PARTIAL') || upper.contains('**VERDICT: PARTIAL**')) {
        verdict = 'PARTIAL';
      }

      // Extract Reason
      String reason = '';
      final reasonMatch = RegExp(r'Reason:\s*(.+?)(?=\n|Score:|$)', caseSensitive: false).firstMatch(text);
      if (reasonMatch != null) {
        reason = reasonMatch.group(1)!.trim().replaceAll('*', '');
      }

      // Extract Score
      double score = 50.0;
      final scoreMatch = RegExp(r'Score:\s*(\d{1,3})', caseSensitive: false).firstMatch(text);
      if (scoreMatch != null) {
        score = double.tryParse(scoreMatch.group(1)!) ?? 50.0;
      }

      // Enforce verdict constraints to prevent small-model hallucination inversions
      if (verdict == 'NO') {
        score = score.clamp(0.0, 15.0);
        if (reason.isEmpty) reason = 'Activity on screen does not match "$focusObjective".';
      } else if (verdict == 'YES') {
        score = score.clamp(75.0, 100.0);
        if (reason.isEmpty) reason = 'Activity matches "$focusObjective".';
      } else if (verdict == 'PARTIAL') {
        score = score.clamp(25.0, 45.0);
        if (reason.isEmpty) reason = 'Activity partially relates to "$focusObjective".';
      }

      return FocusVerificationResult(
        matchPercentage: score,
        reason: reason.isNotEmpty ? reason : 'Evaluated against "$focusObjective"',
        timestamp: DateTime.now(),
      );
    } catch (_) {}

    return _heuristicEvaluation(focusObjective, screenDescription, const []);
  }

  FocusVerificationResult _heuristicEvaluation(
    String focusObjective,
    String screenDescription,
    List<String> openWindows,
  ) {
    final lowerDesc = '${screenDescription.toLowerCase()} ${openWindows.join(' ').toLowerCase()}';
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
    } else {
      score = 10.0; // Distracted / unrelated
    }

    return FocusVerificationResult(
      matchPercentage: score.clamp(0.0, 100.0),
      reason: 'Desktop windows evaluated against: "$focusObjective"',
      timestamp: DateTime.now(),
    );
  }

  void dispose() {
    _client.close();
  }
}
