import 'dart:async';
import 'dart:io';
import 'dart:ui' show Offset, Size;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

const double _focusBarHeight = 64;
const Duration _sessionDuration = Duration(minutes: 25);
const Color _barColor = Color(0xFFFFB000);
const Color _flashColor = Color(0xFFFF4D4F);

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
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setResizable(false);
    await windowManager.setMaximizable(false);
    await windowManager.setMinimizable(false);

    final display = await ScreenRetriever.instance.getPrimaryDisplay();
    final width = display.size.width;
    final topLeft = display.visiblePosition ?? Offset.zero;

    await windowManager.setSize(Size(width, _focusBarHeight));
    await windowManager.setPosition(topLeft);
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
    text: 'Fix the message timing bug in the CSPE library.',
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

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _flashTimer?.cancel();
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
        _onTimerComplete();
      }

      if (!_isPaused && !_isFlashing) {
        _timerController.text = _formatDuration(_remaining);
      }
    });
  }

  void _onTimerComplete() {
    if (!mounted || _isFlashing) {
      return;
    }

    _flashTimer?.cancel();
    setState(() {
      _isPaused = false;
      _isFlashing = true;
      _flashOn = false;
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
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: _focusBarHeight,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
