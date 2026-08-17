import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

import 'services/focus_verifier_service.dart';
import 'services/screen_capture_service.dart';
import 'widgets/focus_pie_chart.dart';

const double _focusBarHeight = 50;
const Duration _sessionDuration = Duration(minutes: 25);
const Color _barColor = Color(0xFFFFB000);
const Color _flashColor = Color(0xFFFF4D4F);
const String _trayIconAsset = 'icon_design/task_monitor_icon_1024x1024.png';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureDesktopWindow();
  runApp(const TaskMonitorApp());
}

Future<void> _configureDesktopWindow() async {
  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    return;
  }

  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1200, _focusBarHeight),
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setMaximizable(false);
    await windowManager.setMinimizable(false);
    await windowManager.setAlwaysOnTop(true);

    final display = await ScreenRetriever.instance.getPrimaryDisplay();
    final offset = display.visiblePosition ?? Offset.zero;
    final width = display.visibleSize?.width ?? display.size.width;
    final rect = Rect.fromLTWH(
      offset.dx,
      offset.dy,
      width,
      _focusBarHeight,
    );

    await windowManager.setBounds(rect);
    await windowManager.setSize(Size(width, _focusBarHeight));
    await windowManager.setPosition(Offset(offset.dx, offset.dy));
    await windowManager.setMinimumSize(Size(width, _focusBarHeight));
    await windowManager.setMaximumSize(Size(width, _focusBarHeight));
    await windowManager.show();
    await windowManager.focus();
  });
}

class TaskMonitorApp extends StatelessWidget {
  const TaskMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Task Monitor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber),
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
        useMaterial3: true,
        tooltipTheme: TooltipThemeData(
          waitDuration: const Duration(milliseconds: 300),
          showDuration: const Duration(seconds: 3),
          preferBelow: false,
          verticalOffset: 32,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(6),
          ),
          textStyle: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      home: const FocusBar(),
    );
  }
}

class FocusBar extends StatefulWidget {
  const FocusBar({super.key});

  @override
  State<FocusBar> createState() => _FocusBarState();
}

class _FocusBarState extends State<FocusBar> {
  static const _tick = Duration(seconds: 1);
  final TextEditingController _focusController = TextEditingController(
    text: 'What are you focusing on?',
  );
  final TextEditingController _timerController =
      TextEditingController(text: _formatDuration(_sessionDuration));
  final FocusNode _timerFocusNode = FocusNode();

  final FocusVerifierService _focusVerifier = FocusVerifierService();
  Timer? _countdownTimer;
  Timer? _flashTimer;
  Timer? _aiAuditTimer;

  Duration _remaining = _sessionDuration;
  bool _isPaused = false;
  bool _isFlashing = false;
  bool _flashOn = false;
  bool _isAlwaysOnTop = true;
  bool _attachTop = true;

  // Gemma AI verification state
  bool _isAiAuditEnabled = false;
  bool _isAuditing = false;
  double? _focusMatchPercentage;
  String? _focusMatchReason;
  final Duration _aiAuditInterval = const Duration(minutes: 1);

  List<Display> _displays = [];
  int _currentDisplayIndex = 0;

  final SystemTray _systemTray = SystemTray();
  final Menu _trayMenu = Menu();
  bool _systemTrayReady = false;

  String? _lastTrayTooltip;
  String? _lastTrayStatusLabel;
  String? _lastTrayFocusLabel;
  String? _lastTrayAttachLabel;
  String? _lastTrayMonitorLabel;
  String? _lastTrayPlayPauseLabel;

  @override
  void initState() {
    super.initState();
    _focusController.addListener(_handleFocusTextChanged);
    _startCountdown();
    _loadAlwaysOnTopState();
    unawaited(_initializeSystemTray());
    unawaited(_initDisplaysAndPosition());
  }

  @override
  void dispose() {
    _focusController.removeListener(_handleFocusTextChanged);
    _countdownTimer?.cancel();
    _flashTimer?.cancel();
    _aiAuditTimer?.cancel();
    _focusVerifier.dispose();
    if (_systemTrayReady) {
      unawaited(_systemTray.destroy());
      _systemTrayReady = false;
    }
    _focusController.dispose();
    _timerController.dispose();
    _timerFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initDisplaysAndPosition() async {
    if (!(Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      return;
    }
    try {
      final displays = await ScreenRetriever.instance.getAllDisplays();
      final primary = await ScreenRetriever.instance.getPrimaryDisplay();
      if (displays.isNotEmpty && mounted) {
        final primaryIndex = displays.indexWhere((d) =>
            (d.visiblePosition?.dx == primary.visiblePosition?.dx &&
             d.visiblePosition?.dy == primary.visiblePosition?.dy) ||
            (d.size.width == primary.size.width && d.size.height == primary.size.height));
        setState(() {
          _displays = displays;
          _currentDisplayIndex = primaryIndex != -1 ? primaryIndex : 0;
        });
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Error initializing displays: $error');
      }
    }
    await _updateWindowPosition();
  }

  Future<void> _refreshDisplays() async {
    if (!(Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      return;
    }
    try {
      final displays = await ScreenRetriever.instance.getAllDisplays();
      if (displays.isNotEmpty && mounted) {
        setState(() {
          _displays = displays;
          if (_currentDisplayIndex >= _displays.length) {
            _currentDisplayIndex = 0;
          }
        });
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Error refreshing displays: $error');
      }
    }
  }

  Future<void> _switchDisplay([int? targetIndex]) async {
    await _refreshDisplays();
    if (_displays.isEmpty) {
      return;
    }

    setState(() {
      if (targetIndex != null && targetIndex >= 0 && targetIndex < _displays.length) {
        _currentDisplayIndex = targetIndex;
      } else {
        _currentDisplayIndex = (_currentDisplayIndex + 1) % _displays.length;
      }
    });

    await _updateWindowPosition();
    unawaited(_updateSystemTrayState());
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(_tick, (_) {
      if (!mounted) {
        _countdownTimer?.cancel();
        return;
      }

      var finishedTick = false;

      setState(() {
        if (_remaining <= _tick) {
          _remaining = Duration.zero;
          finishedTick = true;
        } else {
          _remaining -= _tick;
        }
      });

      if (finishedTick) {
        _countdownTimer?.cancel();
        unawaited(_onTimerComplete());
      }

      if (!_isPaused && !_isFlashing) {
        _timerController.text = _formatDuration(_remaining);
      }

      // Update hover tooltip with current time without rebuilding the DBus context menu
      unawaited(_updateSystemTrayTooltip());
    });
  }

  Future<void> _onTimerComplete() async {
    if (!mounted || _isFlashing) {
      return;
    }

    _flashTimer?.cancel();
    await windowManager.setAlwaysOnTop(true);
    if (!mounted) {
      return;
    }
    setState(() {
      _isPaused = false;
      _isFlashing = true;
      _flashOn = false;
      _isAlwaysOnTop = true;
    });
    _flashTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) {
        _flashTimer?.cancel();
        return;
      }
      setState(() {
        _flashOn = !_flashOn;
      });
    });

    unawaited(_updateSystemTrayState());
  }

  void _pauseTimer() {
    _countdownTimer?.cancel();
    setState(() {
      _isPaused = true;
    });
    _timerController
      ..text = _formatDuration(_remaining)
      ..selection = TextSelection(baseOffset: 0, extentOffset: _timerController.text.length);
    FocusScope.of(context).requestFocus(_timerFocusNode);
    unawaited(_updateSystemTrayState());
  }

  void _resetTimer() {
    _countdownTimer?.cancel();
    _flashTimer?.cancel();
    setState(() {
      _remaining = _sessionDuration;
      _isPaused = false;
      _isFlashing = false;
      _flashOn = false;
    });
    _timerController.text = _formatDuration(_remaining);
    _timerFocusNode.unfocus();
    _startCountdown();
    unawaited(_updateSystemTrayState());
  }

  void _handleTimerTap() {
    if (_isFlashing || _remaining == Duration.zero) {
      _resetTimer();
      return;
    }

    if (_isPaused) {
      FocusScope.of(context).requestFocus(_timerFocusNode);
    } else {
      _pauseTimer();
    }
  }

  void _handleControlTap() {
    if (_isFlashing || _remaining == Duration.zero) {
      _resetTimer();
    } else if (_isPaused) {
      _applyEditedTime();
    } else {
      _pauseTimer();
    }
  }

  Future<void> _loadAlwaysOnTopState() async {
    final value = await windowManager.isAlwaysOnTop();
    if (!mounted) {
      return;
    }
    setState(() {
      _isAlwaysOnTop = value;
    });
  }

  Future<void> _toggleAlwaysOnTop() async {
    final newValue = !_isAlwaysOnTop;
    await windowManager.setAlwaysOnTop(newValue);
    if (!mounted) {
      return;
    }
    setState(() {
      _isAlwaysOnTop = newValue;
    });
    unawaited(_updateSystemTrayState());
  }

  void _handleFocusTextChanged() {
    unawaited(_updateSystemTrayTooltip());
  }

  Future<void> _initializeSystemTray() async {
    if (!(Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      return;
    }

    try {
      await _systemTray.initSystemTray(
        iconPath: _trayIconAsset,
        toolTip: _buildTrayTooltip(),
      );

      _systemTrayReady = true;

      await _rebuildSystemTrayMenu(
        statusLabel: _buildTrayStatusLabel(),
        focusLabel: _buildTrayFocusLabel(),
        attachLabel: _buildTrayAttachLabel(),
        monitorLabel: _buildTrayMonitorLabel(),
        playPauseLabel: _isPaused ? 'Start timer' : 'Pause timer',
      );

      _systemTray.registerSystemTrayEventHandler((eventName) async {
        if (eventName == kSystemTrayEventClick) {
          final isVisible = await windowManager.isVisible();
          if (!isVisible) {
            await windowManager.show();
          }
          await windowManager.focus();
        } else if (eventName == kSystemTrayEventRightClick) {
          await _systemTray.popUpContextMenu();
        }
      });

      await _updateWindowPosition();
      await _updateSystemTrayState();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('System tray init failed: $error');
      }
    }
  }

  Future<void> _updateSystemTrayTooltip() async {
    if (!_systemTrayReady) {
      return;
    }

    final tooltip = _buildTrayTooltip();
    if (tooltip != _lastTrayTooltip) {
      await _systemTray.setSystemTrayInfo(
        toolTip: tooltip,
        iconPath: _trayIconAsset,
      );
      _lastTrayTooltip = tooltip;
    }
  }

  Future<void> _updateSystemTrayState() async {
    if (!_systemTrayReady) {
      return;
    }

    await _updateSystemTrayTooltip();

    final statusLabel = _buildTrayStatusLabel();
    final focusLabel = _buildTrayFocusLabel();
    final attachLabel = _buildTrayAttachLabel();
    final monitorLabel = _buildTrayMonitorLabel();
    final playPauseLabel = _isFlashing || _remaining == Duration.zero
        ? 'Restart focus session'
        : _isPaused
            ? 'Start timer'
            : 'Pause timer';

    final changed = statusLabel != _lastTrayStatusLabel ||
        focusLabel != _lastTrayFocusLabel ||
        attachLabel != _lastTrayAttachLabel ||
        monitorLabel != _lastTrayMonitorLabel ||
        playPauseLabel != _lastTrayPlayPauseLabel;

    if (changed) {
      await _rebuildSystemTrayMenu(
        statusLabel: statusLabel,
        focusLabel: focusLabel,
        attachLabel: attachLabel,
        monitorLabel: monitorLabel,
        playPauseLabel: playPauseLabel,
      );
    }
  }

  void _toggleAiAudit() {
    setState(() {
      _isAiAuditEnabled = !_isAiAuditEnabled;
      if (!_isAiAuditEnabled) {
        _aiAuditTimer?.cancel();
        _focusMatchPercentage = null;
        _focusMatchReason = null;
        _isAuditing = false;
      }
    });

    if (_isAiAuditEnabled) {
      _startAiAuditTimer();
      unawaited(_runAiAudit(immediate: true));
    }

    unawaited(_updateSystemTrayState());
  }

  void _startAiAuditTimer() {
    _aiAuditTimer?.cancel();
    if (!_isAiAuditEnabled) {
      return;
    }
    _aiAuditTimer = Timer.periodic(_aiAuditInterval, (_) {
      if (!mounted || !_isAiAuditEnabled || _isPaused) {
        return;
      }
      unawaited(_runAiAudit());
    });
  }

  Future<void> _runAiAudit({bool immediate = false}) async {
    if (!mounted || !_isAiAuditEnabled || _isAuditing) {
      return;
    }

    setState(() {
      _isAuditing = true;
    });

    try {
      final capture = await ScreenCaptureService.captureScreen();
      if (capture == null) {
        if (mounted) {
          setState(() {
            _isAuditing = false;
          });
        }
        return;
      }

      final result = await _focusVerifier.verifyFocus(
        focusText: _focusController.text,
        base64Image: capture.base64Image,
      );

      if (!mounted || !_isAiAuditEnabled) {
        return;
      }

      setState(() {
        _focusMatchPercentage = result.matchPercentage;
        _focusMatchReason = result.reason;
        _isAuditing = false;
      });

      // If score is red (< 20%), trigger off-task flashing alert!
      if (result.isLowMatch && !_isFlashing) {
        unawaited(_triggerOffTaskAlert(result.reason));
      }

      unawaited(_updateSystemTrayState());
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAuditing = false;
        });
      }
    }
  }

  Future<void> _triggerOffTaskAlert(String reason) async {
    if (!mounted || _isFlashing) {
      return;
    }

    _flashTimer?.cancel();
    await windowManager.setAlwaysOnTop(true);
    if (!mounted) {
      return;
    }

    setState(() {
      _isFlashing = true;
      _flashOn = true;
    });

    _flashTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) {
        _flashTimer?.cancel();
        return;
      }
      setState(() {
        _flashOn = !_flashOn;
      });
    });

    unawaited(_updateSystemTrayState());
  }

  Future<void> _rebuildSystemTrayMenu({
    required String statusLabel,
    required String focusLabel,
    required String attachLabel,
    required String monitorLabel,
    required String playPauseLabel,
  }) async {
    final menuItems = <MenuItemBase>[
      MenuItemLabel(
        label: statusLabel,
        enabled: false,
        name: 'status',
      ),
      MenuItemLabel(
        label: focusLabel,
        enabled: false,
        name: 'focus',
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: _isAiAuditEnabled
            ? 'Gemma AI Auditor: ON (${_focusMatchPercentage != null ? "${_focusMatchPercentage!.toStringAsFixed(0)}%" : "Auditing"})'
            : 'Gemma AI Auditor: OFF',
        onClicked: (_) => _toggleAiAudit(),
        name: 'toggle-ai',
      ),
      if (_isAiAuditEnabled)
        MenuItemLabel(
          label: 'Audit Screen with Gemma Now',
          onClicked: (_) => _runAiAudit(immediate: true),
          name: 'audit-now',
        ),
      MenuSeparator(),
      MenuItemLabel(
        label: playPauseLabel,
        onClicked: (_) => _handleControlTap(),
        name: 'play-pause',
      ),
      MenuItemLabel(
        label: 'Restart session (25:00)',
        onClicked: (_) => _resetTimer(),
        name: 'reset-timer',
      ),
      MenuItemLabel(
        label: attachLabel,
        onClicked: (_) => _toggleAttachPosition(),
        name: 'attach-position',
      ),
      MenuItemLabel(
        label: monitorLabel,
        onClicked: (_) => _switchDisplay(),
        name: 'switch-monitor',
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Show Bar',
        onClicked: (_) async {
          final isVisible = await windowManager.isVisible();
          if (!isVisible) {
            await windowManager.show();
          }
          await windowManager.focus();
        },
        name: 'show',
      ),
      MenuItemLabel(
        label: 'Quit',
        onClicked: (_) async {
          await windowManager.close();
        },
        name: 'quit',
      ),
    ];

    await _trayMenu.buildFrom(menuItems);
    await _systemTray.setContextMenu(_trayMenu);

    _lastTrayStatusLabel = statusLabel;
    _lastTrayFocusLabel = focusLabel;
    _lastTrayAttachLabel = attachLabel;
    _lastTrayMonitorLabel = monitorLabel;
    _lastTrayPlayPauseLabel = playPauseLabel;
  }

  String _buildTrayStatusLabel() {
    if (_isFlashing || _remaining == Duration.zero) {
      return 'Status: Session Complete!';
    }
    if (_isPaused) {
      return 'Status: Paused (${_formatDuration(_remaining)})';
    }
    return 'Status: Focus Session Running';
  }

  String _buildTrayAttachLabel() =>
      _attachTop ? 'Attach to bottom' : 'Attach to top';

  String _buildTrayMonitorLabel() {
    if (_displays.length > 1) {
      return 'Switch Monitor (${_currentDisplayIndex + 1}/${_displays.length})';
    }
    return 'Switch Monitor';
  }

  Future<void> _toggleAttachPosition() async {
    _attachTop = !_attachTop;
    await _updateWindowPosition();
    unawaited(_updateSystemTrayState());
  }

  Future<void> _updateWindowPosition() async {
    if (!(Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      return;
    }

    try {
      final displays = await ScreenRetriever.instance.getAllDisplays();
      if (displays.isNotEmpty) {
        _displays = displays;
        if (_currentDisplayIndex >= _displays.length) {
          _currentDisplayIndex = 0;
        }
      }
    } catch (_) {}

    final display = _displays.isNotEmpty && _currentDisplayIndex < _displays.length
        ? _displays[_currentDisplayIndex]
        : await ScreenRetriever.instance.getPrimaryDisplay();

    final offset = display.visiblePosition ?? Offset.zero;
    final width = display.visibleSize?.width ?? display.size.width;
    final visibleHeight = display.visibleSize?.height ?? display.size.height;

    final targetTop = _attachTop
        ? offset.dy
        : offset.dy + visibleHeight - _focusBarHeight;

    final rect = Rect.fromLTWH(
      offset.dx,
      targetTop,
      width,
      _focusBarHeight,
    );

    // Apply strict width & height geometry hints
    await windowManager.setMinimumSize(Size(width, _focusBarHeight));
    await windowManager.setMaximumSize(Size(width, _focusBarHeight));

    // Apply explicit bounds, size, and position
    await windowManager.setBounds(rect);
    await windowManager.setSize(Size(width, _focusBarHeight));
    await windowManager.setPosition(Offset(offset.dx, targetTop));
  }

  String _buildTrayFocusLabel() {
    final focus = _focusController.text.trim();
    final content = focus.isEmpty ? 'No focus set' : _truncateWithEllipsis(focus, 60);
    return 'CF: $content';
  }

  String _buildTrayTooltip() {
    final focus = _focusController.text.trim();
    final focusText = focus.isEmpty ? 'No focus set' : focus;
    final aiText = _isAiAuditEnabled
        ? (_focusMatchPercentage != null
            ? '\nGemma Match: ${_focusMatchPercentage!.toStringAsFixed(0)}%'
            : '\nGemma Match: Auditing...')
        : '';
    return 'CF: $focusText\nTimer: ${_formatDuration(_remaining)}$aiText';
  }

  String _truncateWithEllipsis(String value, int maxLength) {
    if (value.length <= maxLength) {
      return value;
    }

    final truncated = value.substring(0, maxLength - 1).trimRight();
    return '$truncated…';
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _applyEditedTime() {
    final parsed = _parseDuration(_timerController.text) ?? _sessionDuration;
    setState(() {
      _remaining = parsed;
      _isPaused = false;
      _isFlashing = false;
      _flashOn = false;
    });
    _timerFocusNode.unfocus();
    _timerController.text = _formatDuration(_remaining);
    _startCountdown();
    unawaited(_updateSystemTrayState());
  }

  Duration? _parseDuration(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final parts = trimmed.split(':');
    int minutes;
    int seconds = 0;

    if (parts.length == 1) {
      minutes = int.tryParse(parts[0]) ?? -1;
    } else if (parts.length == 2) {
      minutes = int.tryParse(parts[0]) ?? -1;
      seconds = int.tryParse(parts[1]) ?? -1;
    } else {
      return null;
    }

    if (minutes < 0 || seconds < 0 || seconds > 59) {
      return null;
    }

    return Duration(minutes: minutes, seconds: seconds);
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = _isFlashing && _flashOn ? _flashColor : _barColor;
    return Scaffold(
      backgroundColor: backgroundColor,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        color: backgroundColor,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _focusController,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  prefixText: 'CF: ',
                  prefixStyle: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FocusPieChart(
              percentage: _focusMatchPercentage,
              isEnabled: _isAiAuditEnabled,
              isLoading: _isAuditing,
              tooltipReason: _focusMatchReason,
              onTap: () => _runAiAudit(immediate: true),
            ),
            IconButton(
              tooltip: _isAiAuditEnabled
                  ? 'Disable Gemma AI focus auditor'
                  : 'Enable Gemma AI focus auditor',
              icon: Icon(
                _isAiAuditEnabled
                    ? Icons.auto_awesome
                    : Icons.auto_awesome_outlined,
              ),
              color: Colors.black,
              onPressed: _toggleAiAudit,
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _handleTimerTap,
              behavior: HitTestBehavior.translucent,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _isPaused
                    ? SizedBox(
                        key: const ValueKey('timer-editor'),
                        width: 90,
                        child: TextField(
                          controller: _timerController,
                          focusNode: _timerFocusNode,
                          textAlign: TextAlign.right,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9:]'),
                            ),
                          ],
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                          ),
                        ),
                      )
                    : Text(
                        key: const ValueKey('timer-display'),
                        _formatDuration(_remaining),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: _isFlashing || _remaining == Duration.zero
                  ? 'Restart focus session'
                  : _isPaused
                      ? 'Start timer'
                      : 'Pause timer',
              icon: Icon(
                _isFlashing || _remaining == Duration.zero
                    ? Icons.refresh
                    : _isPaused
                        ? Icons.play_arrow
                        : Icons.pause,
              ),
              color: Colors.black,
              onPressed: _handleControlTap,
            ),
            IconButton(
              tooltip: _isAlwaysOnTop
                  ? 'Disable always-on-top'
                  : 'Enable always-on-top',
              icon: Icon(
                _isAlwaysOnTop
                    ? Icons.arrow_circle_up
                    : Icons.arrow_circle_down,
              ),
              color: Colors.black,
              onPressed: _toggleAlwaysOnTop,
            ),
            IconButton(
              tooltip: _displays.length > 1
                  ? 'Move to next monitor (${_currentDisplayIndex + 1}/${_displays.length})'
                  : 'Move to next monitor',
              icon: const Icon(Icons.desktop_windows_outlined),
              color: Colors.black,
              onPressed: _switchDisplay,
            ),
          ],
        ),
      ),
    );
  }
}
