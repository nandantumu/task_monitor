import 'package:flutter/material.dart';
import 'package:task_monitor/services/focus_verifier_service.dart';

/// Interactive modal dialog displaying detailed AI focus audit verdict, reasoning, and active windows.
class FocusVerdictDialog extends StatelessWidget {
  final String currentFocus;
  final FocusVerificationResult? result;
  final bool isAuditing;
  final VoidCallback onReaudit;

  const FocusVerdictDialog({
    super.key,
    required this.currentFocus,
    required this.result,
    required this.isAuditing,
    required this.onReaudit,
  });

  static Future<void> show(
    BuildContext context, {
    required String currentFocus,
    required FocusVerificationResult? result,
    required bool isAuditing,
    required VoidCallback onReaudit,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => FocusVerdictDialog(
        currentFocus: currentFocus,
        result: result,
        isAuditing: isAuditing,
        onReaudit: onReaudit,
      ),
    );
  }

  Color _getStatusColor(double score) {
    if (score > 50.0) return const Color(0xFF2E7D32); // Green
    if (score >= 20.0) return const Color(0xFFF57F17); // Amber
    return const Color(0xFFD32F2F); // Red
  }

  String _getStatusLabel(double score) {
    if (score > 50.0) return 'ON TASK';
    if (score >= 20.0) return 'PARTIALLY ALIGNED';
    return 'OFF TASK / DISTRACTED';
  }

  IconData _getStatusIcon(double score) {
    if (score > 50.0) return Icons.check_circle_outline;
    if (score >= 20.0) return Icons.help_outline;
    return Icons.warning_amber_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final hasResult = result != null && result!.isSuccess;
    final score = hasResult ? result!.matchPercentage : 0.0;
    final statusColor = hasResult ? _getStatusColor(score) : Colors.grey.shade700;
    final statusLabel = hasResult ? _getStatusLabel(score) : 'AUDIT PENDING';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      child: Container(
        width: 480,
        constraints: const BoxConstraints(maxHeight: 560),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    hasResult ? _getStatusIcon(score) : Icons.auto_awesome,
                    color: statusColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Gemma AI Focus Audit',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        'Evaluated against active screen & desktop context',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.black54),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Scrollable Details Body
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Score Banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: statusColor.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          Text(
                            hasResult ? '${score.round()}%' : '--%',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: statusColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  statusLabel,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: statusColor,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Text(
                                  hasResult
                                      ? (score > 50
                                          ? 'Active screen strongly matches focus.'
                                          : score >= 20
                                              ? 'Ambiguous or partially related tools.'
                                              : 'Activity appears off-task (alert triggered).')
                                      : 'No audit completed yet for this session.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Target Focus Objective
                    _buildSection(
                      title: 'Current Focus Target',
                      icon: Icons.flag_outlined,
                      content: Text(
                        currentFocus.trim().isNotEmpty
                            ? currentFocus
                            : '(No focus objective specified)',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Reason / Explanation
                    _buildSection(
                      title: 'AI Verdict Reason',
                      icon: Icons.psychology_outlined,
                      content: Text(
                        result != null && result!.reason.isNotEmpty
                            ? result!.reason
                            : 'Click "Re-audit Now" below to inspect screen activity.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Active Window & Tools
                    if (result != null && result!.activeWindowTitle.isNotEmpty) ...[
                      _buildSection(
                        title: 'Detected Active Window',
                        icon: Icons.window_outlined,
                        content: Text(
                          result!.activeWindowTitle,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: Colors.blueGrey.shade800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    if (result != null && result!.openWindowTitles.isNotEmpty) ...[
                      _buildSection(
                        title: 'Open Applications on Desktop',
                        icon: Icons.apps_outlined,
                        content: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: result!.openWindowTitles.map((win) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Text(
                                win,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Actions Footer
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (result != null)
                  Expanded(
                    child: Text(
                      'Audited: ${_formatTime(result!.timestamp)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  const Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: isAuditing
                          ? null
                          : () {
                              onReaudit();
                              Navigator.of(context).pop();
                            },
                      icon: isAuditing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.refresh, size: 15),
                      label: Text(isAuditing ? 'Auditing...' : 'Re-audit Now'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black87,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Widget content,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: Colors.grey.shade700),
              const SizedBox(width: 5),
              Text(
                title,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          content,
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}
