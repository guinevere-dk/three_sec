
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../constants/clip_policy.dart';
import '../models/vlog_project.dart';
import '../managers/video_manager.dart';

class TrimEditorModal extends StatefulWidget {
  final VlogClip clip;
  final VideoManager videoManager;
  final VideoPlayerController controller;
  final bool onePointFiveSecMode;
  final int? initialWindowStartMs;

  const TrimEditorModal({
    Key? key,
    required this.clip,
    required this.videoManager,
    required this.controller,
    this.onePointFiveSecMode = false,
    this.initialWindowStartMs,
  }) : super(key: key);

  @override
  State<TrimEditorModal> createState() => _TrimEditorModalState();
}

class _TrimEditorModalState extends State<TrimEditorModal> {
  late Timer _timer;
  double _currentMs = 0;
  late double _windowStartMs;
  Timer? _dragSeekDebounceTimer;
  double? _pendingDragSeekMs;
  bool _isLoopSeekInFlight = false;
  bool _isDragSeekInFlight = false;
  bool _isWindowDragging = false;
  double _lastLoopSeekMs = -1;
  double _lastDragSeekMs = -1;
  DateTime? _lastLoopSeekAt;
  DateTime? _lastLoopReentryAt;
  DateTime? _lastDragSeekAt;
  int _loopLogCounter = 0;

  static const double _fixedWindowMs = kTargetClipMs * 1.0;
  static const int _loopTickMs = 80;
  static const int _loopSeekCooldownMs = 140;
  static const int _loopSeekDuplicateWindowMs = 240;
  static const double _loopSeekDuplicateToleranceMs = 16;
  static const int _dragSeekDebounceMs = 64;
  static const int _dragSeekCooldownMs = 120;
  static const int _loopSeekLogSampleEvery = 6;

  @override
  void initState() {
    super.initState();
    _currentMs = widget.controller.value.position.inMilliseconds.toDouble();
    final totalMs = widget.clip.originalDuration.inMilliseconds.toDouble();
    _windowStartMs = _clampWindowStartMs(
      (widget.initialWindowStartMs ?? widget.clip.startTime.inMilliseconds)
          .toDouble(),
      totalMs,
    );
    _timer = Timer.periodic(const Duration(milliseconds: _loopTickMs), (timer) {
      if (mounted && widget.controller.value.isPlaying) {
        setState(() {
          _currentMs = widget.controller.value.position.inMilliseconds.toDouble();
        });

        // Loop Check
        if (widget.onePointFiveSecMode) {
          final startMs = _windowStartMs;
          final endMs = _windowEndMs(totalMs);
          if (_currentMs < startMs || _currentMs >= endMs) {
            _lastLoopReentryAt = DateTime.now();
            unawaited(_issueLoopSeek(startMs, reason: 'window_out'));
          }
        } else if (_currentMs >= widget.clip.endTime.inMilliseconds) {
          widget.controller.pause();
          widget.controller.seekTo(widget.clip.startTime);
        }
      }
    });
  }

  double _clampWindowStartMs(double value, double totalMs) {
    if (totalMs <= 0) return 0;
    final maxStart = (totalMs - _fixedWindowMs).clamp(0.0, totalMs);
    return value.clamp(0.0, maxStart);
  }

  double _windowEndMs(double totalMs) {
    if (totalMs <= 0) return 0;
    return (_windowStartMs + _fixedWindowMs).clamp(0.0, totalMs);
  }

  String _formatDurationWithMillis(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String threeDigits(int n) => n.toString().padLeft(3, '0');
    return '${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}.${threeDigits(d.inMilliseconds.remainder(1000))}';
  }

  @override
  void dispose() {
    _dragSeekDebounceTimer?.cancel();
    _timer.cancel();
    super.dispose();
  }

  void _debugLoopLog(String message) {
    if (!kDebugMode) return;
    debugPrint('[TrimEditorLoop] $message');
  }

  Future<void> _issueLoopSeek(double targetMs, {required String reason}) async {
    if (!widget.onePointFiveSecMode || _isWindowDragging) return;
    if (_isLoopSeekInFlight) return;
    final now = DateTime.now();
    final lastAt = _lastLoopSeekAt;
    if (lastAt != null && now.difference(lastAt).inMilliseconds < _loopSeekCooldownMs) {
      return;
    }
    if ((_lastLoopSeekMs - targetMs).abs() <= _loopSeekDuplicateToleranceMs &&
        lastAt != null &&
        now.difference(lastAt).inMilliseconds < _loopSeekDuplicateWindowMs) {
      return;
    }

    _isLoopSeekInFlight = true;
    _lastLoopSeekAt = now;
    _lastLoopSeekMs = targetMs;
    final requestAt = now;
    final reentryGapMs = _lastLoopReentryAt == null
        ? null
        : now.difference(_lastLoopReentryAt!).inMilliseconds;
    try {
      await widget.controller.seekTo(Duration(milliseconds: targetMs.toInt()));
    } finally {
      _isLoopSeekInFlight = false;
      final latencyMs = DateTime.now().difference(requestAt).inMilliseconds;
      _loopLogCounter += 1;
      if (latencyMs >= 28 || _loopLogCounter % _loopSeekLogSampleEvery == 0) {
        _debugLoopLog(
          'loop seek($reason): target=${targetMs.toInt()}, reentryGap=${reentryGapMs ?? -1}ms, latency=${latencyMs}ms',
        );
      }
    }
  }

  void _scheduleDragSeek(double targetMs) {
    _pendingDragSeekMs = targetMs;
    _dragSeekDebounceTimer?.cancel();
    _dragSeekDebounceTimer = Timer(
      const Duration(milliseconds: _dragSeekDebounceMs),
      _flushDragSeek,
    );
  }

  void _flushDragSeek() {
    final ms = _pendingDragSeekMs;
    if (ms == null) return;
    unawaited(_issueDragSeek(ms));
  }

  Future<void> _issueDragSeek(double targetMs) async {
    if (_isDragSeekInFlight) return;
    final now = DateTime.now();
    if (_lastDragSeekAt != null &&
        now.difference(_lastDragSeekAt!).inMilliseconds < _dragSeekCooldownMs) {
      return;
    }
    if ((_lastDragSeekMs - targetMs).abs() < 8 &&
        _lastDragSeekAt != null &&
        now.difference(_lastDragSeekAt!).inMilliseconds < 220) {
      return;
    }

    _isDragSeekInFlight = true;
    _pendingDragSeekMs = null;
    _lastDragSeekAt = now;
    _lastDragSeekMs = targetMs;
    final requestAt = now;
    try {
      await widget.controller.seekTo(Duration(milliseconds: targetMs.toInt()));
    } finally {
      _isDragSeekInFlight = false;
      if (_pendingDragSeekMs != null) {
        _dragSeekDebounceTimer?.cancel();
        _dragSeekDebounceTimer = Timer(
          const Duration(milliseconds: _dragSeekDebounceMs),
          _flushDragSeek,
        );
      }
      _debugLoopLog(
        'drag seek: target=${targetMs.toInt()}, latency=${DateTime.now().difference(requestAt).inMilliseconds}ms',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.clip.originalDuration.inMilliseconds.toDouble();
    
    return Container(
      height: 300,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
           const Text("Trim Clip", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
           const SizedBox(height: 20),
           Expanded(
             child: LayoutBuilder(
               builder: (context, constraints) {
                 final double width = constraints.maxWidth;
                 if (totalMs <= 0 || width <= 0) return const SizedBox();

                 final double startMs = widget.clip.startTime.inMilliseconds.toDouble();
                 final double endMs = widget.clip.endTime.inMilliseconds.toDouble();
                 final double fixedStartMs = _clampWindowStartMs(_windowStartMs, totalMs);
                 final double fixedEndMs = _windowEndMs(totalMs);
                 
                 final double startPx = (startMs / totalMs) * width;
                 final double endPx = (endMs / totalMs) * width;
                 final double currentPx = (_currentMs / totalMs) * width;
                 
                 return Stack(
                   alignment: Alignment.centerLeft,
                   children: [
                     // 1. Thumbnails Background
                     Positioned.fill(
                       child: TrimTimelineBackground(
                         clip: widget.clip,
                         totalDurationMs: totalMs.toInt(),
                         videoManager: widget.videoManager,
                       ),
                     ),

                     // 2. Dimmed Areas
                     Positioned(
                       left: 0,
                       width: startPx,
                       top: 0,
                       bottom: 0,
                       child: Container(color: Colors.black.withOpacity(0.6)),
                     ),
                     Positioned(
                       left: endPx,
                       width: width - endPx,
                       top: 0,
                       bottom: 0,
                       child: Container(color: Colors.black.withOpacity(0.6)),
                     ),

                     // 3. Selection Border
                     Positioned(
                       left: startPx,
                       width: endPx - startPx,
                       top: 0,
                       bottom: 0,
                       child: Container(
                         decoration: BoxDecoration(
                           border: Border.all(color: const Color(0xFFF2F20D), width: 2),
                           borderRadius: BorderRadius.circular(4),
                         ),
                       ),
                     ),

                     // 4. Left Handle
                      Positioned(
                        left: startPx - 20,
                        top: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          ignoring: widget.onePointFiveSecMode,
                          child: GestureDetector(
                          onHorizontalDragUpdate: (details) {
                             final newPx = (startPx + details.delta.dx).clamp(0.0, endPx - 20);
                             final newMs = (newPx / width) * totalMs;
                             setState(() {
                               widget.clip.startTime = Duration(milliseconds: newMs.toInt());
                             });
                             widget.controller.seekTo(widget.clip.startTime);
                          },
                          child: Container(
                            width: 40,
                            color: Colors.transparent,
                            alignment: Alignment.center,
                            child: Container(
                              width: 16,
                              height: 60,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF2F20D),
                                borderRadius: BorderRadius.horizontal(left: Radius.circular(4)),
                              ),
                              child: const Icon(Icons.chevron_left, color: Colors.black, size: 16),
                            ),
                          ),
                          ),
                        ),
                      ),

                     // 5. Right Handle
                      Positioned(
                        left: endPx - 20,
                        top: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          ignoring: widget.onePointFiveSecMode,
                          child: GestureDetector(
                          onHorizontalDragUpdate: (details) {
                             final newPx = (endPx + details.delta.dx).clamp(startPx + 20, width);
                             final newMs = (newPx / width) * totalMs;
                             setState(() {
                               widget.clip.endTime = Duration(milliseconds: newMs.toInt());
                             });
                              // Optional: preview end
                          },
                          child: Container(
                            width: 40,
                            color: Colors.transparent,
                            alignment: Alignment.center,
                            child: Container(
                              width: 16,
                              height: 60,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF2F20D),
                                borderRadius: BorderRadius.horizontal(right: Radius.circular(4)),
                              ),
                              child: const Icon(Icons.chevron_right, color: Colors.black, size: 16),
                            ),
                          ),
                          ),
                        ),
                      ),

                      if (widget.onePointFiveSecMode)
                        Positioned(
                          left: (fixedStartMs / totalMs) * width,
                          width: ((fixedEndMs - fixedStartMs) / totalMs) * width,
                          top: 0,
                          bottom: 0,
                          child: GestureDetector(
                            onHorizontalDragStart: (_) {
                              _isWindowDragging = true;
                            },
                            onHorizontalDragUpdate: (details) {
                              final currentLeft = (fixedStartMs / totalMs) * width;
                              final fixedWidth = ((fixedEndMs - fixedStartMs) / totalMs) * width;
                              final nextLeft = (currentLeft + details.delta.dx).clamp(
                                0.0,
                                width - fixedWidth,
                              );
                              final nextStart = (nextLeft / width) * totalMs;
                              setState(() {
                                _windowStartMs = _clampWindowStartMs(nextStart, totalMs);
                              });
                              _scheduleDragSeek(_windowStartMs);
                            },
                            onHorizontalDragEnd: (_) {
                              _isWindowDragging = false;
                              _flushDragSeek();
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0xFF4EA5FF),
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(6),
                                color: const Color(0x224EA5FF),
                              ),
                            ),
                          ),
                        ),
                     
                     // 6. Scrubber (White Line)
                     Positioned(
                        left: currentPx - 10,
                        top: 0,
                        bottom: 0,
                        child: GestureDetector(
                          onHorizontalDragUpdate: (details) {
                             final newPx = (currentPx + details.delta.dx).clamp(0.0, width);
                             final newMs = (newPx / width) * totalMs;
                             
                             // Snap to start/end
                             double finalMs = newMs;
                             if ((newMs - startMs).abs() < (totalMs * 0.05)) finalMs = startMs;
                             if ((newMs - endMs).abs() < (totalMs * 0.05)) finalMs = endMs;
                             
                             setState(() {
                               _currentMs = finalMs;
                             });
                             widget.controller.seekTo(Duration(milliseconds: finalMs.toInt()));
                          },
                          child: Container(
                             width: 20,
                             color: Colors.transparent,
                             alignment: Alignment.center,
                             child: Container(
                               width: 2,
                               height: double.infinity,
                               color: Colors.white,
                               child: Align(
                                 alignment: Alignment.topCenter,
                                 child: Container(
                                   width: 6,
                                   height: 6,
                                   decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                 ),
                               ),
                             ),
                          )
                        )
                     )
                   ],
                 );
               }
             ),
           ),
           const SizedBox(height: 20),
           if (widget.onePointFiveSecMode)
             Padding(
               padding: const EdgeInsets.only(bottom: 8),
               child: Text(
                 '${_formatDurationWithMillis(Duration(milliseconds: _windowStartMs.toInt()))} ~ ${_formatDurationWithMillis(Duration(milliseconds: _windowEndMs(totalMs).toInt()))}',
                 style: const TextStyle(
                   color: Colors.white70,
                   fontSize: 12,
                   fontWeight: FontWeight.w600,
                 ),
               ),
             ),
           Row(
             mainAxisAlignment: MainAxisAlignment.end,
             children: [
               TextButton(
                 onPressed: () => Navigator.pop(context),
                 child: const Text("Done", style: TextStyle(color: Colors.blueAccent)),
               )
             ],
           )
        ],
      ),
    );
  }
}

// Isolated widget to handle thumbnail loading statefully
class TrimTimelineBackground extends StatefulWidget {
  final VlogClip clip;
  final int totalDurationMs;
  final VideoManager videoManager;

  const TrimTimelineBackground({
    Key? key, 
    required this.clip, 
    required this.totalDurationMs, 
    required this.videoManager
  }) : super(key: key);

  @override
  State<TrimTimelineBackground> createState() => _TrimTimelineBackgroundState();
}

class _TrimTimelineBackgroundState extends State<TrimTimelineBackground> {
  Future<List<Uint8List>>? _thumbnailsFuture;

  @override
  void initState() {
    super.initState();
    _loadThumbnails();
  }

  @override
  void didUpdateWidget(TrimTimelineBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clip.path != widget.clip.path ||
        oldWidget.totalDurationMs != widget.totalDurationMs) {
      _loadThumbnails();
    }
  }

  void _loadThumbnails() {
    setState(() {
      _thumbnailsFuture = widget.videoManager.getTimelineThumbnails(
        widget.clip.path, 
        widget.totalDurationMs, 
        3
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FutureBuilder<List<Uint8List>>(
          future: _thumbnailsFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Container(
                color: Colors.grey[300], 
                child: const Center(child: Icon(Icons.error, color: Colors.red))
              );
            }
            if (snapshot.hasData && snapshot.data!.isNotEmpty) {
              return Row(
                children: snapshot.data!.map((bytes) {
                  return Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(right: BorderSide(color: Colors.white.withOpacity(0.2), width: 0.5)),
                      ),
                      child: Image.memory(
                        bytes, 
                        fit: BoxFit.cover,
                        height: double.infinity,
                        width: double.infinity,
                      ),
                    ),
                  );
                }).toList(),
              );
            }
            return Row(
              children: List.generate(3, (index) {
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    color: Colors.grey[300],
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: 0.45 + (index * 0.18),
                        child: Container(
                          height: 10,
                          decoration: BoxDecoration(
                            color: Colors.grey[400],
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}
