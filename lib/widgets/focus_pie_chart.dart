import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Compact animated pie chart / gauge visualizing the Gemma focus match percentage.
class FocusPieChart extends StatelessWidget {
  final double? percentage;
  final bool isEnabled;
  final bool isLoading;
  final String? tooltipReason;
  final VoidCallback? onTap;
  final double size;

  const FocusPieChart({
    super.key,
    required this.percentage,
    required this.isEnabled,
    this.isLoading = false,
    this.tooltipReason,
    this.onTap,
    this.size = 30.0,
  });

  Color _getScoreColor(double score) {
    if (score > 50.0) {
      return const Color(0xFF2E7D32); // Green
    } else if (score >= 20.0) {
      return const Color(0xFFF57F17); // Amber/Yellow
    } else {
      return const Color(0xFFD32F2F); // Red
    }
  }

  String _buildTooltipMessage() {
    if (!isEnabled) {
      return 'Gemma AI Focus Auditor: Disabled (Click icon to enable)';
    }
    if (isLoading) {
      return 'Analyzing screen with Gemma AI...';
    }
    if (percentage == null) {
      return 'Gemma AI: Ready (Click to audit now)';
    }
    final score = percentage!.toStringAsFixed(0);
    final reason = tooltipReason?.isNotEmpty == true ? '\nReason: $tooltipReason' : '';
    return 'Gemma Focus Match: $score%$reason\n(Click to view verdict & details)';
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _buildTooltipMessage(),
      waitDuration: const Duration(milliseconds: 300),
      child: GestureDetector(
        onTap: isEnabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: size,
          height: size,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: isLoading
                ? Center(
                    key: const ValueKey('pie-loading'),
                    child: SizedBox(
                      width: size * 0.75,
                      height: size * 0.75,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.black87),
                      ),
                    ),
                  )
                : !isEnabled
                    ? Container(
                        key: const ValueKey('pie-disabled'),
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.black26,
                            width: 1.5,
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.auto_awesome_outlined,
                            size: size * 0.55,
                            color: Colors.black38,
                          ),
                        ),
                      )
                    : percentage == null
                        ? Container(
                            key: const ValueKey('pie-untested'),
                            width: size,
                            height: size,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.black45,
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                'AI',
                                style: TextStyle(
                                  fontSize: size * 0.35,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          )
                        : TweenAnimationBuilder<double>(
                            key: const ValueKey('pie-active'),
                            tween: Tween<double>(
                              begin: 0.0,
                              end: percentage!.clamp(0.0, 100.0),
                            ),
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOutCubic,
                            builder: (context, animValue, _) {
                              final color = _getScoreColor(animValue);
                              return CustomPaint(
                                size: Size(size, size),
                                painter: _PieChartPainter(
                                  percentage: animValue,
                                  color: color,
                                  backgroundColor: Colors.black12,
                                ),
                                child: Center(
                                  child: Text(
                                    '${animValue.round()}',
                                    style: TextStyle(
                                      fontSize: size * 0.36,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ),
      ),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final double percentage;
  final Color color;
  final Color backgroundColor;

  _PieChartPainter({
    required this.percentage,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    const strokeWidth = 3.5;

    // Background track circle
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius - (strokeWidth / 2), bgPaint);

    // Inner fill circle with low opacity
    final innerFillPaint = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - strokeWidth, innerFillPaint);

    // Active progress arc
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    final sweepAngle = (percentage / 100.0) * 2 * math.pi;
    const startAngle = -math.pi / 2; // Start from 12 o'clock

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - (strokeWidth / 2)),
      startAngle,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) {
    return oldDelegate.percentage != percentage ||
        oldDelegate.color != color ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}
