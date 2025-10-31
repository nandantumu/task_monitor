import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

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
    await windowManager.setResizable(false);
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

  Timer? _countdownTimer;
  Timer? _flashTimer;
  Duration _remaining = _sessionDuration;
  bool _isPaused = false;
  bool _isFlashing = false;
  bool _flashOn = false;
  bool _isAlwaysOnTop = true;
  bool _attachTop = true;

  final SystemTray _systemTray = SystemTray();
  final Menu _trayMenu = Menu();
  bool _systemTrayReady = false;

  String? _lastTrayTooltip;
  String? _lastTrayTimerLabel;
  String? _lastTrayFocusLabel;
  String? _lastTrayAttachLabel;

  @override
  void initState() {
    super.initState();
    _focusController.addListener(_handleFocusTextChanged);
    _startCountdown();
    _loadAlwaysOnTopState();
    unawaited(_initializeSystemTray());
    unawaited(_updateWindowPosition());
  }

  @override
  void dispose() {
    _focusController.removeListener(_handleFocusTextChanged);
    _countdownTimer?.cancel();
    _flashTimer?.cancel();
    if (_systemTrayReady) {
      unawaited(_systemTray.destroy());
      _systemTrayReady = false;
    }
    _focusController.dispose();
    _timerController.dispose();
    _timerFocusNode.dispose();
    super.dispose();
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

      unawaited(_updateSystemTrayContent());
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

    unawaited(_updateSystemTrayContent());
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
    unawaited(_updateSystemTrayContent());
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
    unawaited(_updateSystemTrayContent());
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
    unawaited(_updateSystemTrayContent());
  }

  void _handleFocusTextChanged() {
    unawaited(_updateSystemTrayContent());
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

      await _rebuildSystemTrayMenu(
        timerLabel: _buildTrayTimerLabel(),
        focusLabel: _buildTrayFocusLabel(),
        attachLabel: _buildTrayAttachLabel(),
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

      _systemTrayReady = true;
      await _updateWindowPosition();
      await _updateSystemTrayContent();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('System tray init failed: $error');
      }
    }
  }

  Future<void> _updateSystemTrayContent() async {
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

    final timerLabel = _buildTrayTimerLabel();
    final focusLabel = _buildTrayFocusLabel();
    final attachLabel = _buildTrayAttachLabel();

    final labelsChanged = timerLabel != _lastTrayTimerLabel ||
        focusLabel != _lastTrayFocusLabel ||
        attachLabel != _lastTrayAttachLabel;

    if (labelsChanged) {
      await _rebuildSystemTrayMenu(
        timerLabel: timerLabel,
        focusLabel: focusLabel,
        attachLabel: attachLabel,
      );
    }
  }

  Future<void> _rebuildSystemTrayMenu({
    required String timerLabel,
    required String focusLabel,
    required String attachLabel,
  }) async {
    final menuItems = <MenuItemBase>[
      MenuItemLabel(
        label: timerLabel,
        enabled: false,
        name: 'timer',
      ),
      MenuItemLabel(
        label: focusLabel,
        enabled: false,
        name: 'focus',
      ),
      MenuItemLabel(
        label: attachLabel,
        onClicked: (_) => _toggleAttachPosition(),
        name: 'attach-position',
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Show',
        onClicked: (_) async {
          await windowManager.show();
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

    _lastTrayTimerLabel = timerLabel;
    _lastTrayFocusLabel = focusLabel;
    _lastTrayAttachLabel = attachLabel;
  }

  String _buildTrayTimerLabel() => 'Timer: ${_formatDuration(_remaining)}';

  String _buildTrayAttachLabel() =>
      _attachTop ? 'Attach to bottom' : 'Attach to top';

  Future<void> _toggleAttachPosition() async {
    _attachTop = !_attachTop;
    await _updateWindowPosition();
    unawaited(_updateSystemTrayContent());
  }

  Future<void> _updateWindowPosition() async {
    if (!(Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      return;
    }

  final display = await ScreenRetriever.instance.getPrimaryDisplay();
  final offset = display.visiblePosition ?? Offset.zero;
  final width = display.visibleSize?.width ?? display.size.width;
  final visibleHeight = display.visibleSize?.height ?? display.size.height;
  final totalHeight = display.size.height;
  final topReserved = offset.dy;
  final bottomReserved =
    (totalHeight - visibleHeight - topReserved).clamp(0.0, double.infinity);

  final targetTop = _attachTop
    ? topReserved
    : totalHeight - bottomReserved - _focusBarHeight;

  final rect = Rect.fromLTWH(
    offset.dx,
    targetTop,
    width,
    _focusBarHeight,
  );

  await windowManager.setBounds(rect);
  await windowManager.setMinimumSize(Size(width, _focusBarHeight));
  await windowManager.setMaximumSize(Size(width, _focusBarHeight));
  }

  String _buildTrayFocusLabel() {
    final focus = _focusController.text.trim();
    final content = focus.isEmpty ? 'No focus set' : _truncateWithEllipsis(focus, 60);
    return 'Focus: $content';
  }

  String _buildTrayTooltip() {
    final focus = _focusController.text.trim();
    final focusText = focus.isEmpty ? 'No focus set' : focus;
    return 'Focus: $focusText\nTimer: ${_formatDuration(_remaining)}';
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
    unawaited(_updateSystemTrayContent());
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
      backgroundColor: Colors.transparent,
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: _focusBarHeight,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            color: backgroundColor,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _focusController,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      prefixText: 'Current Focus: ',
                      prefixStyle: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: _handleTimerTap,
                  behavior: HitTestBehavior.translucent,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _isPaused
                        ? SizedBox(
                            key: const ValueKey('timer-editor'),
                            width: 110,
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
                                fontSize: 28,
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
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
