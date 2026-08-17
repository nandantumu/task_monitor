import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';
import 'package:task_monitor/services/window_strut_service.dart';

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

    double posX = 0;
    double posY = 0;
    double width = 1920;

    if (Platform.isLinux) {
      final physicalMonitors = await WindowStrutService().getPhysicalMonitors();
      if (physicalMonitors.isNotEmpty) {
        final primary = physicalMonitors.firstWhere((m) => m.isPrimary, orElse: () => physicalMonitors[0]);
        posX = primary.x;
        posY = primary.y;
        width = primary.width;
      }
    }

    if (width == 1920) {
      final display = await ScreenRetriever.instance.getPrimaryDisplay();
      final offset = display.visiblePosition ?? Offset.zero;
      posX = offset.dx;
      posY = offset.dy;
      width = display.size.width;
    }

    final rect = Rect.fromLTWH(
      posX,
      posY,
      width,
      _focusBarHeight,
    );

    await windowManager.setBounds(rect);
    await windowManager.setSize(Size(width, _focusBarHeight));
    await windowManager.setPosition(Offset(posX, posY));
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
  final bool autoStartTimer;
  const FocusBar({super.key, this.autoStartTimer = true});

  @override
  State<FocusBar> createState() => _FocusBarState();
}

class _FocusBarState extends State<FocusBar> with WindowListener {
  static const _tick = Duration(seconds: 1);
  final TextEditingController _focusController = TextEditingController(
    text: 'What are you focusing on?',
  );
  final TextEditingController _timerController =
      TextEditingController(text: _formatDuration(_sessionDuration));
  final FocusNode _timerFocusNode = FocusNode();

  final WindowStrutService _windowStrutService = WindowStrutService();

  Timer? _countdownTimer;
  Timer? _flashTimer;
  Duration _remaining = _sessionDuration;
  bool _isPaused = false;
  bool _isFlashing = false;
  bool _flashOn = false;
  bool _isAlwaysOnTop = true;
  bool _attachTop = true;

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
    windowManager.addListener(this);
    _focusController.addListener(_handleFocusTextChanged);
    if (widget.autoStartTimer) {
      _startCountdown();
    } else {
      _isPaused = true;
    }
    _loadAlwaysOnTopState();
    unawaited(_initializeSystemTray());
    unawaited(_initDisplaysAndPosition());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    if (Platform.isLinux) {
      unawaited(_windowStrutService.clearStrut());
    }
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

  @override
  void onWindowClose() {
    if (Platform.isLinux) {
      unawaited(_windowStrutService.clearStrut());
    }
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
    if (Platform.isLinux) {
      if (newValue) {
        await _applyWindowStrut();
      } else {
        await _windowStrutService.clearStrut();
      }
    }
    unawaited(_updateSystemTrayState());
  }

  PhysicalMonitor? _findMatchingMonitor(Display display, List<PhysicalMonitor> physicalMonitors) {
    // 1. Match by position proximity (within 150px to account for docks/panels)
    final dispX = display.visiblePosition?.dx ?? 0.0;
    final dispY = display.visiblePosition?.dy ?? 0.0;
    for (final mon in physicalMonitors) {
      if ((mon.x - dispX).abs() < 150 && (mon.y - dispY).abs() < 150) {
        return mon;
      }
    }
    // 2. Match by size proximity (within 150px to account for docks/panels)
    for (final mon in physicalMonitors) {
      if ((mon.width - display.size.width).abs() < 150 && (mon.height - display.size.height).abs() < 150) {
        return mon;
      }
    }
    // 3. Fallback by index or primary
    if (_currentDisplayIndex < physicalMonitors.length) {
      return physicalMonitors[_currentDisplayIndex];
    }
    return physicalMonitors.isNotEmpty ? physicalMonitors.first : null;
  }

  Future<void> _applyWindowStrut() async {
    if (!Platform.isLinux || !_isAlwaysOnTop) {
      return;
    }
    try {
      final display = _displays.isNotEmpty && _currentDisplayIndex < _displays.length
          ? _displays[_currentDisplayIndex]
          : await ScreenRetriever.instance.getPrimaryDisplay();

      final physicalMonitors = await _windowStrutService.getPhysicalMonitors();
      final mon = _findMatchingMonitor(display, physicalMonitors);

      final bool isRight = (display.visiblePosition?.dx ?? 0.0) >= 1000;
      final double defaultX = isRight ? 1080.0 : 0.0;
      final double displayX = mon?.x ?? defaultX;
      final double displayY = mon?.y ?? 0.0;
      final double displayWidth = mon?.width ?? display.size.width;
      final double displayHeight = mon?.height ?? display.size.height;

      await _windowStrutService.reserveStrut(
        attachTop: _attachTop,
        displayX: displayX,
        displayY: displayY,
        displayWidth: displayWidth,
        displayHeight: displayHeight,
        barHeight: _focusBarHeight,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error applying window strut: $e');
      }
    }
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

      _systemTray.registerSystemTrayEventHandler((eventName) {
        if (eventName == kSystemTrayEventClick) {
          unawaited(windowManager.show());
          unawaited(windowManager.focus());
        } else if (eventName == kSystemTrayEventRightClick) {
          unawaited(_systemTray.popUpContextMenu());
        }
      });

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
          if (Platform.isLinux) {
            await _windowStrutService.clearStrut();
          }
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

    final physicalMonitors = await _windowStrutService.getPhysicalMonitors();
    final mon = _findMatchingMonitor(display, physicalMonitors);

    final bool isRight = (display.visiblePosition?.dx ?? 0.0) >= 1000;
    final double defaultX = isRight ? 1080.0 : 0.0;
    final double posX = mon?.x ?? defaultX;
    final double posY = mon?.y ?? 0.0;
    final double width = mon?.width ?? display.size.width;
    final double height = mon?.height ?? display.size.height;

    final targetTop = _attachTop
        ? posY
        : posY + height - _focusBarHeight;

    final rect = Rect.fromLTWH(
      posX,
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
    await windowManager.setPosition(Offset(posX, targetTop));

    // Apply workarea reservation strut on Linux
    if (Platform.isLinux) {
      unawaited(_windowStrutService.moveResizeWindow(
        x: posX.round(),
        y: targetTop.round(),
        width: width.round(),
        height: _focusBarHeight.round(),
      ));
      if (_isAlwaysOnTop) {
        unawaited(_applyWindowStrut());
      } else {
        unawaited(_windowStrutService.clearStrut());
      }
    }
  }

  String _buildTrayFocusLabel() {
    final focus = _focusController.text.trim();
    final content = focus.isEmpty ? 'No focus set' : _truncateWithEllipsis(focus, 60);
    return 'CF: $content';
  }

  String _buildTrayTooltip() {
    final focus = _focusController.text.trim();
    final focusText = focus.isEmpty ? 'No focus set' : focus;
    return 'CF: $focusText\nTimer: ${_formatDuration(_remaining)}';
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
            const SizedBox(width: 12),
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
