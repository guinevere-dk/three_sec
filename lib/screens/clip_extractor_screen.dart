import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../constants/clip_policy.dart';
import '../managers/video_manager.dart';
import '../managers/user_status_manager.dart';
import '../models/clip_save_job_state.dart';

class ClipExtractorScreen extends StatefulWidget {
  final File videoFile;
  final String targetAlbum;

  const ClipExtractorScreen({
    super.key,
    required this.videoFile,
    required this.targetAlbum,
  });

  @override
  State<ClipExtractorScreen> createState() => _ClipExtractorScreenState();
}

class _ClipExtractorScreenState extends State<ClipExtractorScreen> {
  static const MethodChannel _platform = MethodChannel('com.dk.three_sec/video_engine');
  static const int _fixedWindowMs = kTargetClipMs;
  static const int _minValidClipBytes = 8 * 1024;
  static const int _minValidClipDurationMs = 400;
  static const int _minEstimatedFrameCount = 6;
  static const double _validationMinFps = 10.0;
  static const bool _allowParallelClipSave = bool.fromEnvironment(
    'clipSaveAllowParallel',
    defaultValue: false,
  );

  late VideoPlayerController _controller;
  VideoManager? _videoManager;
  bool _clipQueueListenerAttached = false;
  VideoManager? _clipQueueListenerManager;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isExporting = false;
  bool _isVideoInitializing = false;
  bool _isDisposing = false;
  bool _isDisposed = false;
  bool _clipQueueCompletionHandled = false;
  final bool _isFixedWindowMode = true;
  int _windowStartMs = 0;
  Timer? _windowSeekDebounceTimer;
  int? _pendingWindowSeekMs;
  bool _isWindowSeekInFlight = false;
  bool _isFreeSeekInFlight = false;
  bool _isWindowDragging = false;
  int _lastWindowSeekMs = -1;
  DateTime? _lastWindowSeekAt;
  int _lastLoopSeekMs = -1;
  DateTime? _lastLoopSeekAt;
  DateTime? _lastLoopReentryAt;
  bool _isLoopSeekInFlight = false;
  static const int _windowSeekDebounceMs = 56;
  static const int _windowSeekCooldownMs = 120;
  static const int _loopSeekCooldownMs = 140;
  static const int _loopSeekDuplicateWindowMs = 240;
  static const int _loopSeekDuplicateToleranceMs = 16;
  static const int _loopSeekLogSampleEvery = 6;
  int _loopSeekLogCounter = 0;
  final List<String> _activeExtractionJobIds = [];
  int? _sourceTotalDurationMs;
  int _extractOpToken = 0;

  // 선택된 구간 리스트 (시작 시간 ms)
  // 종료 시간은 자동으로 start + target clip ms
  final List<int> _selectedSegments = [];
  
  // 썸네일 캐시는 복잡하므로 일단 심플한 타임스탬프 UI로 간다.

  @override
  void initState() {
    super.initState();
    _initVideoPlayer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final manager = Provider.of<VideoManager>(context, listen: false);
    _videoManager = manager;
    _bindClipQueueListener(manager);
  }

  void _bindClipQueueListener(VideoManager manager) {
    if (_clipQueueListenerAttached && identical(_clipQueueListenerManager, manager)) {
      return;
    }
    _unbindClipQueueListener();
    manager.clipSaveQueueStateNotifier.addListener(_onClipQueueStateChanged);
    _clipQueueListenerAttached = true;
    _clipQueueListenerManager = manager;
  }

  void _unbindClipQueueListener() {
    if (!_clipQueueListenerAttached) return;
    _clipQueueListenerManager?.clipSaveQueueStateNotifier.removeListener(
      _onClipQueueStateChanged,
    );
    _clipQueueListenerAttached = false;
    _clipQueueListenerManager = null;
  }

  Future<void> _initVideoPlayer() async {
    if (_isVideoInitializing || _isDisposing || _isDisposed) return;
    _isVideoInitializing = true;

    try {
      _sourceTotalDurationMs = null;
      _controller = VideoPlayerController.file(widget.videoFile);
      await _controller.initialize();
      if (!_mountedAndReady) return;

      final durationMs = _controller.value.duration.inMilliseconds;
      if (durationMs <= 0) {
        if (mounted) {
          setState(() => _isInitialized = false);
        }
        return;
      }

      _sourceTotalDurationMs = durationMs;
      final startMs = _clampWindowStartMs(
        _controller.value.position.inMilliseconds,
        durationMs,
      );

      // 항목 전환 시 루프 관련 상태 누수 방지
      _windowStartMs = 0;
      _lastLoopSeekMs = -1;
      _lastLoopSeekAt = null;
      _isLoopSeekInFlight = false;
      _lastLoopReentryAt = null;
      _loopSeekLogCounter = 0;

      _controller.addListener(_videoListener);

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isPlaying = true;
          _windowStartMs = startMs;
          _isVideoInitializing = false;
        });
        _controller.play();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isInitialized = false);
      }
      debugPrint('[ClipExtractor] video init failed: $e');
    } finally {
      if (mounted) {
        _isVideoInitializing = false;
      }
    }
  }

  bool get _mountedAndReady => mounted && !_isDisposing;

  bool _isExtractOpActive(int token) =>
      !_isDisposing && !_isDisposed && token == _extractOpToken;

  void _videoListener() {
    if (!_mountedAndReady || !_controller.value.isInitialized) return;
    final isPlaying = _controller.value.isPlaying;
    if (!_isVideoInitializing && isPlaying != _isPlaying) {
      if (mounted) {
        setState(() => _isPlaying = isPlaying);
      }
    }
    _enforceFixedWindowLoop();
  }

  @override
  void dispose() {
    _isDisposing = true;
    _extractOpToken += 1;
    _windowSeekDebounceTimer?.cancel();
    _windowSeekDebounceTimer = null;
    _pendingWindowSeekMs = null;
    _unbindClipQueueListener();
    final manager = _videoManager;
    if (manager != null && _activeExtractionJobIds.isNotEmpty) {
      manager.requestCancelClipSaveQueue();
    }
    if (_isInitialized) {
      try {
        _controller.removeListener(_videoListener);
      } catch (_) {}
    }
    try {
      _controller.dispose();
    } catch (_) {}
    _isDisposed = true;
    super.dispose();
  }

  void _onClipQueueStateChanged() {
    if (!_mountedAndReady || _clipQueueCompletionHandled || _activeExtractionJobIds.isEmpty) {
      return;
    }
    final manager = _videoManager;
    if (manager == null) return;

    final state = manager.clipSaveQueueState;
    final trackedJobs = state.queue
        .where((job) => _activeExtractionJobIds.contains(job.id))
        .toList(growable: false);
    if (trackedJobs.isEmpty) return;
    final allDone = trackedJobs.every(_isTerminalStatus);
    if (!allDone) return;

    _clipQueueCompletionHandled = true;
    final successCount = trackedJobs
        .where((job) => job.status == ClipSaveJobStatus.success)
        .length;
    final failedCount = trackedJobs
        .where((job) => job.status == ClipSaveJobStatus.failed)
        .length;
    final skippedCount = trackedJobs
        .where((job) => job.status == ClipSaveJobStatus.skipped)
        .length;
    final canceledCount = trackedJobs
        .where((job) => job.status == ClipSaveJobStatus.canceled)
        .length;

    Fluttertoast.showToast(
      msg:
          '저장 완료: 성공 $successCount · 실패 $failedCount · 건너뜀 $skippedCount · 취소 $canceledCount',
    );

    if (!_mountedAndReady) return;

    if (failedCount == 0 && skippedCount == 0 && canceledCount == 0) {
      Navigator.pop(context, true);
    } else {
      setState(() {});
    }
  }

  Future<bool> _isClipFileValid(File file) async {
    if (!await file.exists()) {
      debugPrint('[ClipExtractor] invalid clip: file missing (${file.path})');
      return false;
    }

    int byteLength;
    try {
      byteLength = await file.length();
    } catch (e) {
      debugPrint('[ClipExtractor] invalid clip: file length read failed (${file.path}) / $e');
      return false;
    }
    if (byteLength < _minValidClipBytes) {
      debugPrint('[ClipExtractor] invalid clip: too small (${file.path}) / $byteLength bytes');
      return false;
    }

    VideoPlayerController? probe;
    try {
      probe = VideoPlayerController.file(file);
      await probe.initialize();
      final value = probe.value;
      final durationMs = value.duration.inMilliseconds;
      final estimatedFrames = (durationMs * _validationMinFps / 1000).floor();
      if (value.hasError) {
        debugPrint(
          '[ClipExtractor] invalid clip: codec/player error (${file.path}) / ${value.errorDescription}',
        );
        return false;
      }
      if (durationMs < _minValidClipDurationMs) {
        debugPrint(
          '[ClipExtractor] invalid clip: too short (${file.path}) / duration=${durationMs}ms',
        );
        return false;
      }
      if (estimatedFrames < _minEstimatedFrameCount) {
        debugPrint(
          '[ClipExtractor] invalid clip: low frame estimate (${file.path}) / frames~$estimatedFrames',
        );
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('[ClipExtractor] invalid clip: probe failed (${file.path}) / $e');
      return false;
    } finally {
      if (probe != null) {
        try {
          await probe.dispose();
        } catch (_) {}
      }
    }
  }

  List<File> _collectNativeResultFiles(dynamic result, Directory dir) {
    final files = <File>[];
    if (result is List) {
      for (final item in result) {
        if (item is String && item.toLowerCase().endsWith('.mp4')) {
          files.add(File(item));
        }
      }
    }

    if (files.isEmpty) {
      files.addAll(
        dir
            .listSync()
            .whereType<File>()
            .where((file) => file.path.toLowerCase().endsWith('.mp4')),
      );
    }

    final dedup = <String, File>{};
    for (final file in files) {
      dedup[file.path] = file;
    }
    return dedup.values.toList(growable: false);
  }

  bool _isTerminalStatus(ClipSaveJob job) {
    return job.status == ClipSaveJobStatus.success ||
        job.status == ClipSaveJobStatus.failed ||
        job.status == ClipSaveJobStatus.skipped ||
        job.status == ClipSaveJobStatus.canceled;
  }

  int _resolveClipSaveConcurrency() {
    return _allowParallelClipSave
        ? VideoManager.clipSaveWorkerDefaultConcurrency
        : VideoManager.clipSaveSerialConcurrency;
  }

  List<ClipSaveJob> _trackedJobs(ClipSaveJobState state) {
    if (_activeExtractionJobIds.isEmpty) return const [];
    return state.queue
        .where((job) => _activeExtractionJobIds.contains(job.id))
        .toList(growable: false);
  }

  void _togglePlayPause() {
    if (!_mountedAndReady ||
        !_controller.value.isInitialized ||
        _isVideoInitializing ||
        _isDisposing) {
      return;
    }

    try {
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
    } catch (e) {
      debugPrint('[ClipExtractor] togglePlayPause failed: $e');
    }

    if (mounted) {
      setState(() {
        _isPlaying = _controller.value.isPlaying;
      });
    }
  }

  void _addCurrentSegment() {
    if (!_mountedAndReady ||
        !_controller.value.isInitialized ||
        _isVideoInitializing ||
        _isDisposing ||
        _isExporting) {
      return;
    }

    final currentMs = _isFixedWindowMode
        ? _windowStartMs
        : _controller.value.position.inMilliseconds;
    final totalMs = _controller.value.duration.inMilliseconds;

    if (totalMs <= 0) return;
     
    // 비디오 끝부분 예외 처리 (타겟 길이 미만 남았을 때)
    // 네이티브 엔진에서 처리하겠지만, UI에서도 시작점은 total - targetClipMs 안쪽이어야 안전
    int startMs = _clampWindowStartMs(currentMs, totalMs);
    if (startMs > totalMs - kTargetClipMs) {
      startMs = totalMs - kTargetClipMs;
      if (startMs < 0) startMs = 0; // 영상 자체가 타겟 길이 미만인 경우
    }

    if (_selectedSegments.contains(startMs)) {
      Fluttertoast.showToast(msg: '이미 추가한 구간입니다');
      return;
    }

    setState(() {
      _selectedSegments.add(startMs);
      // UX: 추가 후 잠시 멈춤? 아니면 계속 재생? -> 계속 재생이 자연스러움
      // 추가되었다는 피드백(햅틱)
      HapticFeedback.mediumImpact();
    });
    
    // 토스트 등으로 알림
    Fluttertoast.showToast(
      msg: "$kTargetClipSecForDisplay초 구간 추가됨 (${_formatDuration(Duration(milliseconds: startMs))})",
      gravity: ToastGravity.CENTER,
    );
  }

  void _removeSegment(int index) {
    setState(() {
      _selectedSegments.removeAt(index);
    });
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
  }

  String _formatDurationWithMillis(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String threeDigits(int n) => n.toString().padLeft(3, '0');
    return '${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}.${threeDigits(d.inMilliseconds.remainder(1000))}';
  }

  int _clampWindowStartMs(int startMs, int totalMs) {
    if (totalMs <= 0) return 0;
    final maxStart = (totalMs - _fixedWindowMs).clamp(0, totalMs);
    return startMs.clamp(0, maxStart);
  }

  int _windowEndMs(int totalMs) {
    if (totalMs <= 0) return 0;
    return (_windowStartMs + _fixedWindowMs).clamp(0, totalMs);
  }

  bool _sourceTotalDurationMsKnown() {
    return _sourceTotalDurationMs != null && _sourceTotalDurationMs! > 0;
  }

  void _scheduleWindowSeek(int targetMs) {
    _pendingWindowSeekMs = targetMs;
    _windowSeekDebounceTimer?.cancel();
    _windowSeekDebounceTimer = Timer(
      const Duration(milliseconds: _windowSeekDebounceMs),
      () {
        _flushWindowSeek();
      },
    );
  }

  void _flushWindowSeek() {
    final ms = _pendingWindowSeekMs;
    if (!_mountedAndReady ||
        !_isFixedWindowMode ||
        !_controller.value.isInitialized ||
        ms == null) {
      return;
    }
    unawaited(_issueWindowSeek(ms, reason: _isWindowDragging ? 'drag' : 'slider'));
  }

  Future<void> _issueWindowSeek(int targetMs, {required String reason}) async {
    if (!_mountedAndReady || !_isFixedWindowMode || !_controller.value.isInitialized) return;
    if (_isWindowSeekInFlight) return;
    final totalMs = _controller.value.duration.inMilliseconds;
    final clampedTargetMs = _clampWindowStartMs(targetMs, totalMs);
    if (totalMs <= 0) return;
    final now = DateTime.now();
    if ((_lastWindowSeekMs - clampedTargetMs).abs() < 8 &&
        _lastWindowSeekAt != null &&
        now.difference(_lastWindowSeekAt!).inMilliseconds < 220) {
      return;
    }
    if (clampedTargetMs == _windowStartMs) {
      return;
    }
    if (_lastWindowSeekAt != null &&
        now.difference(_lastWindowSeekAt!).inMilliseconds < _windowSeekCooldownMs) {
      return;
    }

    _isWindowSeekInFlight = true;
    _pendingWindowSeekMs = null;
    _lastWindowSeekAt = now;
    _lastWindowSeekMs = clampedTargetMs;
    final requestAt = now;

    if (mounted) {
      setState(() {
        _windowStartMs = clampedTargetMs;
      });
    }
    try {
      await _controller.seekTo(Duration(milliseconds: clampedTargetMs));
    } finally {
      _isWindowSeekInFlight = false;
      if (_pendingWindowSeekMs != null) {
        _windowSeekDebounceTimer?.cancel();
        _windowSeekDebounceTimer = Timer(
          const Duration(milliseconds: _windowSeekDebounceMs),
          _flushWindowSeek,
        );
      }
      _debugLoopLog(
        'window seek($reason): target=$clampedTargetMs, latency=${DateTime.now().difference(requestAt).inMilliseconds}ms',
      );
    }
  }

  void _debugLoopLog(String message) {
    if (!kDebugMode) return;
    debugPrint('[ClipExtractorLoop] $message');
  }

  Future<void> _issueFreeSeek(int targetMs, {required String reason}) async {
    if (!_mountedAndReady || _isFixedWindowMode || !_controller.value.isInitialized) return;
    if (_isDisposing || _isVideoInitializing || _isFreeSeekInFlight) return;

    final totalMs = _controller.value.duration.inMilliseconds;
    if (totalMs <= 0) return;

    final clampedTargetMs = targetMs.clamp(0, totalMs).toInt();
    final now = DateTime.now();
    if (_lastWindowSeekAt != null &&
        _lastWindowSeekMs == clampedTargetMs &&
        now.difference(_lastWindowSeekAt!).inMilliseconds < 150) {
      return;
    }

    _isFreeSeekInFlight = true;
    try {
      await _controller.seekTo(Duration(milliseconds: clampedTargetMs));
    } finally {
      _isFreeSeekInFlight = false;
      _lastWindowSeekMs = clampedTargetMs;
      _lastWindowSeekAt = now;
      _debugLoopLog(
        'free seek($reason): target=$clampedTargetMs, latency=${DateTime.now().difference(now).inMilliseconds}ms',
      );
    }
  }

  Future<void> _issueLoopSeek(int targetMs, {required String reason}) async {
    if (!_mountedAndReady || !_controller.value.isInitialized || _isWindowDragging) return;
    final now = DateTime.now();
    final clampedTargetMs = _clampWindowStartMs(targetMs, _controller.value.duration.inMilliseconds);
    if (_isLoopSeekInFlight) {
      _debugLoopLog(
        'loop seek skip($reason): inFlight target=$clampedTargetMs',
      );
      return;
    }
    final lastAt = _lastLoopSeekAt;
    if (lastAt != null && now.difference(lastAt).inMilliseconds < _loopSeekCooldownMs) {
      _debugLoopLog(
        'loop seek skip($reason): cooldown target=$clampedTargetMs, gap=${now.difference(lastAt).inMilliseconds}ms',
      );
      return;
    }
    if ((_lastLoopSeekMs - clampedTargetMs).abs() <= _loopSeekDuplicateToleranceMs &&
        lastAt != null &&
        now.difference(lastAt).inMilliseconds < _loopSeekDuplicateWindowMs) {
      _debugLoopLog(
        'loop seek skip($reason): duplicate target=$clampedTargetMs, last=$_lastLoopSeekMs, gap=${now.difference(lastAt).inMilliseconds}ms',
      );
      return;
    }

    _isLoopSeekInFlight = true;
    _lastLoopSeekAt = now;
    _lastLoopSeekMs = clampedTargetMs;
    final requestAt = now;
    final reentryGapMs = _lastLoopReentryAt == null
        ? null
        : now.difference(_lastLoopReentryAt!).inMilliseconds;
    _debugLoopLog(
      'loop seek issue($reason): target=$clampedTargetMs, reentryGap=${reentryGapMs ?? -1}ms',
    );
    try {
      await _controller.seekTo(Duration(milliseconds: clampedTargetMs));
    } finally {
      _isLoopSeekInFlight = false;
      final latencyMs = DateTime.now().difference(requestAt).inMilliseconds;
      _loopSeekLogCounter += 1;
      if (latencyMs >= 28 || _loopSeekLogCounter % _loopSeekLogSampleEvery == 0) {
        _debugLoopLog(
          'loop seek($reason): target=$clampedTargetMs, reentryGap=${reentryGapMs ?? -1}ms, latency=${latencyMs}ms',
        );
      }
    }
  }

  void _enforceFixedWindowLoop() {
    if (!_isFixedWindowMode || !_controller.value.isInitialized || _isWindowDragging) {
      return;
    }
    final totalMs = _controller.value.duration.inMilliseconds;
    if (totalMs <= 0) return;
    final startMs = _clampWindowStartMs(_windowStartMs, totalMs);
    final endMs = (startMs + _fixedWindowMs).clamp(0, totalMs);
    final currentMs = _controller.value.position.inMilliseconds;
    if (currentMs >= startMs && currentMs < endMs) return;

    _lastLoopReentryAt = DateTime.now();
    unawaited(_issueLoopSeek(startMs, reason: 'window_out'));
  }

  void _updateWindowStartFromSlider(double newValue) {
    if (!_mountedAndReady || !_isFixedWindowMode || !_controller.value.isInitialized) return;
    final totalMs = _controller.value.duration.inMilliseconds;
    final next = _clampWindowStartMs(newValue.toInt(), totalMs);
    if (next == _windowStartMs) return;
    setState(() {
      _windowStartMs = next;
    });
    _scheduleWindowSeek(next);
  }

  Widget _buildFixedWindowOverlay() {
    if (!_isFixedWindowMode || !_controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    final totalMs = _controller.value.duration.inMilliseconds;
    if (totalMs <= 0) return const SizedBox.shrink();

    final start = _clampWindowStartMs(_windowStartMs, totalMs);
    final end = (start + _fixedWindowMs).clamp(0, totalMs);

    return Positioned(
      left: 0,
      right: 0,
      bottom: 18,
      child: IgnorePointer(
        ignoring: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                '${_formatDurationWithMillis(Duration(milliseconds: start))} ~ ${_formatDurationWithMillis(Duration(milliseconds: end))}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final overlayWidth = constraints.maxWidth * 0.78;
                final safeWidth = overlayWidth <= 0 ? 1.0 : overlayWidth;
                final startRatio = (start / totalMs).clamp(0.0, 1.0);
                final windowRatio = (_fixedWindowMs / totalMs).clamp(0.02, 1.0);
                final left = (safeWidth * startRatio).clamp(
                  0.0,
                  safeWidth * (1 - windowRatio),
                );
                final windowWidth = (safeWidth * windowRatio).clamp(14.0, safeWidth);

                return SizedBox(
                  width: safeWidth,
                  height: 20,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      Positioned(
                        left: left,
                        width: windowWidth,
                        top: 0,
                        bottom: 0,
                         child: GestureDetector(
                           onHorizontalDragStart: (_) {
                             _isWindowDragging = true;
                           },
                           onHorizontalDragUpdate: (details) {
                             final nextLeft = (left + details.delta.dx).clamp(
                               0.0,
                               safeWidth - windowWidth,
                             );
                             final nextRatio = nextLeft / safeWidth;
                             final nextStart = (nextRatio * totalMs).round();
                             _updateWindowStartFromSlider(nextStart.toDouble());
                           },
                           onHorizontalDragEnd: (_) {
                             _isWindowDragging = false;
                             _flushWindowSeek();
                           },
                           child: Container(
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.white70),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _extractClips() async {
    if (_selectedSegments.isEmpty) return;
    if (!_mountedAndReady || _isExporting || !_controller.value.isInitialized) return;
    final opToken = ++_extractOpToken;
    final videoManager = _videoManager ?? Provider.of<VideoManager>(context, listen: false);

    final videoFileLength = await () async {
      try {
        return await widget.videoFile.length();
      } catch (_) {
        return 0;
      }
    }();

    final totalMs =
        videoFileLength > 0 ? (_sourceTotalDurationMs ?? _controller.value.duration.inMilliseconds) : 0;
    if (totalMs <= 0) {
      Fluttertoast.showToast(msg: '원본 영상 정보를 읽을 수 없습니다');
      return;
    }

    final normalizedSegments = _selectedSegments
        .where((startMs) => startMs >= 0)
        .map((startMs) => _clampWindowStartMs(startMs, totalMs))
        .toSet()
        .toList()
      ..sort();

    if (normalizedSegments.isEmpty) {
      Fluttertoast.showToast(msg: '유효한 클립 구간이 없습니다');
      return;
    }

    if (!_sourceTotalDurationMsKnown()) {
      Fluttertoast.showToast(msg: '영상 길이 정보가 아직 준비되지 않았습니다');
      return;
    }

    setState(() => _isExporting = true);

    final userStatusManager = UserStatusManager();
    final docDir = await videoManager.getAppDocDir(); // public method 필요하지만, 없으면 standard way 사용
    if (!_mountedAndReady || !_isExtractOpActive(opToken)) return;
    final outputDir = "${docDir.path}/clips"; // 임시 폴더
    
    // 디렉토리 생성 및 정리
    final dir = Directory(outputDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);

    // 세그먼트 데이터 준비
        final segmentsPayload = normalizedSegments
        .map((startMs) {
          final clampedEnd = (startMs + kTargetClipMs).clamp(0, totalMs);
          if (clampedEnd <= startMs) return null;
          return <String, int>{
            'start': startMs,
            'end': clampedEnd,
          };
        })
        .whereType<Map<String, int>>()
        .toList(growable: false);

    if (segmentsPayload.isEmpty) {
      if (mounted) {
        setState(() => _isExporting = false);
      }
      Fluttertoast.showToast(msg: '유효한 클립 구간이 없습니다');
      return;
    }

    try {
      debugPrint('[ClipExtractor] 🎥 클립 추출 시작: ${segmentsPayload.length}개 구간');
      
      final result = await _platform.invokeMethod('extractClips', {
        'inputPath': widget.videoFile.path,
        'outputDir': outputDir,
        'segments': segmentsPayload,
        'quality': '1080p', // 추출은 원본 화질 유지하되 인코딩은 1080p로 통일 (속도 위해)
        'enableNoiseSuppression': false,
        'userTier': userStatusManager.currentTier.toString().split('.').last,
      });
      if (!_mountedAndReady || !_isExtractOpActive(opToken)) return;

      if (result != null) {
        // 결과는 생성된 파일 경로들의 리스트 (JSON String or List)
        // 네이티브 구현상 List<String> 반환 예상됨 (확인 필요) 혹은 성공 메시지일 수 있음.
        // MainActivity.kt의 extractClips를 보면 결과를 알 수 있음.
        // 현재 MainActivity 구현은 result.success("SUCCESS") 또는 경로 리스트일 것임.
        // 일반적인 3S 패턴상 파일들을 특정 폴더에 떨구고 "SUCCESS"만 줄 수도 있음.
        
        // 하지만 videoManager 로직에 태워야 하므로, 생성된 파일들을 찾아서 등록해야 함.
        // 가정: outputDir에 파일들이 생성됨. 이름을 알 수 없으니 폴더 스캔 또는 네이티브가 리턴해주길 기대.
        // 네이티브 코드가 반환값을 명시적으로 안주면 폴더를 스캔해서 최근 생성된 파일을 가져와야 함.
        
        // 여기서는 안전하게 outputDir의 파일들을 가져와서 이동시킴.
        final expectedCount = segmentsPayload.length;
        final clipFiles = _collectNativeResultFiles(result, dir);
        final validClipFiles = <File>[];
        for (final file in clipFiles) {
          if (!_isExtractOpActive(opToken)) return;
          final valid = await _isClipFileValid(file);
          if (valid) {
            validClipFiles.add(file);
          }
        }

        validClipFiles.sort((a, b) {
          final aMs = a.statSync().modified.millisecondsSinceEpoch;
          final bMs = b.statSync().modified.millisecondsSinceEpoch;
          return aMs.compareTo(bMs);
        });

        if (validClipFiles.length < expectedCount) {
          throw StateError('생성된 클립 파일이 부족합니다: ${validClipFiles.length}/$expectedCount');
        }

        final now = DateTime.now();
        final jobs = validClipFiles
            .asMap()
            .entries
            .where((entry) => entry.key < normalizedSegments.length)
            .map(
              (entry) => ClipSaveJob.queued(
                id:
                    'clip_save_${entry.key}_${entry.value.path.hashCode}_${now.microsecondsSinceEpoch}',
                sourcePath: entry.value.path,
                destinationPath: p.join(
                  widget.targetAlbum,
                  p.basename(entry.value.path),
                ),
                startMs: normalizedSegments[entry.key],
                endMs: (normalizedSegments[entry.key] + kTargetClipMs).clamp(
                  0,
                  totalMs,
                ),
                durationMs: kTargetClipMs,
                sourceVideoId: widget.videoFile.path,
                maxRetry: VideoManager.clipSaveMaxRetry,
              ),
            )
            .toList(growable: false);

        if (jobs.isEmpty) {
          throw StateError('클립 작업 생성에 실패했습니다');
        }
        if (!_mountedAndReady || !_isExtractOpActive(opToken)) return;
        _activeExtractionJobIds
          ..clear()
          ..addAll(jobs.map((job) => job.id));
        _clipQueueCompletionHandled = false;
        videoManager.enqueueClipSaveJobs(
          jobs,
          concurrency: _resolveClipSaveConcurrency(),
        );

        // 방금 생성된 파일들만 골라내기 위해 타임스탬프 체크 등을 할 수 있으나, 
        // 일단 outputDir를 전용으로 썼으므로 있는거 다 가져옴.
        
        Fluttertoast.showToast(msg: '${jobs.length}개 클립 저장 큐에 등록됨');
        if (_mountedAndReady && _isExtractOpActive(opToken)) {
          setState(() {});
        }
      } else {
        throw StateError('네이티브 추출 결과가 비어 있습니다');
      }
    } catch (e) {
      debugPrint('[ClipExtractor] ✗ 추출 실패: $e');
      Fluttertoast.showToast(msg: "클립 추출 실패: $e");
    } finally {
      if (_mountedAndReady && _isExtractOpActive(opToken)) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: _isExporting
              ? null
              : () {
            final manager = _videoManager;
            if (manager != null && _activeExtractionJobIds.isNotEmpty) {
              manager.requestCancelClipSaveQueue();
            }
            Navigator.pop(context);
          },
        ),
        title: const Text('원하는 장면 담기', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: _selectedSegments.isEmpty || _isExporting ? null : _extractClips,
            child: Text(
              _isExporting ? "저장 중..." : "완료 (${_selectedSegments.length})",
              style: TextStyle(
                color: _selectedSegments.isEmpty ? Colors.grey : Colors.blueAccent,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 1. 비디오 프리뷰 (중앙)
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(_controller),
                      _buildFixedWindowOverlay(),
                      // 재생 오버레이
                      if (!_isPlaying)
                        Container(
                          color: Colors.black26,
                          child: const Icon(Icons.play_circle_fill, color: Colors.white70, size: 60),
                        ),
                      GestureDetector(
                        onTap: _togglePlayPause,
                        behavior: HitTestBehavior.opaque,
                        child: const SizedBox.expand(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // 2. 컨트롤 컨트롤 (슬라이더 + 시간)
            // 2. 컨트롤 컨트롤 (슬라이더 + 시간)
            ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, VideoPlayerValue value, child) {
                final duration = value.duration.inMilliseconds.toDouble();
                final position = value.position.inMilliseconds.toDouble();
                final totalMs = value.duration.inMilliseconds;
                final startMs = _clampWindowStartMs(_windowStartMs, totalMs);
                final sliderValue = _isFixedWindowMode ? startMs.toDouble() : position;
                final sliderMax = _isFixedWindowMode
                    ? (duration - _fixedWindowMs).clamp(1.0, duration)
                    : duration;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        _formatDuration(value.position),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2.0,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
                            activeTrackColor: Colors.blueAccent,
                            inactiveTrackColor: Colors.grey,
                            thumbColor: Colors.white,
                          ),
                          child: Slider(
                            value: sliderValue.clamp(0.0, sliderMax),
                            min: 0.0,
                            max: sliderMax,
                            onChangeStart: (_) {
                              if (_isFixedWindowMode) {
                                _isWindowDragging = true;
                              }
                            },
                            onChanged: (newValue) {
                              if (_isFixedWindowMode) {
                                _updateWindowStartFromSlider(newValue);
                              } else {
                                unawaited(_issueFreeSeek(newValue.toInt(), reason: 'slider')); 
                              }
                            },
                            onChangeEnd: (_) {
                              if (_isFixedWindowMode) {
                                _isWindowDragging = false;
                                _flushWindowSeek();
                              }
                            },
                          ),
                        ),
                      ),
                      Text(
                        _formatDuration(value.duration),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                );
              },
            ),

            if (_isFixedWindowMode)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${_formatDurationWithMillis(Duration(milliseconds: _windowStartMs))} ~ ${_formatDurationWithMillis(Duration(milliseconds: _windowEndMs(_controller.value.duration.inMilliseconds)))}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            
            const SizedBox(height: 10),
            
            // 3. 메인 버튼 (Add Clip) - 예쁜 아이콘 버튼
            Center(
              child: SizedBox(
                width: 70, 
                height: 70,
                child: FloatingActionButton(
                  onPressed: _addCurrentSegment,
                  backgroundColor: Colors.white,
                  elevation: 4,
                  shape: const CircleBorder(),
                  child: const Icon(Icons.add_a_photo_outlined, color: Colors.black, size: 32),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // 4. 선택된 세그먼트 리스트 (가로 스크롤)
            SizedBox(
              height: 80,
              child: _selectedSegments.isEmpty
                  ? Center(
                      child: Text(
                        "위 버튼을 눌러 $kTargetClipSecForDisplay초 장면을 담아보세요",
                        style: const TextStyle(color: Colors.white38),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: _selectedSegments.length,
                      separatorBuilder: (_, index) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final startTime = Duration(milliseconds: _selectedSegments[index]);
                        return Stack(
                          children: [
                            Container(
                              width: 100,
                              decoration: BoxDecoration(
                                color: Colors.grey[900],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white24),
                              ),
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.movie, color: Colors.white54),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatDuration(startTime),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: GestureDetector(
                                onTap: () => _removeSegment(index),
                                child: const Icon(Icons.cancel, color: Colors.redAccent, size: 20),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
            const SizedBox(height: 20),

            ValueListenableBuilder<ClipSaveJobState>(
              valueListenable:
                  (_videoManager ?? Provider.of<VideoManager>(context, listen: false))
                      .clipSaveQueueStateNotifier,
              builder: (context, queueState, _) {
                final jobs = _trackedJobs(queueState);
                if (jobs.isEmpty) return const SizedBox.shrink();

                final failedOrSkipped = jobs
                    .where(
                      (job) =>
                          job.status == ClipSaveJobStatus.failed ||
                          job.status == ClipSaveJobStatus.skipped ||
                          job.status == ClipSaveJobStatus.canceled,
                    )
                    .toList(growable: false);

                return Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '저장 큐: ${jobs.length}개',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...jobs.take(4).map((job) {
                        final statusText = switch (job.status) {
                          ClipSaveJobStatus.queued => '대기',
                          ClipSaveJobStatus.running => '저장중',
                          ClipSaveJobStatus.retrying => '재시도중 (${job.attempts}/${job.maxRetry})',
                          ClipSaveJobStatus.success => '완료',
                          ClipSaveJobStatus.failed => '실패',
                          ClipSaveJobStatus.skipped => '건너뜀',
                          ClipSaveJobStatus.canceled => '취소',
                        };
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${p.basename(job.sourcePath)} · $statusText',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ),
                              if (job.status == ClipSaveJobStatus.skipped)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    '건너뜀',
                                    style: TextStyle(
                                      color: Colors.orangeAccent,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              if (job.status == ClipSaveJobStatus.failed ||
                                  job.status == ClipSaveJobStatus.skipped ||
                                  job.status == ClipSaveJobStatus.canceled)
                                TextButton(
                                  onPressed: () =>
                                      (_videoManager ??
                                              Provider.of<VideoManager>(
                                                context,
                                                listen: false,
                                              ))
                                          .retryClipSaveJob(job.id),
                                  child: const Text('재시도'),
                                ),
                            ],
                          ),
                        );
                      }),
                      if (failedOrSkipped.isNotEmpty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () =>
                                (_videoManager ??
                                        Provider.of<VideoManager>(
                                          context,
                                          listen: false,
                                        ))
                                    .retryFailedClipSaveJobs(),
                            child: const Text('실패 항목 전체 재시도'),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
