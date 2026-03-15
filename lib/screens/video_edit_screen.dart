import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../managers/video_manager.dart';
import '../models/edit_command.dart';
import '../managers/user_status_manager.dart';
import '../models/vlog_project.dart';
import '../utils/quality_policy.dart';

// 자막 데이터 모델

class SubtitleModel {
  String text;
  double dx;
  double dy;
  double fontSize;
  Color textColor;
  Color? backgroundColor;
  int? startTimeMs; // 표시 시작 시간(ms)
  int? endTimeMs; // 표시 종료 시간(ms)

  SubtitleModel({
    required this.text,
    required this.dx,
    required this.dy,
    this.fontSize = 18.0,
    this.textColor = Colors.white,
    this.backgroundColor,
    this.startTimeMs,
    this.endTimeMs,
  });

  // Copy helper for Undo/Redo
  SubtitleModel copy() {
    return SubtitleModel(
      text: text,
      dx: dx,
      dy: dy,
      fontSize: fontSize,
      textColor: textColor,
      backgroundColor: backgroundColor,
      startTimeMs: startTimeMs,
      endTimeMs: endTimeMs,
    );
  }
}

class StickerModel {
  String imagePath;
  double dx;
  double dy;
  double scale;
  int? startTimeMs;
  int? endTimeMs;

  StickerModel({
    required this.imagePath,
    required this.dx,
    required this.dy,
    this.scale = 1.0,
    this.startTimeMs,
    this.endTimeMs,
  });

  // Copy helper for Undo/Redo
  StickerModel copy() {
    return StickerModel(
      imagePath: imagePath,
      dx: dx,
      dy: dy,
      scale: scale,
      startTimeMs: startTimeMs,
      endTimeMs: endTimeMs,
    );
  }
}

enum FilterPreset { none, grayscale, warm, cool }

// 편집 상태 스냅샷

class EditorState {
  final List<SubtitleModel> subtitles;
  final List<StickerModel> stickers;
  final FilterPreset filter;
  final double filterOpacity;
  // Audio State
  final String? bgmPath;
  final double videoVolume;
  final double bgmVolume;
  final List<VlogClip> clips;
  final int currentClipIndex;
  final String canvasAspectRatioPreset;
  final String canvasBackgroundMode;
  final Map<String, double> brightnessAdjustments;

  EditorState({
    required this.subtitles,
    required this.stickers,
    required this.filter,
    required this.filterOpacity,
    this.bgmPath,
    required this.videoVolume,
    required this.bgmVolume,
    this.clips = const [],
    this.currentClipIndex = 0,
    this.canvasAspectRatioPreset = 'r9_16',
    this.canvasBackgroundMode = 'crop_fill',
    this.brightnessAdjustments = const <String, double>{},
  });

  EditorState copy() {
    return EditorState(
      subtitles: subtitles.map((e) => e.copy()).toList(),
      stickers: stickers.map((e) => e.copy()).toList(),
      filter: filter,
      filterOpacity: filterOpacity,
      bgmPath: bgmPath,
      videoVolume: videoVolume,
      bgmVolume: bgmVolume,
      clips: clips.map((e) => e.copyWith()).toList(),
      currentClipIndex: currentClipIndex,
      canvasAspectRatioPreset: canvasAspectRatioPreset,
      canvasBackgroundMode: canvasBackgroundMode,
      brightnessAdjustments: Map<String, double>.from(brightnessAdjustments),
    );
  }
}

class _TrimUiState {
  final double startMs;
  final double endMs;
  final double currentMs;
  final double maxMs;

  const _TrimUiState({
    required this.startMs,
    required this.endMs,
    required this.currentMs,
    required this.maxMs,
  });

  _TrimUiState copyWith({
    double? startMs,
    double? endMs,
    double? currentMs,
    double? maxMs,
  }) {
    return _TrimUiState(
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      currentMs: currentMs ?? this.currentMs,
      maxMs: maxMs ?? this.maxMs,
    );
  }
}

enum _TransformInlinePanel { none, angle }

enum _TransformAngleMode { tilt, horizontal, vertical }

enum _TransformQuickAction { none, flip, rotate, angle }

enum _BottomInlinePanel { none, sound, trimSpeedPreset }

enum _TrimTimelineInteraction { none, playhead, startHandle, endHandle }

// 메인 편집 화면

class VideoEditScreen extends StatefulWidget {
  final VlogProject project;

  const VideoEditScreen({super.key, required this.project});

  @override
  State<VideoEditScreen> createState() => _VideoEditScreenState();
}

class _VideoEditScreenState extends State<VideoEditScreen> {
  static const Color _bgColor = Color(0xFFF4F6F8);
  static const Color _primaryColor = Color(0xFF2B8CEE);
  static const Color _textPrimary = Color(0xFF0D141B);
  static const Color _textSecondary = Color(0xFF4C739A);
  static const double _bottomToolbarHeight = 88.0;
  static const double _inlineModePanelHeight = 110.0;
  static const double _inlineModePanelGap = 2.0;
  static const double _transformOverlayBottomInset = 14.0;
  static const double _inlineModePanelSpacing = 1.0;
  static const double _headerRowSpacing = 2.0;
  static const double _inlineModePanelSidePadding = 12.0;
  static const double _inlineModePanelVerticalPadding = 6.0;
  static const double _inlineModeChipRowHeight = 28.0;
  static final BoxDecoration _inlineModePanelDecoration = BoxDecoration(
    color: Color(0x6B000000),
    border: Border.all(color: Color(0x66FFFFFF)),
    borderRadius: BorderRadius.circular(18),
  );

  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isMissingFile = false;
  int? _activeMissingClipIndex;
  Set<int> _missingClipIndexes = <int>{};

  // Editor State
  List<SubtitleModel> _subtitles = [];
  List<StickerModel> _stickers = [];
  FilterPreset _selectedFilter = FilterPreset.none;
  double _filterOpacity = 0.7;

  // Gesture Temp State
  double _tempBaseScale = 1.0;
  double _tempBaseFontSize = 18.0;
  EditorState? _overlayGestureBaseState;
  bool _overlayGestureDirty = false;

  // Trim Gesture State (for Undo/Redo consistency)
  EditorState? _trimGestureBaseState;
  bool _trimGestureDirty = false;
  Timer? _trimSeekDebounceTimer;
  int? _pendingTrimSeekMs;
  int? _lastIssuedTrimSeekMs;
  int? _pendingPlayheadTrimSeekMs;
  bool _trimPlayheadSeekScheduled = false;
  bool _isTrimPlayheadDragging = false;
  bool _isTrimStartHandleDragging = false;
  bool _isTrimEndHandleDragging = false;
  _TrimTimelineInteraction _activeTrimTimelineInteraction =
      _TrimTimelineInteraction.none;
  ValueNotifier<_TrimUiState>? _trimUiStateNotifier;
  bool _trimUiFrameScheduled = false;

  // Transform Slider Session State (for Undo/Redo consistency)
  EditorState? _transformGestureBaseState;
  bool _transformGestureDirty = false;
  bool _isTransformModeActive = false;
  bool _transformDirectManipulationEnabled = false;
  _TransformInlinePanel _transformInlinePanel = _TransformInlinePanel.none;
  _TransformAngleMode _transformAngleMode = _TransformAngleMode.tilt;
  _BottomInlinePanel _bottomInlinePanel = _BottomInlinePanel.none;
  bool _playbackLockedByTransform = false;
  double _transformGestureBaseScale = 1.0;
  bool _transformPreviewFrameScheduled = false;
  EditorState? _transformSessionBaseState;
  Duration? _transformSessionBasePosition;
  bool _isTransformAngleDragging = false;
  bool _showTransformAngleNumericLabel = false;
  bool _isBrightnessMode = false;
  String _selectedBrightnessProperty = 'brightness';
  bool _isBrightnessDragging = false;
  bool _showBrightnessNumericLabel = false;
  bool _brightnessPanelFrameScheduled = false;
  EditorState? _brightnessGestureBaseState;
  bool _brightnessGestureDirty = false;
  String _e3SessionId = '';
  int _e3Seq = 0;
  Map<String, double> _brightnessAdjustments = <String, double>{
    'brightness': 0,
    'exposure': 0,
    'contrast': 0,
    'highlights': 0,
    'shadows': 0,
    'saturation': 0,
    'tint': 0,
    'temperature': 0,
    'sharpness': 0,
    'clarity': 0,
  };

  bool get _isPlaybackLockedForEditing =>
      _playbackLockedByTransform ||
      _isBrightnessMode ||
      _bottomInlinePanel == _BottomInlinePanel.sound;

  // Audio State
  VideoPlayerController? _bgmController;
  String? _bgmPath;
  double _videoVolume = 1.0;
  double _bgmVolume = 0.5;

  // Command Pattern Manager
  final CommandManager _commandManager = CommandManager();

  // Clips Management
  List<VlogClip> _clips = [];
  int _currentClipIndex = 0;

  // State for Snapshot
  EditorState get _currentState => EditorState(
    subtitles: _subtitles.map((e) => e.copy()).toList(),
    stickers: _stickers.map((e) => e.copy()).toList(),
    filter: _selectedFilter,
    filterOpacity: _filterOpacity,
    bgmPath: _bgmPath,
    videoVolume: _videoVolume,
    bgmVolume: _bgmVolume,
    clips: _clips.map((e) => e.copyWith()).toList(),
    currentClipIndex: _currentClipIndex,
    canvasAspectRatioPreset: widget.project.canvasAspectRatioPreset,
    canvasBackgroundMode: widget.project.canvasBackgroundMode,
    brightnessAdjustments: Map<String, double>.from(_brightnessAdjustments),
  );

  // 스티커 에셋 경로
  final List<String> _stickerAssets = [
    'assets/stickers/heart.png',
    'assets/stickers/star.png',
    'assets/stickers/smile.png',
    'assets/stickers/fire.png',
    'assets/stickers/thumbs_up.png',
    'assets/stickers/sparkles.png',
  ];

  final List<Duration> _clipDurations =
      []; // Stores ORIGINAL total duration for slider max
  Duration _totalDuration = Duration.zero; // Sum of trimmed durations
  VideoPlayerController? _nextController; // Add this line
  int _controllerEpoch = 0;
  final Map<String, Future<List<Uint8List>>> _trimTimelineFutureCache = {};

  // Editor State
  bool _isTrimMode = false;
  bool _isDisposed = false;
  late VideoManager
  _videoManager; // Cached reference to avoid context access after dispose
  final ScrollController _timelineScrollController = ScrollController();
  bool _didCheckAccessGate = false;
  Timer? _autosaveDebounceTimer;
  Future<void> _autosaveChain = Future.value();
  bool _isClosingWithSave = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _videoManager = Provider.of<VideoManager>(context, listen: false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runAccessGateThenInit();
    });
  }

  Future<void> _runAccessGateThenInit() async {
    if (_didCheckAccessGate || !mounted || _isDisposed) return;
    _didCheckAccessGate = true;

    final userStatus = UserStatusManager();
    debugPrint(
      '[EditScreen][AccessGate] tier=${userStatus.currentTier} project=${widget.project.id}',
    );

    debugPrint('\n\n🚀🚀🚀 [EditScreen] initState START 🚀🚀🚀\n');
    _initClips()
        .then((_) {
          debugPrint(
            '🚀 [EditScreen] _initClips completed, isDisposed=$_isDisposed, mounted=$mounted',
          );
          if (!mounted || _isDisposed) return;
          _preloadDurations()
              .then((_) {
                debugPrint('🚀 [EditScreen] _preloadDurations completed');
                if (!mounted || _isDisposed) return;
                _preloadTimelineThumbnails();
              })
              .catchError((e, stack) {
                debugPrint(
                  '\n\n⛔⛔⛔ [EditScreen] _preloadDurations CRASHED: $e ⛔⛔⛔\n$stack\n',
                );
              });
        })
        .catchError((e, stack) {
          debugPrint(
            '\n\n⛔⛔⛔ [EditScreen] _initClips CRASHED: $e ⛔⛔⛔\n$stack\n',
          );
        });
  }

  Duration _getTrimmedDuration(VlogClip clip) {
    final start = clip.startTime;
    final end = clip.endTime == Duration.zero
        ? clip.originalDuration
        : clip.endTime;
    if (end <= start) return Duration.zero;
    return end - start;
  }

  Duration _getOriginalDuration(VlogClip clip) {
    if (clip.originalDuration != Duration.zero) return clip.originalDuration;
    if (clip.endTime != Duration.zero) return clip.endTime;
    return Duration.zero;
  }

  void _recalculateTimelineMetrics() {
    _clipDurations.clear();
    _totalDuration = Duration.zero;
    for (final clip in _clips) {
      final original = _getOriginalDuration(clip);
      _clipDurations.add(original);

      var end = clip.endTime == Duration.zero ? original : clip.endTime;
      if (end < Duration.zero) end = Duration.zero;
      if (original > Duration.zero && end > original) end = original;
      clip.endTime = end;
      if (clip.startTime < Duration.zero) clip.startTime = Duration.zero;
      if (clip.startTime > clip.endTime) clip.startTime = Duration.zero;

      _totalDuration += _getTrimmedDuration(clip);
    }
  }

  Future<void> _preloadDurations() async {
    debugPrint('[EditScreen] _preloadDurations START');
    _clipDurations.clear();
    _totalDuration = Duration.zero;

    if (_clips.isEmpty && widget.project.clips.isNotEmpty) {
      _clips = List.from(widget.project.clips);
    }

    for (int i = 0; i < _clips.length; i++) {
      if (_isDisposed) return;

      final clip = _clips[i];

      // Use pre-cached endTime if available (set by createProject or saved project)
      // Only call getVideoDuration as fallback — avoids creating temp controllers
      Duration duration;

      // 1. Ensure originalDuration is set
      if (clip.originalDuration == Duration.zero) {
        try {
          clip.originalDuration = await _videoManager.getVideoDuration(
            clip.path,
          );
        } catch (e) {
          debugPrint('Error fetching duration for ${clip.path}: $e');
          clip.originalDuration = const Duration(seconds: 3); // Fallback
        }
      }

      // 2. Set endTime if missing
      if (clip.endTime != Duration.zero) {
        duration =
            clip.endTime; // Already cached — instant, no controller needed
      } else {
        duration = clip.originalDuration;
        if (_isDisposed) return;
        clip.endTime = duration;
      }

      if (duration != Duration.zero && clip.startTime > duration) {
        clip.startTime = Duration.zero;
      }
      if (duration != Duration.zero && clip.endTime > duration) {
        clip.endTime = duration;
      }
      if (duration != Duration.zero) {
        clip.originalDuration = duration;
      }
      debugPrint(
        '[EditScreen] Clip $i duration: $duration (cached=${clip.endTime != Duration.zero})',
      );
    }
    if (mounted && !_isDisposed) setState(() {});
    _recalculateTimelineMetrics();

    // Auto-save updated endTime values for old projects
    if (!_isDisposed) {
      widget.project.clips = _clips;
      _videoManager.saveProject(widget.project);
    }
    debugPrint('[EditScreen] _preloadDurations DONE, total=$_totalDuration');
  }

  Future<void> _preloadTimelineThumbnails() async {
    if (_isDisposed) return;
    var didUpdateMetadata = false;
    // Use cached _videoManager reference — NO context access!
    for (int i = 0; i < _clips.length; i++) {
      if (_isDisposed) return;
      final clip = _clips[i];
      final duration = _clipDurations.length > i
          ? _clipDurations[i]
          : clip.endTime;

      final durationMs = duration.inMilliseconds;
      if (durationMs <= 0) continue;

      final updated = await _videoManager
          .ensureTimelineThumbnailMetadataForClip(
            clip,
            durationMs: durationMs,
            count: VideoManager.trimTimelineThumbCount,
          );
      if (updated) didUpdateMetadata = true;
    }

    if (didUpdateMetadata && mounted && !_isDisposed) {
      widget.project.clips = _clips;
      await _videoManager.saveProject(widget.project);
    }
    debugPrint('[EditScreen] _preloadTimelineThumbnails DONE');
  }

  Future<void> _preloadNextClip() async {
    if (_isDisposed) return;
    final nextIndex = _findNextExistingClipIndex(_currentClipIndex + 1);
    if (nextIndex == null) {
      if (_nextController != null) {
        await _disposeControllerDeferred(_nextController);
        _nextController = null;
      }
      return;
    }
    if (nextIndex >= _clips.length) return;

    final nextClip = _clips[nextIndex];
    final file = File(nextClip.path);
    if (!await file.exists()) return;
    if (_isDisposed) return; // Check after await

    // Dispose old next controller if it exists and points to a different file
    if (_nextController != null &&
        _nextController!.dataSource != 'file://${file.path}') {
      await _nextController!.dispose();
      _nextController = null;
    }
    if (_isDisposed) return; // Check after await

    if (_nextController == null) {
      _nextController = VideoPlayerController.file(file);
      await _nextController!.initialize();
      if (_isDisposed) {
        // Widget disposed during initialization — clean up immediately
        _nextController?.dispose();
        _nextController = null;
        return;
      }
      await _nextController!.seekTo(nextClip.startTime);
    }
  }

  int? _findNextExistingClipIndex(int startIndex) {
    for (int i = startIndex; i < _clips.length; i++) {
      if (File(_clips[i].path).existsSync()) return i;
    }
    return null;
  }

  int? _findPreviousExistingClipIndex(int startIndex) {
    for (int i = startIndex; i >= 0; i--) {
      if (File(_clips[i].path).existsSync()) return i;
    }
    return null;
  }

  int? _missingIndexForUi() {
    debugPrint(
      '[EditScreen][Diag][Missing][ui_pick][start] '
      'active=$_activeMissingClipIndex current=$_currentClipIndex '
      'missing=${_missingClipIndexes.toList()}',
    );
    final active = _activeMissingClipIndex;
    if (active != null && active >= 0 && active < _clips.length) {
      debugPrint('[EditScreen][Diag][Missing][ui_pick][active] picked=$active');
      return active;
    }
    if (_currentClipIndex >= 0 &&
        _currentClipIndex < _clips.length &&
        _missingClipIndexes.contains(_currentClipIndex)) {
      debugPrint(
        '[EditScreen][Diag][Missing][ui_pick][current] picked=$_currentClipIndex',
      );
      return _currentClipIndex;
    }
    if (_missingClipIndexes.isEmpty) return null;
    final first = _missingClipIndexes.first;
    if (first >= 0 && first < _clips.length) {
      debugPrint('[EditScreen][Diag][Missing][ui_pick][first] picked=$first');
      return first;
    }
    debugPrint('[EditScreen][Diag][Missing][ui_pick][none] picked=null');
    return null;
  }

  Future<void> _removeProblemClip(int index) async {
    if (index < 0 || index >= _clips.length) return;

    debugPrint(
      '[EditScreen][Diag][Missing][remove][start] '
      'index=$index current=$_currentClipIndex '
      'path=${_clips[index].path} missingBefore=${_missingClipIndexes.toList()}',
    );

    final removingCurrent = index == _currentClipIndex;
    if (removingCurrent) {
      final prev = _controller;
      if (prev != null) {
        prev.removeListener(_videoListener);
        _controller = null;
        await _disposeControllerDeferred(prev);
      }
    }

    setState(() {
      _clips.removeAt(index);
      _missingClipIndexes = _missingClipIndexes
          .where((i) => i != index)
          .map((i) => i > index ? i - 1 : i)
          .toSet();

      final active = _activeMissingClipIndex;
      if (active == index) {
        _activeMissingClipIndex = null;
      } else if (active != null && active > index) {
        _activeMissingClipIndex = active - 1;
      }

      if (_clips.isEmpty) {
        _currentClipIndex = 0;
        _isInitialized = false;
        _isPlaying = false;
        _isMissingFile = false;
      } else {
        if (_currentClipIndex > index) {
          _currentClipIndex -= 1;
        } else if (_currentClipIndex >= _clips.length) {
          _currentClipIndex = _clips.length - 1;
        }
      }

      _recalculateTimelineMetrics();
    });

    debugPrint(
      '[EditScreen][Diag][Missing][remove][done] '
      'index=$index current=$_currentClipIndex '
      'missingAfter=${_missingClipIndexes.toList()} clipCount=${_clips.length}',
    );

    _scheduleAutosave(reason: 'remove_problem_clip');

    if (_clips.isNotEmpty && (removingCurrent || _isMissingFile)) {
      await _loadClip(_currentClipIndex, autoPlay: false);
    }
  }

  Future<void> _confirmAndRemoveClip(int index) async {
    if (index < 0 || index >= _clips.length) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('클립 삭제'),
          content: Text('#${index + 1}번 Clip. 삭제하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );

    if (ok == true) {
      await _removeProblemClip(index);
    }
  }

  Future<void> _disposeControllerDeferred(
    VideoPlayerController? controller,
  ) async {
    if (controller == null) return;
    try {
      await controller.pause();
    } catch (_) {}
    try {
      await controller.dispose();
    } catch (e) {
      debugPrint('[EditScreen] controller dispose ignored: $e');
    }
  }

  void _videoListener() {
    if (_isDisposed || !mounted || _controller == null || !_isInitialized) {
      return;
    }

    // Safe access: check native player is still alive
    try {
      if (!_controller!.value.isInitialized) return;
    } catch (e) {
      debugPrint('\n\n⛔⛔⛔ [LISTENER] Controller access FAILED: $e ⛔⛔⛔\n');
      return;
    }

    // Sync BGM
    final isPlaying = _controller!.value.isPlaying;
    if (isPlaying != _isPlaying) {
      if (mounted && !_isDisposed) setState(() => _isPlaying = isPlaying);
      if (_bgmController != null) {
        try {
          if (isPlaying) {
            _bgmController!.play();
          } else {
            _bgmController!.pause();
          }
        } catch (e) {
          debugPrint('\n\n⛔⛔⛔ [LISTENER] BGM control FAILED: $e ⛔⛔⛔\n');
        }
      }
    }

    // Trim Constraint
    final pos = _controller!.value.position;
    if (_currentClipIndex < _clips.length) {
      final clip = _clips[_currentClipIndex];

      if (_playbackLockedByTransform && _isPlaying) {
        _pausePlaybackForEditingMode();
        _controller!.seekTo(clip.startTime);
        return;
      }

      if (_isSoundOrBrightnessActive && pos >= clip.endTime) {
        if (_isPlaying) {
          _pausePlaybackForEditingMode();
          _controller!.seekTo(clip.startTime);
          if (mounted && !_isDisposed) {
            setState(() {
              _isPlaying = false;
            });
          }
        }
        return;
      }

      // 1. Trim Mode: Loop or Pause logic
      if (_isTrimMode) {
        _requestTrimUiRebuild();
        if (pos >= clip.endTime) {
          _controller!.pause();
          _controller!.seekTo(clip.startTime);
          if (mounted && !_isDisposed) {
            setState(() {
              _isPlaying = false;
            });
          }
        }
        return;
      }

      // 2. Normal Mode: Gapless playback with controller swap
      if (pos >= clip.endTime) {
        if (_currentClipIndex < _clips.length - 1) {
          if (_nextController != null && _nextController!.value.isInitialized) {
            debugPrint(
              '\n\n✅✅✅ [SWAP] Controller swap START: clip $_currentClipIndex -> ${_currentClipIndex + 1} ✅✅✅\n',
            );

            // 1. Save old, assign new
            final oldController = _controller;
            _controller = _nextController;
            _nextController = null;

            // 2. Detach old listener now, dispose old after next frame
            oldController?.removeListener(_videoListener);

            // 3. Set up new controller
            _currentClipIndex++;
            _controller!.addListener(_videoListener);
            _controller!.play();

            // 4. Trigger rebuild LAST (old is already gone)
            if (mounted && !_isDisposed) setState(() {});
            debugPrint(
              '✅✅✅ [SWAP] setState called, rebuilding with new controller ✅✅✅\n',
            );

            // 4-1. Dispose previous controller after UI switched to new one
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _disposeControllerDeferred(oldController);
            });
            debugPrint('✅✅✅ [SWAP] Old controller dispose scheduled ✅✅✅');

            // 5. Preload next
            _preloadNextClip();
          } else {
            debugPrint(
              '\n\n⚠️⚠️⚠️ [FALLBACK] No nextController, using _loadClip ⚠️⚠️⚠️\n',
            );
            // Fallback: nullify controller to prevent stale access
            _controller?.removeListener(_videoListener);
            _controller = null;
            if (mounted && !_isDisposed) {
              setState(() {
                _isInitialized = false;
              });
            }
            _loadClip(_currentClipIndex + 1);
          }
        } else {
          // Stop at last clip
          _controller!.pause();
          _controller!.seekTo(clip.startTime);
          if (mounted && !_isDisposed) {
            setState(() {
              _isPlaying = false;
            });
          }
        }
      }
    }
  }

  Future<void> _initClips() async {
    debugPrint('[EditScreen] _initClips START');
    if (_clips.isEmpty && widget.project.clips.isNotEmpty) {
      _clips = List.from(widget.project.clips);
    }
    if (_clips.isNotEmpty) {
      await _loadClip(0);
    }
    debugPrint('[EditScreen] _initClips DONE');
  }

  Future<void> _loadClip(int index, {bool autoPlay = true}) async {
    debugPrint('[EditScreen] _loadClip($index) START');
    if (_isDisposed || index < 0 || index >= _clips.length) return;
    final loadEpoch = ++_controllerEpoch;

    // Detach current controller from UI first, then dispose.
    final previousController = _controller;
    if (previousController != null) {
      previousController.removeListener(_videoListener);
      _controller = null;
      if (mounted && !_isDisposed) {
        setState(() {
          _isInitialized = false;
          _isPlaying = false;
        });
      } else {
        _isInitialized = false;
        _isPlaying = false;
      }

      // Give one frame so VideoPlayer widget detaches before native dispose.
      await Future<void>.delayed(Duration.zero);
      await _disposeControllerDeferred(previousController);
      if (_isDisposed || loadEpoch != _controllerEpoch) return;
    }

    if (_isDisposed) return;

    final clip = _clips[index];
    final file = File(clip.path);
    debugPrint(
      '[EditScreen][Diag][Missing][load] index=$index '
      'path=${clip.path} missingNow=${_missingClipIndexes.toList()}',
    );

    if (!await file.exists()) {
      _missingClipIndexes.add(index);

      final nextPlayable = _findNextExistingClipIndex(index + 1);
      final prevPlayable = _findPreviousExistingClipIndex(index - 1);
      debugPrint(
        '[EditScreen][Diag][Missing][not_found] '
        'index=$index path=${clip.path} '
        'nextPlayable=$nextPlayable prevPlayable=$prevPlayable '
        'missingNow=${_missingClipIndexes.toList()}',
      );
      if (nextPlayable != null) {
        if (mounted && !_isDisposed) {
          setState(() {
            _isMissingFile = false;
            _activeMissingClipIndex = index;
          });
        }
        await _loadClip(nextPlayable, autoPlay: autoPlay);
        return;
      }

      if (prevPlayable != null) {
        if (mounted && !_isDisposed) {
          setState(() {
            _isMissingFile = false;
            _activeMissingClipIndex = index;
          });
        }
        await _loadClip(prevPlayable, autoPlay: false);
        return;
      }

      if (mounted && !_isDisposed) {
        setState(() {
          _isMissingFile = true;
          _activeMissingClipIndex = index;
          _isInitialized = false;
          _isPlaying = false;
        });
      }
      return;
    }
    if (_isDisposed) return;

    _missingClipIndexes.remove(index);

    // Reuse _nextController if it matches the requested file
    if (_nextController != null &&
        _nextController!.dataSource == 'file://${file.path}') {
      _controller = _nextController;
      _nextController = null;
    } else {
      final nextController = VideoPlayerController.file(file);
      await nextController.initialize();
      if (_isDisposed || loadEpoch != _controllerEpoch) {
        await _disposeControllerDeferred(nextController);
        return;
      }
      _controller = nextController;
    }

    _controller!.addListener(_videoListener);

    if (mounted && !_isDisposed) {
      setState(() {
        _currentClipIndex = index;
        _isInitialized = true;
        _isPlaying = autoPlay;
        _isMissingFile = false;
        _activeMissingClipIndex = null;
      });
    }

    if (_controller == null || _isDisposed || loadEpoch != _controllerEpoch) {
      return;
    }
    await _controller!.seekTo(clip.startTime);
    final clipSpeed = clip.playbackSpeed.clamp(0.25, 3.0);
    await _controller!.setPlaybackSpeed(clipSpeed);
    await _bgmController?.setPlaybackSpeed(clipSpeed);
    if (_controller == null || _isDisposed || loadEpoch != _controllerEpoch) {
      return;
    }
    if (autoPlay) {
      await _controller!.play();
    }

    _preloadNextClip();
    debugPrint('[EditScreen] _loadClip($index) DONE');
  }

  double _calculateGlobalPosition() {
    if (_controller == null ||
        !_isInitialized ||
        _currentClipIndex >= _clips.length) {
      return 0.0;
    }

    double globalPos = 0.0;
    for (int i = 0; i < _currentClipIndex; i++) {
      final c = _clips[i];
      globalPos += (c.endTime - c.startTime).inMilliseconds;
    }

    final currentClip = _clips[_currentClipIndex];
    // Current position within the trim range (pos - startTime)
    final currentRelPos = _controller!.value.position - currentClip.startTime;
    // ensure it's not negative if seek happens incorrectly, and clamp to duration
    final duration =
        (currentClip.endTime - currentClip.startTime).inMilliseconds;

    globalPos += currentRelPos.inMilliseconds.clamp(0, duration);

    return globalPos;
  }

  bool get _isSoundOrBrightnessActive =>
      _isBrightnessMode || _bottomInlinePanel == _BottomInlinePanel.sound;

  double _getClipGlobalStartMs(int clipIndex) {
    if (clipIndex <= 0) return 0.0;
    double accumulated = 0.0;
    final safeIndex = clipIndex.clamp(0, _clips.length);
    for (int i = 0; i < safeIndex; i++) {
      accumulated += _getTrimmedDuration(_clips[i]).inMilliseconds.toDouble();
    }
    return accumulated;
  }

  void _seekToGlobalPosition(double value) {
    if (_controller == null || _isDisposed || !_isInitialized) return;
    if (_currentClipIndex >= _clips.length) return;

    final totalMs = _totalDuration.inMilliseconds.toDouble();
    final clampedValue = value.clamp(0.0, totalMs);

    if (_isSoundOrBrightnessActive) {
      final clip = _clips[_currentClipIndex];
      final clipDuration = _getTrimmedDuration(clip).inMilliseconds.toDouble();
      if (clipDuration <= 0.0) {
        _controller!.seekTo(clip.startTime);
        return;
      }

      final clipStartMs = _getClipGlobalStartMs(_currentClipIndex);
      final localGlobalMs = clampedValue.clamp(
        clipStartMs,
        clipStartMs + clipDuration,
      );
      final localMs = (localGlobalMs - clipStartMs).clamp(0.0, clipDuration);
      final seekPos = clip.startTime + Duration(milliseconds: localMs.toInt());
      _controller!.seekTo(seekPos);
      return;
    }

    double accumulated = 0.0;
    for (int i = 0; i < _clips.length; i++) {
      final c = _clips[i];
      final duration = _getTrimmedDuration(c).inMilliseconds.toDouble();
      final seekAtEnd = accumulated + duration;
      if (clampedValue <= seekAtEnd) {
        final localMs = (clampedValue - accumulated).clamp(0.0, duration);
        final seekPos = c.startTime + Duration(milliseconds: localMs.toInt());
        if (i != _currentClipIndex) {
          _loadClip(i, autoPlay: _isPlaying).then((_) {
            if (_controller != null) _controller!.seekTo(seekPos);
          });
        } else {
          _controller!.seekTo(seekPos);
        }
        return;
      }
      accumulated += duration;
    }
  }

  Future<void> _initBgmController(String path) async {
    final file = File(path);
    if (!await file.exists()) return;

    final prevController = _bgmController;
    _bgmController = VideoPlayerController.file(file);
    await _bgmController!.initialize();
    await _bgmController!.setVolume(_bgmVolume);
    await _bgmController!.setLooping(true); // Always loop BGM as requested

    if (_isPlaying) {
      _bgmController!.play();
    }

    // Sync position with video?
    // _bgmController!.seekTo(_controller!.value.position);

    prevController?.dispose();
    setState(() {});
  }

  void _updateVolumes() {
    _controller?.setVolume(_videoVolume);
    _bgmController?.setVolume(_bgmVolume);
  }

  void _syncEditorStateToProject() {
    widget.project.clips = _clips.map((clip) => clip.copyWith()).toList();
    widget.project.bgmPath = _bgmPath;
    widget.project.bgmVolume = _bgmVolume;
    widget.project.canvasAspectRatioPreset =
        _currentState.canvasAspectRatioPreset;
    widget.project.canvasBackgroundMode = _currentState.canvasBackgroundMode;
  }

  double _canvasAspectRatioForPreset(String preset) {
    switch (preset) {
      case 'r1_1':
        return 1.0;
      case 'r16_9':
        return 16 / 9;
      case 'r9_16':
      default:
        return 9 / 16;
    }
  }

  String _canvasAspectLabel(String preset) {
    switch (preset) {
      case 'r1_1':
        return '1:1';
      case 'r16_9':
        return '16:9';
      case 'r9_16':
      default:
        return '9:16';
    }
  }

  VlogClip? _getCurrentClipForTransform() {
    if (_currentClipIndex < 0 || _currentClipIndex >= _clips.length) {
      return null;
    }
    return _clips[_currentClipIndex];
  }

  Future<void> _persistProjectAutosave({required String reason}) async {
    _syncEditorStateToProject();
    await _videoManager.saveProject(widget.project);
    debugPrint('[EditScreen][Autosave] saved: reason=$reason');
  }

  Future<void> _enqueueAutosave({required String reason}) {
    _autosaveChain = _autosaveChain
        .then((_) => _persistProjectAutosave(reason: reason))
        .catchError((Object e, StackTrace st) {
          debugPrint('[EditScreen][Autosave] failed: reason=$reason, error=$e');
        });
    return _autosaveChain;
  }

  void _scheduleAutosave({
    String reason = 'state_change',
    Duration delay = const Duration(milliseconds: 700),
  }) {
    if (_isDisposed) return;
    _autosaveDebounceTimer?.cancel();
    _autosaveDebounceTimer = Timer(delay, () {
      unawaited(_enqueueAutosave(reason: reason));
    });
  }

  Future<void> _flushAutosave({required String reason}) async {
    _autosaveDebounceTimer?.cancel();
    _autosaveDebounceTimer = null;
    await _enqueueAutosave(reason: reason);
  }

  Future<void> _handleClosePressed() async {
    if (_isClosingWithSave) return;
    setState(() {
      _isClosingWithSave = true;
    });
    try {
      await _flushAutosave(reason: 'close_button');
      await _videoManager.saveProject(widget.project);
      if (!mounted) return;
      Navigator.pop(context, true);
    } finally {
      if (mounted) {
        setState(() {
          _isClosingWithSave = false;
        });
      }
    }
  }

  @override
  void dispose() {
    debugPrint('[EditScreen] dispose START');
    _autosaveDebounceTimer?.cancel();
    _autosaveDebounceTimer = null;
    unawaited(_enqueueAutosave(reason: 'dispose'));
    _isDisposed = true;

    // 1. Stop playback first to prevent native codec conflicts
    _controller?.removeListener(_videoListener);
    try {
      _controller?.pause();
    } catch (_) {}
    try {
      _bgmController?.pause();
    } catch (_) {}
    try {
      _nextController?.pause();
    } catch (_) {}

    // 2. Dispose all controllers
    _controller?.dispose();
    _controller = null;
    _bgmController?.dispose();
    _bgmController = null;
    _nextController?.dispose();
    _nextController = null;
    _trimSeekDebounceTimer?.cancel();
    _trimSeekDebounceTimer = null;
    _trimUiStateNotifier?.dispose();
    _trimUiStateNotifier = null;
    _pendingTrimSeekMs = null;
    _trimTimelineFutureCache.clear();
    _timelineScrollController.dispose();

    debugPrint('[EditScreen] dispose DONE');
    super.dispose();
  }

  // Undo/Redo 상태 복원

  void _applyEditorState(EditorState state, {bool keepPlayback = false}) {
    final wasPlaying = keepPlayback ? _isPlaying : false;
    final previousIndex = _currentClipIndex.clamp(
      0,
      (_clips.isEmpty ? 0 : _clips.length - 1),
    );
    final previousPath = previousIndex >= 0 && previousIndex < _clips.length
        ? _clips[previousIndex].path
        : null;

    final nextIndex = state.currentClipIndex.clamp(
      0,
      (state.clips.isEmpty ? 0 : state.clips.length - 1),
    );
    final normalizedNextIndex = state.clips.isEmpty ? 0 : nextIndex;
    setState(() {
      _subtitles = state.subtitles.map((e) => e.copy()).toList();
      _stickers = state.stickers.map((e) => e.copy()).toList();
      _selectedFilter = state.filter;
      _filterOpacity = state.filterOpacity;
      _brightnessAdjustments = Map<String, double>.from(
        state.brightnessAdjustments.isEmpty
            ? _brightnessAdjustments
            : state.brightnessAdjustments,
      );
      _bgmPath = state.bgmPath;
      _videoVolume = state.videoVolume;
      _bgmVolume = state.bgmVolume;
      _clips = state.clips.map((e) => e.copyWith()).toList();
      _currentClipIndex = normalizedNextIndex;
      widget.project.canvasAspectRatioPreset = state.canvasAspectRatioPreset;
      widget.project.canvasBackgroundMode = state.canvasBackgroundMode;
      _recalculateTimelineMetrics();
    });

    if (_bgmPath != null &&
        (_bgmController == null ||
            _bgmController!.dataSource != 'file://${_bgmPath!}')) {
      _initBgmController(_bgmPath!);
    } else if (_bgmPath == null) {
      _bgmController?.dispose();
      _bgmController = null;
    }
    _updateVolumes();

    if (_clips.isEmpty) {
      return;
    }

    final nextPath = _clips[_currentClipIndex].path;
    final needReload =
        _controller == null ||
        !_isInitialized ||
        _controller!.dataSource != 'file://$nextPath';
    if (needReload) {
      _loadClip(
        _currentClipIndex,
        autoPlay: previousPath != nextPath ? false : wasPlaying,
      ).then((_) {
        if (!mounted || _isDisposed) return;
        if (keepPlayback) {
          _isPlaying = wasPlaying;
        } else if (previousPath == nextPath) {
          _isPlaying = _controller?.value.isPlaying == true;
        }
        if (_controller != null) {
          _controller!.seekTo(_clips[_currentClipIndex].startTime);
          if (wasPlaying) {
            _controller!.play();
          } else {
            _controller!.pause();
          }
        }
      });
    } else {
      _controller!.seekTo(_clips[_currentClipIndex].startTime);
      final clipSpeed = _clips[_currentClipIndex].playbackSpeed.clamp(
        0.25,
        3.0,
      );
      _controller!.setPlaybackSpeed(clipSpeed);
      _bgmController?.setPlaybackSpeed(clipSpeed);
      if (wasPlaying) {
        _controller!.play();
      } else {
        _controller!.pause();
      }
      if (mounted && !_isDisposed) {
        setState(() {
          _isPlaying = wasPlaying;
        });
      }
    }
  }

  void _executeStateChange(EditorState newState) {
    final oldState = _currentState.copy();
    _executeStateTransition(oldState, newState);
  }

  void _executeStateTransition(EditorState oldState, EditorState newState) {
    var initialApply = true;
    final command = _GenericStateCommand(
      oldState: oldState,
      newState: newState.copy(),
      onRestore: (state) {
        _applyEditorState(state, keepPlayback: initialApply);
        initialApply = false;
      },
    );

    _commandManager.execute(command);
    _scheduleAutosave(reason: 'state_transition');
  }

  void _startOverlayGesture() {
    _overlayGestureBaseState = _currentState.copy();
    _overlayGestureDirty = false;
  }

  void _commitOverlayGesture() {
    if (!_overlayGestureDirty || _overlayGestureBaseState == null) {
      _overlayGestureBaseState = null;
      _overlayGestureDirty = false;
      return;
    }

    final oldState = _overlayGestureBaseState!;
    final newState = _currentState.copy();
    _overlayGestureBaseState = null;
    _overlayGestureDirty = false;
    _executeStateTransition(oldState, newState);
  }

  void _startTransformGesture() {
    _transformGestureBaseState = _currentState.copy();
    _transformGestureDirty = false;
  }

  void _scheduleTransformQuickAction(
    _TransformQuickAction action,
    VoidCallback apply,
  ) {
    if (_isTransformAngleDragging) {
      _commitTransformGesture();
    }

    if (action == _TransformQuickAction.angle) {
      final clip = _getCurrentClipForTransform();
      final targetOpenState =
          _transformInlinePanel == _TransformInlinePanel.angle
          ? _TransformInlinePanel.none
          : _TransformInlinePanel.angle;
      final currentAngle = clip == null
          ? 0.0
          : _quantizeAngleStep(clip.transformAngle.clamp(-180.0, 180.0));
      setState(() {
        _transformInlinePanel = targetOpenState;
        _showTransformAngleNumericLabel =
            targetOpenState == _TransformInlinePanel.angle
            ? currentAngle != 0.0
            : false;
      });
      return;
    }

    setState(() {
      _showTransformAngleNumericLabel = false;
      _transformInlinePanel = _TransformInlinePanel.none;
    });
    _isTransformAngleDragging = false;
    apply();
  }

  void _setTransformAngleNumericLabelFromCurrentValue() {
    final clip = _getCurrentClipForTransform();
    final currentAngle = clip == null
        ? 0.0
        : _quantizeAngleStep(clip.transformAngle.clamp(-180.0, 180.0));
    setState(() {
      _showTransformAngleNumericLabel = currentAngle != 0.0;
    });
  }

  void _commitTransformGesture() {
    if (!_transformGestureDirty || _transformGestureBaseState == null) {
      _transformGestureBaseState = null;
      _transformGestureDirty = false;
      return;
    }

    final oldState = _transformGestureBaseState!;
    final newState = _currentState.copy();
    _transformGestureBaseState = null;
    _transformGestureDirty = false;
    _executeStateTransition(oldState, newState);
  }

  void _scheduleTransformPreviewFrame() {
    if (_transformPreviewFrameScheduled || !mounted || _isDisposed) return;
    _transformPreviewFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _transformPreviewFrameScheduled = false;
      if (!mounted || _isDisposed) return;
      setState(() {});
    });
  }

  void _onPreviewTransformGestureStart(ScaleStartDetails details) {
    if ((!_isTransformModeActive && !_transformDirectManipulationEnabled) ||
        _clips.isEmpty) {
      return;
    }
    final clip = _getCurrentClipForTransform();
    if (clip == null) {
      Fluttertoast.showToast(msg: '대상을 먼저 선택하세요');
      return;
    }
    _transformGestureBaseScale = clip.transformScale;
    _startTransformGesture();
  }

  void _onPreviewTransformGestureUpdate(
    ScaleUpdateDetails details,
    Size canvasSize,
  ) {
    if ((!_isTransformModeActive && !_transformDirectManipulationEnabled) ||
        _clips.isEmpty) {
      return;
    }
    if (canvasSize.width <= 0 || canvasSize.height <= 0) return;

    _applyCurrentClipTransformPreview((clip) {
      final nextX =
          clip.transformOffsetX +
          (details.focalPointDelta.dx / (canvasSize.width * 0.5));
      final nextY =
          clip.transformOffsetY +
          (details.focalPointDelta.dy / (canvasSize.height * 0.5));
      clip.transformOffsetX = nextX.clamp(-1.0, 1.0);
      clip.transformOffsetY = nextY.clamp(-1.0, 1.0);
      clip.transformScale = (_transformGestureBaseScale * details.scale).clamp(
        0.5,
        2.0,
      );
    });
  }

  void _onPreviewTransformGestureEnd(ScaleEndDetails details) {
    if ((!_isTransformModeActive && !_transformDirectManipulationEnabled) ||
        _clips.isEmpty) {
      return;
    }
    _commitTransformGesture();
  }

  void _applyCurrentClipTransformInstant(void Function(VlogClip clip) update) {
    final clip = _getCurrentClipForTransform();
    if (clip == null) return;
    final oldState = _currentState.copy();
    setState(() {
      update(clip);
    });
    final newState = _currentState.copy();
    _executeStateTransition(oldState, newState);
  }

  void _applyCurrentClipTransformPreview(void Function(VlogClip clip) update) {
    final clip = _getCurrentClipForTransform();
    if (clip == null) return;
    update(clip);
    _transformGestureDirty = true;
    _scheduleTransformPreviewFrame();
  }

  void _enterTransformMode() {
    if (_clips.isEmpty) return;

    final shouldActivate = !_isTransformModeActive;
    if (shouldActivate) {
      _controller?.pause();
      _bgmController?.pause();
      _transformSessionBaseState = _currentState.copy();
      _transformSessionBasePosition = _controller?.value.position;
      _showTransformAngleNumericLabel = false;
      _isTransformAngleDragging = false;
    }

    setState(() {
      _isTransformModeActive = shouldActivate;
      _playbackLockedByTransform = shouldActivate;
      _transformInlinePanel = _TransformInlinePanel.none;
      if (shouldActivate) {
        _isPlaying = false;
        _transformDirectManipulationEnabled = true;
      } else {
        _commitTransformGesture();
        _transformDirectManipulationEnabled = false;
        _transformSessionBaseState = null;
        _transformSessionBasePosition = null;
        _showTransformAngleNumericLabel = false;
        _isTransformAngleDragging = false;
        _transformInlinePanel = _TransformInlinePanel.none;
      }
    });
  }

  void _restoreTransformSession() {
    final baseState = _transformSessionBaseState;
    if (baseState == null) return;
    final basePosition = _transformSessionBasePosition;

    _applyEditorState(baseState, keepPlayback: false);
    if (basePosition == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isDisposed || _controller == null) return;
      _controller!.seekTo(basePosition);
    });
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (!mounted || _isDisposed || _controller == null) return;
      _controller!.seekTo(basePosition);
    });
  }

  double _adaptiveAngleSnapThreshold(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final shortest = MediaQuery.of(context).size.shortestSide;
    var threshold = 2.4;
    if (dpr < 2.0) threshold += 0.8;
    if (shortest >= 600) threshold -= 0.4;
    return threshold.clamp(1.6, 3.8);
  }

  double _applyAdaptiveAngleSnap(double rawAngle, BuildContext context) {
    const snapPoints = <double>[-180, -90, 0, 90, 180];
    final threshold = _adaptiveAngleSnapThreshold(context);
    for (final snap in snapPoints) {
      if ((rawAngle - snap).abs() <= threshold) {
        return snap;
      }
    }
    return rawAngle;
  }

  double _quantizeAngleStep(double value) => (value * 10).round() / 10;

  void _toggleTransformRotateStep() {
    final clip = _getCurrentClipForTransform();
    if (clip == null) return;

    final nextStep = (clip.transformRotation90Step + 1) % 4;
    _applyCurrentClipTransformInstant((transformClip) {
      transformClip.transformRotation90Step = nextStep;
    });
  }

  void _setTransformAngleMode(_TransformAngleMode mode) {
    if (_transformAngleMode == mode) {
      _setTransformAngleNumericLabelFromCurrentValue();
      return;
    }

    if (_isTransformAngleDragging) {
      _commitTransformGesture();
    }

    setState(() {
      _transformAngleMode = mode;
      _showTransformAngleNumericLabel = false;
    });

    if (mode == _TransformAngleMode.tilt) return;

    _startTransformGesture();
    _applyCurrentClipTransformPreview((clip) {
      clip.transformAngle = mode == _TransformAngleMode.horizontal ? 0.0 : 90.0;
    });
    _commitTransformGesture();
    _setTransformAngleNumericLabelFromCurrentValue();
  }

  String _transformAngleModeLabel(_TransformAngleMode mode) {
    switch (mode) {
      case _TransformAngleMode.tilt:
        return '기울기';
      case _TransformAngleMode.horizontal:
        return '수평';
      case _TransformAngleMode.vertical:
        return '수직';
    }
  }

  String _getBrightnessTransitionFromMode() {
    if (_isTrimMode) return 'trim';
    if (_isTransformModeActive) return 'transform';
    if (_bottomInlinePanel == _BottomInlinePanel.trimSpeedPreset) {
      return 'trim_speed_preset';
    }
    if (_bottomInlinePanel == _BottomInlinePanel.sound) return 'sound_panel';
    return 'none';
  }

  void _exitBrightnessModeForReason(
    String reason, {
    String? note,
    String? fromMode,
  }) {
    final wasBrightnessActive = _isBrightnessMode;
    final property = _selectedBrightnessProperty;
    final value = (_brightnessAdjustments[property] ?? 0.0).clamp(
      -100.0,
      100.0,
    );
    final wasDragging = _isBrightnessDragging;
    final wasNumericShown = _showBrightnessNumericLabel;
    final resolvedFromMode = fromMode ?? _getBrightnessTransitionFromMode();

    if (!wasBrightnessActive) {
      _traceBrightnessEvent(
        'brightness_mode_exit_skipped_$reason',
        '${note ?? 'already inactive'} from=$resolvedFromMode',
        property: property,
        value: value,
        dragging: wasDragging,
        showLabel: wasNumericShown,
      );
      return;
    }

    if (wasDragging) {
      _commitBrightnessGesture();
    }

    setState(() {
      _isBrightnessMode = false;
      _showBrightnessNumericLabel = false;
      _isBrightnessDragging = false;
    });

    _traceBrightnessEvent(
      'brightness_mode_exit_$reason',
      '${note ?? 'toolbar transition'} from=$resolvedFromMode',
      property: property,
      value: value,
      dragging: wasDragging,
      showLabel: wasNumericShown,
    );
  }

  void _applyClipSpeedPreset(double speed) {
    if (_controller == null || !_isInitialized) return;
    final clamped = speed.clamp(0.25, 3.0);
    _applyCurrentClipTransformInstant((clip) {
      clip.playbackSpeed = clamped;
    });
    _controller!.setPlaybackSpeed(clamped);
    _bgmController?.setPlaybackSpeed(clamped);
  }

  void _startTrimGesture() {
    _trimGestureBaseState = _currentState.copy();
    _trimGestureDirty = false;
  }

  void _setTrimTimelineInteraction(_TrimTimelineInteraction interaction) {
    final previousInteraction = _activeTrimTimelineInteraction;
    if (_activeTrimTimelineInteraction == interaction) {
      return;
    }
    _activeTrimTimelineInteraction = interaction;

    if (interaction != _TrimTimelineInteraction.playhead) {
      _trimPlayheadSeekScheduled = false;
      _pendingPlayheadTrimSeekMs = null;
    }

    // When switching into playhead interaction, cancel any pending handle seek
    // to keep playhead/tap interaction as highest priority.
    if (interaction == _TrimTimelineInteraction.playhead) {
      if (previousInteraction != _TrimTimelineInteraction.playhead) {
        _trimSeekDebounceTimer?.cancel();
        _trimSeekDebounceTimer = null;
        _pendingTrimSeekMs = null;
      }
    }
  }

  void _commitTrimGesture() {
    if (!_trimGestureDirty || _trimGestureBaseState == null) {
      _trimGestureBaseState = null;
      _trimGestureDirty = false;
      _activeTrimTimelineInteraction = _TrimTimelineInteraction.none;
      return;
    }

    final oldState = _trimGestureBaseState!;
    final newState = _currentState.copy();

    // 드래그 종료 시 마지막 미리보기 시크를 즉시 반영
    final pendingMs = _pendingTrimSeekMs;
    if (pendingMs != null) {
      _trimSeekDebounceTimer?.cancel();
      _trimSeekDebounceTimer = null;
      _pendingTrimSeekMs = null;
      _lastIssuedTrimSeekMs = pendingMs;
      _controller?.seekTo(Duration(milliseconds: pendingMs));
    }

    _trimGestureBaseState = null;
    _trimGestureDirty = false;
    if (_trimUiStateNotifier != null && _currentClipIndex < _clips.length) {
      _trimUiStateNotifier!.value = _buildTrimUiStateForClip(
        _clips[_currentClipIndex],
      );
    }
    _requestTrimUiRebuild(force: true);
    _executeStateTransition(oldState, newState);
    _activeTrimTimelineInteraction = _TrimTimelineInteraction.none;
  }

  void _resetTrimUiInteractionState() {
    _activeTrimTimelineInteraction = _TrimTimelineInteraction.none;
    _trimPlayheadSeekScheduled = false;
    _pendingPlayheadTrimSeekMs = null;
    _pendingTrimSeekMs = null;
    _trimSeekDebounceTimer?.cancel();
    _trimSeekDebounceTimer = null;
  }

  void _scheduleTrimPreviewSeek(
    Duration target, {
    _TrimTimelineInteraction? reason,
  }) {
    final effectiveReason = reason ?? _activeTrimTimelineInteraction;

    if (effectiveReason == _TrimTimelineInteraction.playhead) {
      _pendingPlayheadTrimSeekMs = target.inMilliseconds;
      if (_trimPlayheadSeekScheduled) return;
      _trimPlayheadSeekScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDisposed || _controller == null) {
          _trimPlayheadSeekScheduled = false;
          _pendingPlayheadTrimSeekMs = null;
          return;
        }

        _trimPlayheadSeekScheduled = false;
        if (_activeTrimTimelineInteraction !=
            _TrimTimelineInteraction.playhead) {
          _pendingPlayheadTrimSeekMs = null;
          return;
        }

        final ms = _pendingPlayheadTrimSeekMs;
        _pendingPlayheadTrimSeekMs = null;
        if (ms == null) return;
        _pendingTrimSeekMs = ms;
        _lastIssuedTrimSeekMs = ms;
        _controller!.seekTo(Duration(milliseconds: ms));
      });
      return;
    }

    _pendingTrimSeekMs = target.inMilliseconds;
    _trimSeekDebounceTimer?.cancel();
    _trimSeekDebounceTimer = Timer(const Duration(milliseconds: 24), () {
      if (!mounted || _isDisposed || _controller == null) return;
      final ms = _pendingTrimSeekMs;
      _pendingTrimSeekMs = null;
      if (ms == null) return;
      final lastMs = _lastIssuedTrimSeekMs;
      if (lastMs != null && (ms - lastMs).abs() < 12) {
        return;
      }
      _lastIssuedTrimSeekMs = ms;
      _controller!.seekTo(Duration(milliseconds: ms));
    });
  }

  void _pausePlaybackForEditingMode() {
    if (_isPlaying) {
      try {
        _controller?.pause();
      } catch (_) {}
      try {
        _bgmController?.pause();
      } catch (_) {}
    }

    if (_isPlaying) {
      if (mounted && !_isDisposed) {
        setState(() => _isPlaying = false);
      } else {
        _isPlaying = false;
      }
    }
  }

  void _requestTrimUiRebuild({bool force = false}) {
    if (!mounted || _isDisposed) return;
    if (_isTrimMode && _trimUiStateNotifier != null) {
      final currentMs = _controller?.value.position.inMilliseconds.toDouble();
      if (currentMs != null) {
        _syncTrimUiCurrentMs(currentMs);
      }
      if (force) {
        _trimUiStateNotifier!.value = _trimUiStateNotifier!.value.copyWith();
      }
      return;
    }
    if (force) {
      setState(() {});
      return;
    }
    if (_trimUiFrameScheduled) return;
    _trimUiFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _trimUiFrameScheduled = false;
      if (!mounted || _isDisposed) return;
      setState(() {});
    });
  }

  _TrimUiState _buildTrimUiStateForClip(VlogClip clip) {
    final totalDuration = _clipDurations.length > _currentClipIndex
        ? _clipDurations[_currentClipIndex]
        : clip.endTime;

    double startMs = clip.startTime.inMilliseconds.toDouble();
    double endMs = clip.endTime.inMilliseconds.toDouble();
    double maxMs = totalDuration.inMilliseconds.toDouble();
    if (maxMs <= 0) maxMs = 1000.0;
    if (endMs > maxMs) endMs = maxMs;
    if (startMs >= endMs) startMs = (endMs - 100).clamp(0.0, maxMs);

    final currentRaw = _controller?.value.position.inMilliseconds.toDouble();
    final currentMs = currentRaw == null
        ? startMs
        : currentRaw.clamp(startMs, endMs);

    return _TrimUiState(
      startMs: startMs,
      endMs: endMs,
      currentMs: currentMs,
      maxMs: maxMs,
    );
  }

  void _ensureTrimUiStateForCurrentClip({bool force = false}) {
    if (_currentClipIndex >= _clips.length) return;
    final clip = _clips[_currentClipIndex];
    final next = _buildTrimUiStateForClip(clip);
    final notifier = _trimUiStateNotifier;
    if (notifier == null) {
      _trimUiStateNotifier = ValueNotifier<_TrimUiState>(next);
      return;
    }

    final current = notifier.value;
    final changed =
        force ||
        (current.startMs - next.startMs).abs() >= 1 ||
        (current.endMs - next.endMs).abs() >= 1 ||
        (current.maxMs - next.maxMs).abs() >= 1 ||
        (current.currentMs - next.currentMs).abs() >= 8;
    if (changed) {
      notifier.value = next;
    }
  }

  void _syncTrimUiCurrentMs(double currentMs) {
    final notifier = _trimUiStateNotifier;
    if (notifier == null) return;
    final current = notifier.value;
    final clamped = currentMs.clamp(current.startMs, current.endMs);
    if ((clamped - current.currentMs).abs() < 4) return;
    notifier.value = current.copyWith(currentMs: clamped);
  }

  double _trimTimelineMsFromLocalX({
    required double localX,
    required _TrimUiState state,
    required double timelineWidth,
  }) {
    if (timelineWidth <= 0 || state.maxMs <= 0) {
      return state.currentMs;
    }
    final safeLocalX = localX.clamp(0.0, timelineWidth);
    final rawMs = (safeLocalX / timelineWidth) * state.maxMs;
    return rawMs.clamp(state.startMs, state.endMs);
  }

  Future<void> _prepareForExportRendering() async {
    _resetTrimUiInteractionState();

    try {
      await _controller?.pause();
    } catch (_) {}
    try {
      _controller?.removeListener(_videoListener);
    } catch (_) {}
    try {
      await _controller?.setVolume(0);
    } catch (_) {}
    try {
      await _bgmController?.pause();
    } catch (_) {}
    try {
      await _nextController?.pause();
    } catch (_) {}

    // Export 직전 preview decode 리소스 반환
    try {
      await _nextController?.dispose();
    } catch (_) {}
    _nextController = null;

    if (mounted && !_isDisposed) {
      setState(() {
        _isPlaying = false;
        _isTrimMode = false;
      });
    }
  }

  void _undo() {
    _commandManager.undo();
    Fluttertoast.showToast(msg: "Undo");
  }

  void _redo() {
    _commandManager.redo();
    Fluttertoast.showToast(msg: "Redo");
  }

  // 트리머 UI

  void _closeTrimMode() {
    if (!_isTrimMode) {
      return;
    }

    _commitTrimGesture();
    _resetTrimUiInteractionState();
    setState(() {
      _isTrimMode = false;
      _bottomInlinePanel = _BottomInlinePanel.none;
    });
  }

  void _toggleTrimMode() {
    if (_clips.isEmpty || _controller == null) return;

    if (_isTrimMode) {
      _closeTrimMode();
      return;
    }

    if (_isTransformModeActive) {
      _enterTransformMode();
    }
    if (_isBrightnessMode) {
      _exitBrightnessModeForReason(
        'trim',
        note: 'trim mode entered',
        fromMode: _isTransformModeActive
            ? 'transform'
            : _bottomInlinePanel == _BottomInlinePanel.sound
            ? 'sound_panel'
            : 'brightness',
      );
    }
    if (_bottomInlinePanel != _BottomInlinePanel.none) {
      _bottomInlinePanel = _BottomInlinePanel.none;
    }

    setState(() {
      _isTrimMode = true;
    });
    _ensureTrimUiStateForCurrentClip(force: true);

    // Auto-scroll to selected clip for focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_timelineScrollController.hasClients) {
        final double targetOffset = _currentClipIndex * 80.0; // Estimate
        _timelineScrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _handleTrimBackAction() {
    if (_isTrimMode &&
        _bottomInlinePanel == _BottomInlinePanel.trimSpeedPreset) {
      setState(() {
        _bottomInlinePanel = _BottomInlinePanel.none;
      });
      _resetTrimUiInteractionState();
      return true;
    }
    if (_isTrimMode) {
      _closeTrimMode();
      return true;
    }
    return false;
  }

  String _formatDuration(Duration d) {
    return "${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
  }

  String _formatTrimTime(Duration d) {
    int minutes = d.inMinutes;
    int seconds = d.inSeconds % 60;
    int milliseconds = (d.inMilliseconds % 1000) ~/ 100;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.$milliseconds';
  }

  void _traceBrightnessEvent(
    String event,
    String note, {
    String? property,
    double? value,
    double? nextValue,
    bool? dragging,
    bool? showLabel,
  }) {
    final targetProperty = property ?? _selectedBrightnessProperty;
    final currentValue =
        value ?? (_brightnessAdjustments[targetProperty] ?? 0.0);
    final nextValueText = nextValue == null
        ? 'n/a'
        : nextValue.clamp(-100.0, 100.0).toStringAsFixed(2);
    final nextSeq = ++_e3Seq;
    debugPrint(
      '[EditScreen][Gate-E3] '
      'session=$_e3SessionId seq=$nextSeq event=$event '
      'property=$targetProperty '
      'value=${currentValue.clamp(-100.0, 100.0).toStringAsFixed(2)} '
      'nextValue=$nextValueText '
      'showLabel=${showLabel ?? _showBrightnessNumericLabel} '
      'dragging=${dragging ?? _isBrightnessDragging} '
      'clip=$_currentClipIndex/${_clips.length} '
      'note=$note',
    );
  }

  // UI 빌드

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isTrimMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleTrimBackAction();
      },
      child: Scaffold(
        backgroundColor: _bgColor,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: Stack(
                  children: [
                    _buildPreviewSection(),
                    ..._stickers.map((s) => _buildStickerWidget(s)),
                    ..._subtitles.map((s) => _buildSubtitleWidget(s)),
                  ],
                ),
              ),
              _buildBottomControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    final bool showSoundPanel = _bottomInlinePanel == _BottomInlinePanel.sound;
    final bool showBrightnessPanel = _isBrightnessMode;
    final double bottomPanelHeight =
        _inlineModePanelHeight + _inlineModePanelGap + _bottomToolbarHeight;

    return Container(
      height: bottomPanelHeight,
      color: _bgColor,
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _isTransformModeActive
                ? KeyedSubtree(
                    key: ValueKey(
                      _transformInlinePanel == _TransformInlinePanel.angle
                          ? 'panel_transform_angle'
                          : 'panel_transform_empty',
                    ),
                    child: _transformInlinePanel == _TransformInlinePanel.angle
                        ? _buildTransformAnglePanel()
                        : SizedBox(height: _inlineModePanelHeight),
                  )
                : showBrightnessPanel
                ? KeyedSubtree(
                    key: const ValueKey('panel_brightness'),
                    child: _buildBrightnessInlinePanel(),
                  )
                : showSoundPanel
                ? KeyedSubtree(
                    key: const ValueKey('panel_sound'),
                    child: _buildInlineSoundPanel(),
                  )
                : KeyedSubtree(
                    key: const ValueKey('panel_timeline'),
                    child: _buildTimelineSection(),
                  ),
          ),
          const SizedBox(height: 2),
          Expanded(child: _buildGlassToolbar()),
        ],
      ),
    );
  }

  Widget _buildPreviewSection() {
    if (_isMissingFile) {
      final missingIndex = _missingIndexForUi();
      final clipNumber = missingIndex == null ? '-' : '${missingIndex + 1}';
      final clipName = (missingIndex != null && missingIndex < _clips.length)
          ? _clips[missingIndex].path.split('/').last
          : 'unknown';
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE4E8EF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 54),
              const SizedBox(height: 12),
              const Text(
                'File Missing',
                style: TextStyle(
                  color: Color(0xFF121212),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '누락 클립: $clipNumber 번',
                style: const TextStyle(
                  color: Color(0xFF2A2F37),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                clipName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF5A6472), fontSize: 12),
              ),
              const SizedBox(height: 14),
              if (missingIndex != null)
                ElevatedButton.icon(
                  onPressed: () => _confirmAndRemoveClip(missingIndex),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD32F2F),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('문제 클립 제거'),
                ),
            ],
          ),
        ),
      );
    }

    final controller = _controller;
    if (!_isInitialized || controller == null) {
      debugPrint(
        '⏳⏳⏳ [BUILD] Showing loading: _isInitialized=$_isInitialized, controller=${_controller != null}',
      );
      return const Center(
        child: CircularProgressIndicator(color: _primaryColor),
      );
    }

    // Safe check: ensure native player is still alive
    late final VideoPlayerValue value;
    try {
      value = controller.value;
      if (!value.isInitialized) {
        debugPrint(
          '⚠️⚠️⚠️ [BUILD] Controller exists but NOT initialized! Showing loading. ⚠️⚠️⚠️',
        );
        return const Center(
          child: CircularProgressIndicator(color: _primaryColor),
        );
      }
    } catch (e) {
      debugPrint('\n\n⛔⛔⛔ [BUILD] Controller access CRASHED: $e ⛔⛔⛔\n');
      return const Center(
        child: CircularProgressIndicator(color: _primaryColor),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: AspectRatio(
            aspectRatio: _canvasAspectRatioForPreset(
              widget.project.canvasAspectRatioPreset,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(11.2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11.2),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final canvasSize = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    final clip = _getCurrentClipForTransform();
                    final fitMode = clip?.transformFitMode ?? 'fill';
                    final boxFit = fitMode == 'fit'
                        ? BoxFit.contain
                        : BoxFit.cover;
                    final scale = clip?.transformScale ?? 1.0;
                    final rotation90 =
                        (clip?.transformRotation90Step ?? 0) * (math.pi / 2);
                    final angle =
                        (clip?.transformAngle ?? 0.0) * (math.pi / 180.0);
                    final totalRotation = rotation90 + angle;
                    final scaleX = (clip?.transformFlipX ?? false)
                        ? -scale
                        : scale;
                    final scaleY = (clip?.transformFlipY ?? false)
                        ? -scale
                        : scale;
                    final offsetX =
                        (clip?.transformOffsetX ?? 0.0) *
                        constraints.maxWidth *
                        0.5;
                    final offsetY =
                        (clip?.transformOffsetY ?? 0.0) *
                        constraints.maxHeight *
                        0.5;

                    final canvasAspect = _canvasAspectRatioForPreset(
                      widget.project.canvasAspectRatioPreset,
                    );
                    final sourceAspect = value.size.height == 0
                        ? canvasAspect
                        : value.size.width / value.size.height;
                    final showCropGuide =
                        fitMode == 'fill' &&
                        (sourceAspect - canvasAspect).abs() > 0.02;

                    return GestureDetector(
                      onTap: _isTransformModeActive ? null : _togglePlayPause,
                      onScaleStart: _transformDirectManipulationEnabled
                          ? _onPreviewTransformGestureStart
                          : null,
                      onScaleUpdate: _transformDirectManipulationEnabled
                          ? (details) => _onPreviewTransformGestureUpdate(
                              details,
                              canvasSize,
                            )
                          : null,
                      onScaleEnd: _transformDirectManipulationEnabled
                          ? _onPreviewTransformGestureEnd
                          : null,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColorFiltered(
                            colorFilter: _getFilterMatrix(),
                            child: Transform.translate(
                              offset: Offset(offsetX, offsetY),
                              child: Transform.rotate(
                                angle: totalRotation,
                                child: Transform.scale(
                                  scaleX: scaleX,
                                  scaleY: scaleY,
                                  child: FittedBox(
                                    fit: boxFit,
                                    child: SizedBox(
                                      width: value.size.width,
                                      height: value.size.height,
                                      child: VideoPlayer(controller),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (showCropGuide)
                            IgnorePointer(
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0x88FFFFFF),
                                    width: 1,
                                  ),
                                ),
                              ),
                            ),
                          if (!_isPlaying &&
                              !_transformDirectManipulationEnabled)
                            Container(
                              color: Colors.black26,
                              child: const Center(
                                child: Icon(
                                  Icons.play_arrow,
                                  color: Colors.white,
                                  size: 64,
                                ),
                              ),
                            ),
                          _buildVideoProgressOverlay(),
                          _buildTrimSpeedPresetOverlay(),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoProgressOverlay() {
    if (_isTransformModeActive) return _buildTransformQuickOverlayInPreview();
    final controller = _controller;
    if (controller == null || !_isInitialized) return const SizedBox.shrink();

    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, VideoPlayerValue value, child) {
        final globalPos = _calculateGlobalPosition();
        final globalDuration = _totalDuration; // Fix missing variable

        if (_isTrimMode) {
          return Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.62,
                child: Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: _togglePlayPause,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.46),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.42),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${_formatDuration(Duration(milliseconds: globalPos.toInt()))} / ${_formatDuration(globalDuration)}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () {
                        setState(() {
                          _bottomInlinePanel =
                              _bottomInlinePanel ==
                                  _BottomInlinePanel.trimSpeedPreset
                              ? _BottomInlinePanel.none
                              : _BottomInlinePanel.trimSpeedPreset;
                        });
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.42),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0x44FFFFFF)),
                        ),
                        child: const Icon(
                          Icons.speed,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.62,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(
                          Duration(milliseconds: globalPos.toInt()),
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          shadows: [
                            Shadow(blurRadius: 3, color: Colors.black54),
                          ],
                        ),
                      ),
                      Text(
                        _formatDuration(globalDuration),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          shadows: [
                            Shadow(blurRadius: 3, color: Colors.black54),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 5,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 10,
                      ),
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white30,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: globalPos.clamp(
                        0.0,
                        globalDuration.inMilliseconds.toDouble(),
                      ),
                      min: 0.0,
                      max: globalDuration.inMilliseconds > 0
                          ? globalDuration.inMilliseconds.toDouble()
                          : 1.0,
                      onChanged: _seekToGlobalPosition,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrimSpeedPresetOverlay() {
    if (!_isTrimMode ||
        _bottomInlinePanel != _BottomInlinePanel.trimSpeedPreset) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 66),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: _buildTrimSpeedPresetPanel(),
        ),
      ),
    );
  }

  Widget _buildTransformQuickOverlayInPreview() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: _transformOverlayBottomInset),
        child: _buildTransformQuickOverlay(),
      ),
    );
  }

  Widget _buildTransformQuickOverlay() {
    if (!_isTransformModeActive || _isTrimMode || _clips.isEmpty) {
      return const SizedBox.shrink();
    }
    final clip = _getCurrentClipForTransform();
    if (clip == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0x66FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildTransformQuickAction(
            icon: Icons.flip,
            semanticLabel: '좌우 반전',
            active: clip.transformFlipX || clip.transformFlipY,
            onTap: () => _scheduleTransformQuickAction(
              _TransformQuickAction.flip,
              () => _applyCurrentClipTransformInstant((c) {
                c.transformFlipX = !c.transformFlipX;
              }),
            ),
          ),
          const SizedBox(width: 8),
          _buildTransformQuickAction(
            icon: Icons.crop_rotate,
            semanticLabel: '회전 +90도',
            onTap: () => _scheduleTransformQuickAction(
              _TransformQuickAction.rotate,
              _toggleTransformRotateStep,
            ),
          ),
          const SizedBox(width: 8),
          _buildTransformQuickAction(
            icon: Icons.straighten,
            semanticLabel: 'Angle 패널 토글',
            active: _transformInlinePanel == _TransformInlinePanel.angle,
            onTap: () => _scheduleTransformQuickAction(
              _TransformQuickAction.angle,
              () {},
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransformAnglePanel() {
    final clip = _getCurrentClipForTransform();
    if (clip == null) {
      return SizedBox(height: _inlineModePanelHeight);
    }

    final currentValue = _quantizeAngleStep(
      clip.transformAngle.clamp(-180.0, 180.0),
    );

    return Container(
      height: _inlineModePanelHeight,
      margin: EdgeInsets.fromLTRB(
        _inlineModePanelSidePadding,
        _inlineModePanelSpacing,
        _inlineModePanelSidePadding,
        _inlineModePanelSpacing,
      ),
      padding: EdgeInsets.fromLTRB(
        _inlineModePanelSidePadding,
        _inlineModePanelVerticalPadding,
        _inlineModePanelSidePadding,
        _inlineModePanelVerticalPadding,
      ),
      decoration: _inlineModePanelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: _inlineModeChipRowHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _TransformAngleMode.values.length,
              separatorBuilder: (_, index) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final mode = _TransformAngleMode.values[index];
                final selected = mode == _transformAngleMode;
                final text = _transformAngleModeLabel(mode);
                return InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () {
                    _setTransformAngleMode(mode);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF2B8CEE)
                          : Colors.white12,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF9FD0FF)
                            : Colors.white24,
                      ),
                    ),
                    child: Text(
                      selected && _showTransformAngleNumericLabel
                          ? '${currentValue.toStringAsFixed(1)}°'
                          : text,
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _buildInlineRulerControl(
              value: currentValue,
              minValue: -180.0,
              maxValue: 180.0,
              divisions: 3600,
              onChanged: (value) {
                _applyCurrentClipTransformPreview(
                  (c) => c.transformAngle = _quantizeAngleStep(value),
                );
              },
              onInteractionStart: () {
                if (!_isTransformAngleDragging) {
                  _startTransformGesture();
                  setState(() {
                    _isTransformAngleDragging = true;
                    _showTransformAngleNumericLabel = true;
                  });
                }
              },
              onInteractionEnd: () {
                _commitTransformGesture();
                _setTransformAngleNumericLabelFromCurrentValue();
                if (_isTransformAngleDragging) {
                  setState(() => _isTransformAngleDragging = false);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransformQuickAction({
    required IconData icon,
    required String semanticLabel,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Tooltip(
        message: semanticLabel,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? const Color(0x332B8CEE) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 24,
                color: active ? const Color(0xFF9FD0FF) : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  ColorFilter _getFilterMatrix() {
    switch (_selectedFilter) {
      case FilterPreset.grayscale:
        return const ColorFilter.matrix(<double>[
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]);
      case FilterPreset.warm:
        return ColorFilter.mode(
          Colors.orangeAccent.withAlpha(50),
          BlendMode.overlay,
        );
      case FilterPreset.cool:
        return ColorFilter.mode(
          Colors.blueAccent.withAlpha(50),
          BlendMode.overlay,
        );
      default:
        return const ColorFilter.mode(Colors.transparent, BlendMode.dst);
    }
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: _textPrimary, size: 28),
                onPressed: _isClosingWithSave ? null : _handleClosePressed,
                tooltip: '닫기',
              ),
              Expanded(
                child: Text(
                  widget.project.title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(92, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                onPressed: _handleExport,
                child: const Text(
                  "만들기",
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: _headerRowSpacing),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.undo,
                    color: _commandManager.canUndo
                        ? _textPrimary
                        : Colors.black26,
                  ),
                  onPressed: _commandManager.canUndo ? _undo : null,
                  tooltip: 'Undo',
                ),
                IconButton(
                  icon: Icon(
                    Icons.redo,
                    color: _commandManager.canRedo
                        ? _textPrimary
                        : Colors.black26,
                  ),
                  onPressed: _commandManager.canRedo ? _redo : null,
                  tooltip: 'Redo',
                ),
                IconButton(
                  icon: const Icon(Icons.aspect_ratio, color: _textPrimary),
                  onPressed: _showCanvasPanel,
                  tooltip:
                      'Canvas ${_canvasAspectLabel(widget.project.canvasAspectRatioPreset)}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassToolbar() {
    return SizedBox(
      height: 88,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          _buildToolbarItem(
            Icons.content_cut,
            "Trim",
            _toggleTrimMode,
            active: _isTrimMode,
          ),
          _buildToolbarItem(Icons.crop_rotate, "Transform", () {
            final transitionFrom = _getBrightnessTransitionFromMode();
            _traceBrightnessEvent(
              'toolbar_transform_pressed',
              'from=$transitionFrom',
              property: _selectedBrightnessProperty,
              value: _brightnessAdjustments[_selectedBrightnessProperty] ?? 0.0,
              dragging: _isBrightnessDragging,
              showLabel: _showBrightnessNumericLabel,
            );
            if (_isTrimMode) {
              _closeTrimMode();
            }
            if (_bottomInlinePanel != _BottomInlinePanel.none) {
              setState(() => _bottomInlinePanel = _BottomInlinePanel.none);
            }
            if (_isBrightnessMode) {
              _exitBrightnessModeForReason(
                'transform_toolbar',
                note: 'toolbar transform pressed',
                fromMode: transitionFrom,
              );
            }
            _enterTransformMode();
          }, active: _isTransformModeActive),
          _buildToolbarItem(Icons.wb_sunny_outlined, "밝기", () {
            final fromMode = _getBrightnessTransitionFromMode();
            _traceBrightnessEvent(
              'toolbar_brightness_pressed',
              'from=$fromMode',
              property: _selectedBrightnessProperty,
              value: _brightnessAdjustments[_selectedBrightnessProperty] ?? 0.0,
              dragging: _isBrightnessDragging,
              showLabel: _showBrightnessNumericLabel,
            );

            if (_isTrimMode) {
              _closeTrimMode();
            }
            if (_isTransformModeActive) {
              _enterTransformMode();
            }
            if (_bottomInlinePanel != _BottomInlinePanel.none) {
              setState(() => _bottomInlinePanel = _BottomInlinePanel.none);
            }
            _enterBrightnessMode(
              reason: 'toolbar_brightness_button',
              fromMode: fromMode,
              forceOpen: fromMode != 'none' && !_isBrightnessMode,
            );
          }, active: _isBrightnessMode),
          _buildToolbarItem(
            Icons.volume_up,
            "사운드",
            () {
              final transitionFrom = _getBrightnessTransitionFromMode();
              _traceBrightnessEvent(
                'toolbar_sound_pressed',
                'from=$transitionFrom',
                property: _selectedBrightnessProperty,
                value:
                    _brightnessAdjustments[_selectedBrightnessProperty] ?? 0.0,
                dragging: _isBrightnessDragging,
                showLabel: _showBrightnessNumericLabel,
              );
              if (_isTrimMode) {
                _closeTrimMode();
              }
              if (_isTransformModeActive) {
                _enterTransformMode();
              }
              if (_isBrightnessMode) {
                _exitBrightnessModeForReason(
                  'sound_toolbar',
                  note: 'toolbar sound pressed',
                  fromMode: transitionFrom,
                );
              }
              if (_bottomInlinePanel == _BottomInlinePanel.trimSpeedPreset) {
                setState(() => _bottomInlinePanel = _BottomInlinePanel.none);
                return;
              }
              setState(() {
                _bottomInlinePanel =
                    _bottomInlinePanel == _BottomInlinePanel.sound
                    ? _BottomInlinePanel.none
                    : _BottomInlinePanel.sound;
              });
            },
            active: _bottomInlinePanel == _BottomInlinePanel.sound,
          ),
          _buildToolbarItem(Icons.auto_awesome, "AI", () {
            final transitionFrom = _getBrightnessTransitionFromMode();
            _traceBrightnessEvent(
              'toolbar_ai_pressed',
              'from=$transitionFrom',
              property: _selectedBrightnessProperty,
              value: _brightnessAdjustments[_selectedBrightnessProperty] ?? 0.0,
              dragging: _isBrightnessDragging,
              showLabel: _showBrightnessNumericLabel,
            );
            if (_isTrimMode) {
              _closeTrimMode();
            }
            if (_isTransformModeActive) {
              _enterTransformMode();
            }
            if (_isBrightnessMode) {
              _exitBrightnessModeForReason(
                'ai_toolbar',
                note: 'toolbar ai pressed',
                fromMode: transitionFrom,
              );
            }
            if (_bottomInlinePanel != _BottomInlinePanel.none) {
              setState(() => _bottomInlinePanel = _BottomInlinePanel.none);
            }
            _showFilterDialog();
          }, emphasized: true),
        ],
      ),
    );
  }

  Widget _buildToolbarItem(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool emphasized = false,
    bool active = false,
  }) {
    final Color iconColor = active
        ? _primaryColor
        : emphasized
        ? const Color(0xFF7A38E5)
        : _textPrimary;

    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 55.8,
                height: 55.8,
                decoration: BoxDecoration(
                  color: emphasized
                      ? const Color(0xFFE8E3F4)
                      : active
                      ? const Color(0xFFE8F2FD)
                      : const Color(0xFFF0F2F4),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: emphasized
                        ? const Color(0xFFD8C7F8)
                        : active
                        ? const Color(0xFFB7D7FA)
                        : const Color(0xFFE6EBF0),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x12000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, color: iconColor, size: 35.1),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrimSpeedPresetPanel() {
    if (_clips.isEmpty || _currentClipIndex >= _clips.length) {
      return const SizedBox(height: 42);
    }
    final clip = _clips[_currentClipIndex];
    const presets = <double>[0.25, 0.5, 1.0, 2.0];
    const double baseButtonSize = 40.0;
    const double compactSpacing = 2.0;
    String speedLabel(double speed) {
      if (speed == 0.25) return '1/4';
      if (speed == 0.5) return '1/2';
      if (speed == 1.0) return '1';
      return '2';
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final int count = presets.length;
        final double availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : (baseButtonSize * count);
        final double compactThreshold =
            (baseButtonSize * count) + (compactSpacing * (count - 1));
        final bool compact = availableWidth < compactThreshold;
        final double buttonSize = compact
            ? ((availableWidth - compactSpacing * (count - 1)) / count).clamp(
                0.0,
                baseButtonSize,
              )
            : baseButtonSize;

        return SizedBox(
          height: compact ? 36 : 42,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: presets.map((speed) {
                final bool selected = (clip.playbackSpeed - speed).abs() < 0.05;
                final bool isLast = presets.last == speed;
                return Padding(
                  padding: EdgeInsets.only(right: isLast ? 0 : compactSpacing),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _applyClipSpeedPreset(speed),
                    child: SizedBox(
                      width: buttonSize,
                      height: compact ? 30 : 32,
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected
                              ? Colors.white
                              : Colors.black.withValues(alpha: 0.36),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: selected
                                ? Colors.white
                                : const Color(0x77FFFFFF),
                          ),
                        ),
                        child: Text(
                          speedLabel(speed),
                          style: TextStyle(
                            color: selected
                                ? const Color(0xFF111111)
                                : Colors.white,
                            fontSize: 10.8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInlineSoundPanel() {
    return Container(
      height: _inlineModePanelHeight,
      margin: EdgeInsets.fromLTRB(
        _inlineModePanelSidePadding,
        _inlineModePanelSpacing,
        _inlineModePanelSidePadding,
        _inlineModePanelSpacing,
      ),
      padding: EdgeInsets.fromLTRB(
        _inlineModePanelSidePadding,
        _inlineModePanelVerticalPadding,
        _inlineModePanelSidePadding,
        _inlineModePanelVerticalPadding,
      ),
      decoration: _inlineModePanelDecoration,
      child: Column(
        children: [
          _buildInlineSoundSliderRow(
            icon: Icons.volume_up,
            label: '전체 사운드',
            value: _videoVolume,
            onChanged: (val) {
              setState(() => _videoVolume = val);
              _updateVolumes();
            },
            onChangeEnd: (val) {
              final newState = EditorState(
                subtitles: _currentState.subtitles,
                stickers: _currentState.stickers,
                filter: _currentState.filter,
                filterOpacity: _currentState.filterOpacity,
                brightnessAdjustments: _currentState.brightnessAdjustments,
                bgmPath: _currentState.bgmPath,
                videoVolume: val,
                bgmVolume: _currentState.bgmVolume,
                clips: _currentState.clips,
                currentClipIndex: _currentState.currentClipIndex,
              );
              _executeStateChange(newState);
            },
          ),
          const SizedBox(height: _inlineModePanelSpacing),
          _buildInlineSoundSliderRow(
            icon: Icons.music_note,
            label: '클립 사운드',
            value: _bgmVolume,
            onChanged: (val) {
              setState(() => _bgmVolume = val);
              _updateVolumes();
            },
            onChangeEnd: (val) {
              final newState = EditorState(
                subtitles: _currentState.subtitles,
                stickers: _currentState.stickers,
                filter: _currentState.filter,
                filterOpacity: _currentState.filterOpacity,
                brightnessAdjustments: _currentState.brightnessAdjustments,
                bgmPath: _currentState.bgmPath,
                videoVolume: _currentState.videoVolume,
                bgmVolume: val,
                clips: _currentState.clips,
                currentClipIndex: _currentState.currentClipIndex,
              );
              _executeStateChange(newState);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInlineSoundSliderRow({
    required IconData icon,
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return Row(
      children: [
        Icon(icon, color: Colors.white, size: 19),
        const SizedBox(width: 8),
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: Colors.white24,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value,
              min: 0,
              max: 1,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${(value * 100).round()}%',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  void _enterBrightnessMode({
    String reason = 'toolbar',
    String? fromMode,
    bool forceOpen = false,
  }) {
    if (_clips.isEmpty) return;
    if (_isTransformModeActive) {
      _enterTransformMode();
    }
    final enteringFrom = fromMode ?? _getBrightnessTransitionFromMode();
    final willEnter = forceOpen || !_isBrightnessMode;

    if (forceOpen && _isBrightnessDragging) {
      _commitBrightnessGesture();
    }

    setState(() {
      if (_bottomInlinePanel != _BottomInlinePanel.none) {
        _bottomInlinePanel = _BottomInlinePanel.none;
      }
      _isBrightnessMode = willEnter;
      _isBrightnessDragging = false;
      _showBrightnessNumericLabel =
          willEnter &&
          (_brightnessAdjustments[_selectedBrightnessProperty] ?? 0.0) != 0.0;
    });

    if (willEnter) {
      _e3SessionId = 'E3_${DateTime.now().millisecondsSinceEpoch}';
      _e3Seq = 0;
      _traceBrightnessEvent(
        'brightness_mode_enter',
        'reason=$reason from=$enteringFrom forceOpen=${forceOpen ? 'true' : 'false'}',
        property: _selectedBrightnessProperty,
        value: _brightnessAdjustments[_selectedBrightnessProperty] ?? 0.0,
        dragging: _isBrightnessDragging,
        showLabel: _showBrightnessNumericLabel,
      );
    } else {
      _traceBrightnessEvent(
        'brightness_mode_exit',
        'reason=$reason from=$enteringFrom',
        property: _selectedBrightnessProperty,
        value: _brightnessAdjustments[_selectedBrightnessProperty] ?? 0.0,
        dragging: _isBrightnessDragging,
        showLabel: _showBrightnessNumericLabel,
      );
    }
  }

  void _scheduleBrightnessPanelFrame() {
    if (!mounted || _isDisposed) return;
    if (_brightnessPanelFrameScheduled) return;
    _brightnessPanelFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _brightnessPanelFrameScheduled = false;
      if (!mounted || _isDisposed) return;
      setState(() {});
    });
  }

  List<MapEntry<String, String>> get _brightnessProperties => const [
    MapEntry('brightness', '밝기'),
    MapEntry('exposure', '노출'),
    MapEntry('contrast', '대비'),
    MapEntry('highlights', '하이라이트'),
    MapEntry('shadows', '그림자'),
    MapEntry('saturation', '채도'),
    MapEntry('tint', '틴트'),
    MapEntry('temperature', '색온도'),
    MapEntry('sharpness', '선명도'),
    MapEntry('clarity', '명료도'),
  ];

  void _startBrightnessGesture() {
    final property = _selectedBrightnessProperty;
    final previousValue = (_brightnessAdjustments[property] ?? 0.0).clamp(
      -100.0,
      100.0,
    );
    _brightnessGestureBaseState = _currentState.copy();
    _brightnessGestureDirty = false;
    setState(() {
      _isBrightnessDragging = true;
      _showBrightnessNumericLabel = true;
    });
    _traceBrightnessEvent(
      'brightness_gesture_start',
      'start baseline captured',
      property: property,
      value: previousValue,
      dragging: true,
      showLabel: true,
    );
  }

  void _commitBrightnessGesture() {
    final property = _selectedBrightnessProperty;
    final valueBefore = (_brightnessAdjustments[property] ?? 0.0).clamp(
      -100.0,
      100.0,
    );
    if (!_brightnessGestureDirty || _brightnessGestureBaseState == null) {
      _brightnessGestureBaseState = null;
      _brightnessGestureDirty = false;
      _isBrightnessDragging = false;
      _traceBrightnessEvent(
        'brightness_gesture_commit_skipped',
        'gesture had no dirty diff',
        property: property,
        value: valueBefore,
        dragging: false,
      );
      return;
    }
    final oldState = _brightnessGestureBaseState!;
    final newState = _currentState.copy();
    _brightnessGestureBaseState = null;
    _brightnessGestureDirty = false;
    _isBrightnessDragging = false;
    final committedValue = (_brightnessAdjustments[property] ?? 0.0).clamp(
      -100.0,
      100.0,
    );
    _traceBrightnessEvent(
      'brightness_gesture_commit',
      'commit transition',
      property: property,
      value: valueBefore,
      nextValue: committedValue,
      dragging: false,
      showLabel: _showBrightnessNumericLabel,
    );
    _executeStateTransition(oldState, newState);
  }

  Widget _buildInlineRulerScale({
    required int divisions,
    int majorStep = 5,
    double height = 16,
  }) {
    final safeDivisions = divisions <= 0 ? 1 : divisions;
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Stack(
            children: List.generate(safeDivisions + 1, (index) {
              final ratio = index / safeDivisions;
              final left = width * ratio;
              final isMajor = index % majorStep == 0;
              return Positioned(
                left: left,
                child: Container(
                  width: 1,
                  height: isMajor ? height : (height * 0.62),
                  color: isMajor ? Colors.white70 : Colors.white24,
                ),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _buildInlineRulerControl({
    required double value,
    required double minValue,
    required double maxValue,
    required int divisions,
    required ValueChanged<double> onChanged,
    required VoidCallback onInteractionStart,
    required VoidCallback onInteractionEnd,
  }) {
    final safeMin = minValue;
    final safeMax = maxValue;
    final safeDivisions = divisions <= 0 ? 1 : divisions;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width <= 0) return const SizedBox.shrink();

        final clamped = value.clamp(safeMin, safeMax);
        final range = safeMax - safeMin;
        final ratio = range == 0 ? 0.0 : ((clamped - safeMin) / range);
        final thumbLeft = (width * ratio).clamp(0.0, width);
        final centerRatio = range == 0
            ? 0.5
            : safeMin <= 0 && safeMax >= 0
            ? (-safeMin) / range
            : 0.5;

        void updateFromX(double x) {
          final clampedX = x.clamp(0.0, width);
          final raw = safeMin + (range * (clampedX / width));
          final step = range / safeDivisions;
          final snapped = ((raw - safeMin) / step).round() * step + safeMin;
          onChanged(snapped.clamp(safeMin, safeMax));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) {
            onInteractionStart();
            updateFromX(details.localPosition.dx);
          },
          onHorizontalDragUpdate: (details) {
            updateFromX(details.localPosition.dx);
          },
          onHorizontalDragEnd: (_) {
            onInteractionEnd();
          },
          onTapDown: (details) {
            onInteractionStart();
            updateFromX(details.localPosition.dx);
            onInteractionEnd();
          },
          child: SizedBox(
            height: 30,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _buildInlineRulerScale(
                    divisions: safeDivisions,
                    majorStep: 5,
                    height: 12,
                  ),
                ),
                Positioned(
                  left: (width * centerRatio) - 0.5,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 1, color: Colors.white38),
                ),
                Positioned(
                  left: thumbLeft - 6,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFF2F20D),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x7F000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBrightnessInlinePanel() {
    final key = _selectedBrightnessProperty;
    final currentValue = (_brightnessAdjustments[key] ?? 0.0).clamp(
      -100.0,
      100.0,
    );
    const minValue = -100.0;
    const maxValue = 100.0;

    return Container(
      height: _inlineModePanelHeight,
      margin: EdgeInsets.fromLTRB(
        _inlineModePanelSidePadding,
        _inlineModePanelSpacing,
        _inlineModePanelSidePadding,
        _inlineModePanelSpacing,
      ),
      padding: EdgeInsets.fromLTRB(
        _inlineModePanelSidePadding,
        _inlineModePanelVerticalPadding,
        _inlineModePanelSidePadding,
        _inlineModePanelVerticalPadding,
      ),
      decoration: _inlineModePanelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: _inlineModeChipRowHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _brightnessProperties.length,
              separatorBuilder: (_, index) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final property = _brightnessProperties[index];
                final selected = property.key == _selectedBrightnessProperty;
                final displayedValue =
                    (_brightnessAdjustments[property.key] ?? 0.0).clamp(
                      -100.0,
                      100.0,
                    );
                return InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () {
                    final propertyValue =
                        (_brightnessAdjustments[property.key] ?? 0.0).clamp(
                          -100.0,
                          100.0,
                        );
                    final previousProperty = _selectedBrightnessProperty;
                    final previousValue =
                        (_brightnessAdjustments[previousProperty] ?? 0.0).clamp(
                          -100.0,
                          100.0,
                        );
                    final nextShowLabel = propertyValue != 0.0;
                    if (_isBrightnessDragging) {
                      _commitBrightnessGesture();
                    }
                    _traceBrightnessEvent(
                      'brightness_property_tap_handler',
                      'before setState',
                      property: property.key,
                      value: previousValue,
                      nextValue: propertyValue,
                      dragging: _isBrightnessDragging,
                      showLabel: nextShowLabel,
                    );
                    setState(() {
                      _selectedBrightnessProperty = property.key;
                      _isBrightnessDragging = false;
                      _showBrightnessNumericLabel = nextShowLabel;
                    });
                    _traceBrightnessEvent(
                      'brightness_property_tap',
                      'post setState',
                      property: property.key,
                      value: previousValue,
                      nextValue: propertyValue,
                      dragging: _isBrightnessDragging,
                      showLabel: _showBrightnessNumericLabel,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF2B8CEE)
                          : Colors.white12,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF9FD0FF)
                            : Colors.white24,
                      ),
                    ),
                    child: Text(
                      selected && _showBrightnessNumericLabel
                          ? displayedValue.toStringAsFixed(0)
                          : property.value,
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _buildInlineRulerControl(
              value: currentValue,
              minValue: minValue,
              maxValue: maxValue,
              divisions: 200,
              onChanged: (val) {
                _brightnessAdjustments[_selectedBrightnessProperty] = val;
                _brightnessGestureDirty = true;
                _traceBrightnessEvent(
                  'brightness_ruler_change',
                  'onChanged',
                  property: _selectedBrightnessProperty,
                  value: val,
                  dragging: _isBrightnessDragging,
                  showLabel: _showBrightnessNumericLabel,
                );
                _scheduleBrightnessPanelFrame();
              },
              onInteractionStart: () {
                if (!_isBrightnessDragging) {
                  _startBrightnessGesture();
                } else {
                  _traceBrightnessEvent(
                    'brightness_ruler_start_while_dragging',
                    'interactionStart called while dragging flag true',
                    property: _selectedBrightnessProperty,
                    value:
                        _brightnessAdjustments[_selectedBrightnessProperty] ??
                        0.0,
                    dragging: _isBrightnessDragging,
                    showLabel: _showBrightnessNumericLabel,
                  );
                }
                _traceBrightnessEvent(
                  'brightness_ruler_interaction_start',
                  'onInteractionStart',
                  property: _selectedBrightnessProperty,
                  value:
                      _brightnessAdjustments[_selectedBrightnessProperty] ??
                      0.0,
                  dragging: _isBrightnessDragging,
                  showLabel: _showBrightnessNumericLabel,
                );
              },
              onInteractionEnd: () {
                _commitBrightnessGesture();
                final propertyValue =
                    (_brightnessAdjustments[_selectedBrightnessProperty] ?? 0.0)
                        .clamp(-100.0, 100.0);
                setState(() {
                  _isBrightnessDragging = false;
                  _showBrightnessNumericLabel = propertyValue != 0.0;
                });
                _traceBrightnessEvent(
                  'brightness_ruler_interaction_end',
                  'post commit',
                  property: _selectedBrightnessProperty,
                  value: propertyValue,
                  dragging: _isBrightnessDragging,
                  showLabel: _showBrightnessNumericLabel,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineSection() {
    if (_isTransformModeActive || _isBrightnessMode) {
      return const SizedBox.shrink();
    }

    final double modePanelHeight = _isTrimMode ? _inlineModePanelHeight : 90.0;

    // Trim Mode: Use ListView for variable widths & context
    if (_isTrimMode && _clips.isNotEmpty) {
      final screenWidth = MediaQuery.of(context).size.width;
      final horizontalPadding = (screenWidth - (screenWidth * 0.7)) / 2;

      return SizedBox(
        height: modePanelHeight,
        child: ListView.separated(
          controller: _timelineScrollController,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          scrollDirection: Axis.horizontal,
          itemCount: _clips.length,
          separatorBuilder: (ctx, idx) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final clip = _clips[index];
            final isSelected = index == _currentClipIndex;

            // Expanded item for selected clip
            if (isSelected) {
              _ensureTrimUiStateForCurrentClip();
              final notifier = _trimUiStateNotifier;
              if (notifier == null) {
                return _buildExpandedTimelineItem(
                  context,
                  clip,
                  _buildTrimUiStateForClip(clip),
                );
              }
              return ValueListenableBuilder<_TrimUiState>(
                valueListenable: notifier,
                builder: (context, uiState, _) {
                  return _buildExpandedTimelineItem(context, clip, uiState);
                },
              );
            }

            // Standard thumbnail for others
            return Opacity(
              opacity: 0.5, // Dim inactive clips
              child: Container(
                width: 70,
                height: 70,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey[300],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: FutureBuilder<Uint8List?>(
                    future: Provider.of<VideoManager>(
                      context,
                      listen: false,
                    ).getThumbnail(clip.path),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data != null) {
                        return Image.memory(snapshot.data!, fit: BoxFit.cover);
                      }
                      return const Center(
                        child: Icon(Icons.movie, color: Colors.black26),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    // Normal Mode: ReorderableListView
    return SizedBox(
      height: modePanelHeight,
      child: ReorderableListView.builder(
        proxyDecorator: (Widget child, int index, Animation<double> animation) {
          return AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final t = Curves.easeOut.transform(animation.value);
              return Transform.translate(
                offset: Offset(0, -6 * t),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.24),
                        blurRadius: 14,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: child,
                ),
              );
            },
          );
        },
        scrollController: _timelineScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: _clips.length,
        onReorder: (oldIndex, newIndex) {
          if (oldIndex == newIndex) return;
          if (oldIndex < newIndex) {
            newIndex -= 1;
          }

          final baseState = _currentState;
          final reorderedClips = baseState.clips
              .map((clip) => clip.copyWith())
              .toList();
          final moved = reorderedClips.removeAt(oldIndex);
          reorderedClips.insert(newIndex, moved);

          var nextClipIndex = baseState.currentClipIndex;
          if (nextClipIndex == oldIndex) {
            nextClipIndex = newIndex;
          } else if (oldIndex < nextClipIndex && newIndex >= nextClipIndex) {
            nextClipIndex -= 1;
          } else if (oldIndex > nextClipIndex && newIndex <= nextClipIndex) {
            nextClipIndex += 1;
          }

          final nextState = EditorState(
            subtitles: baseState.subtitles,
            stickers: baseState.stickers,
            filter: baseState.filter,
            filterOpacity: baseState.filterOpacity,
            brightnessAdjustments: baseState.brightnessAdjustments,
            bgmPath: baseState.bgmPath,
            videoVolume: baseState.videoVolume,
            bgmVolume: baseState.bgmVolume,
            clips: reorderedClips,
            currentClipIndex: reorderedClips.isEmpty
                ? 0
                : nextClipIndex.clamp(0, reorderedClips.length - 1),
          );
          _executeStateChange(nextState);
        },
        itemBuilder: (context, index) {
          final clip = _clips[index];
          final isSelected = index == _currentClipIndex;
          return GestureDetector(
            key: ValueKey(clip.id),
            onTap: () async {
              if (_isPlaybackLockedForEditing) {
                return;
              }
              if (_currentClipIndex != index) {
                await _loadClip(index);
                if (_controller != null && !_isDisposed) {
                  _controller!.play();
                }
              }
            },
            child: Container(
              width: 70,
              height: 70,
              margin: const EdgeInsets.only(right: 8, top: 10, bottom: 10),
              decoration: BoxDecoration(
                border: isSelected
                    ? Border.all(color: Colors.blue, width: 3)
                    : null,
                borderRadius: BorderRadius.circular(12),
                color: Colors.grey[300],
                boxShadow: [
                  if (isSelected)
                    BoxShadow(
                      color: Colors.blue.withValues(alpha: 0.3),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                ],
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: FutureBuilder<Uint8List?>(
                      future: Provider.of<VideoManager>(
                        context,
                        listen: false,
                      ).getThumbnail(clip.path),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data != null) {
                          return Image.memory(
                            snapshot.data!,
                            fit: BoxFit.cover,
                          );
                        }
                        return const Center(
                          child: Icon(Icons.movie, color: Colors.black26),
                        );
                      },
                    ),
                  ),
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Builder(
                        builder: (ctx) {
                          // Use _clipDurations if available, otherwise fall back to clip times
                          final int durationSec;
                          final clipTrimDuration =
                              clip.endTime - clip.startTime;
                          final Duration durationToDisplay;
                          if (clipTrimDuration != Duration.zero) {
                            durationToDisplay = clipTrimDuration;
                          } else if (index < _clipDurations.length &&
                              _clipDurations[index] != Duration.zero) {
                            durationToDisplay = _clipDurations[index];
                          } else {
                            durationToDisplay = Duration.zero;
                          }

                          if (durationToDisplay != Duration.zero) {
                            final totalMs = durationToDisplay.inMilliseconds;
                            durationSec = (totalMs ~/ 1000).clamp(0, 999999);
                          } else {
                            durationSec = -1; // Not yet loaded
                          }
                          return Text(
                            durationSec >= 0 ? '${durationSec}s' : '...',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (_missingClipIndexes.contains(index))
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD32F2F),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Missing #${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Material(
                      color: _missingClipIndexes.contains(index)
                          ? const Color(0xFFD32F2F)
                          : Colors.black45,
                      borderRadius: BorderRadius.circular(999),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => _confirmAndRemoveClip(index),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Expanded timeline item for selected clip in trim mode
  Widget _buildExpandedTimelineItem(
    BuildContext context,
    VlogClip clip,
    _TrimUiState uiState,
  ) {
    final startMs = uiState.startMs;
    final endMs = uiState.endMs;
    final maxMs = uiState.maxMs;

    final startPercent = (startMs / maxMs).clamp(0.0, 1.0);
    final endPercent = (endMs / maxMs).clamp(0.0, 1.0);
    final scrubberPercent = (uiState.currentMs / maxMs).clamp(0.0, 1.0);

    // Width of the expanded item (Reduced to show adjacent clips)
    final double itemWidth = MediaQuery.of(context).size.width * 0.7;
    final double height = 70.0;

    if (itemWidth.isNaN || maxMs.isNaN || itemWidth <= 0 || maxMs <= 0) {
      return Container(height: 90, color: Colors.red);
    }

    return Container(
      width: itemWidth,
      height: 90,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: FutureBuilder<List<Uint8List>>(
        future: _getTrimTimelineFuture(clip, maxMs.toInt()),
        builder: (context, snapshot) {
          final thumbs = snapshot.data ?? const <Uint8List>[];
          return Builder(
            builder: (timelineContext) => Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: thumbs.isEmpty
                        ? Container(
                            color: Colors.grey[800],
                            child: const Center(
                              child: Icon(Icons.movie, color: Colors.white24),
                            ),
                          )
                        : Row(
                            children: thumbs
                                .map(
                                  (thumb) => Expanded(
                                    child: Image.memory(
                                      thumb,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                  ),
                ),
                Positioned.fill(
                  child: Row(
                    children: [
                      Container(
                        width: itemWidth * startPercent,
                        height: height,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.58),
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(12),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: itemWidth * (1 - endPercent),
                        height: height,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.58),
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: itemWidth * startPercent,
                  width: itemWidth * (endPercent - startPercent),
                  height: height,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFFF2F20D),
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                Positioned(
                  left: itemWidth * startPercent - 12,
                  top: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (details) {
                      if (_activeTrimTimelineInteraction ==
                          _TrimTimelineInteraction.playhead) {
                        return;
                      }
                      final timelineBox =
                          timelineContext.findRenderObject() as RenderBox?;
                      if (timelineBox != null) {
                        final localX = timelineBox
                            .globalToLocal(details.globalPosition)
                            .dx;
                        if ((localX - itemWidth * scrubberPercent).abs() <=
                            18) {
                          return;
                        }
                      }
                      if (_isTrimPlayheadDragging) {
                        return;
                      }
                      if (_activeTrimTimelineInteraction ==
                          _TrimTimelineInteraction.endHandle) {
                        _commitTrimGesture();
                      }
                      _setTrimTimelineInteraction(
                        _TrimTimelineInteraction.startHandle,
                      );
                      _isTrimStartHandleDragging = true;
                      _isTrimEndHandleDragging = false;
                      _startTrimGesture();
                    },
                    onHorizontalDragUpdate: (details) {
                      if (_activeTrimTimelineInteraction !=
                          _TrimTimelineInteraction.startHandle) {
                        return;
                      }
                      final state = _trimUiStateNotifier?.value ?? uiState;
                      double newStartMs =
                          state.startMs +
                          (details.delta.dx / itemWidth * state.maxMs);
                      newStartMs = newStartMs.clamp(0.0, state.endMs - 500);
                      if ((newStartMs - clip.startTime.inMilliseconds).abs() <
                          4) {
                        return;
                      }
                      final newStart = Duration(
                        milliseconds: newStartMs.toInt(),
                      );
                      if (newStart == clip.startTime) return;
                      clip.startTime = newStart;
                      _trimGestureDirty = true;
                      final currentClamped = state.currentMs < newStartMs
                          ? newStartMs
                          : state.currentMs;
                      _trimUiStateNotifier?.value = state.copyWith(
                        startMs: newStartMs,
                        currentMs: currentClamped,
                      );
                      _scheduleTrimPreviewSeek(
                        newStart,
                        reason: _TrimTimelineInteraction.startHandle,
                      );
                      _requestTrimUiRebuild();
                    },
                    onHorizontalDragEnd: (_) {
                      if (_activeTrimTimelineInteraction !=
                          _TrimTimelineInteraction.startHandle) {
                        return;
                      }
                      _isTrimStartHandleDragging = false;
                      _setTrimTimelineInteraction(
                        _TrimTimelineInteraction.none,
                      );
                      _commitTrimGesture();
                    },
                    child: Container(
                      width: 24,
                      height: height,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF2F20D),
                        borderRadius: BorderRadius.horizontal(
                          left: Radius.circular(8),
                        ),
                      ),
                      child: const Center(
                        child: Icon(Icons.chevron_left, size: 16),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: itemWidth * endPercent - 12,
                  top: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (details) {
                      if (_activeTrimTimelineInteraction ==
                          _TrimTimelineInteraction.playhead) {
                        return;
                      }
                      final timelineBox =
                          timelineContext.findRenderObject() as RenderBox?;
                      if (timelineBox != null) {
                        final localX = timelineBox
                            .globalToLocal(details.globalPosition)
                            .dx;
                        if ((localX - itemWidth * scrubberPercent).abs() <=
                            18) {
                          return;
                        }
                      }
                      if (_isTrimPlayheadDragging) {
                        return;
                      }
                      if (_activeTrimTimelineInteraction ==
                          _TrimTimelineInteraction.startHandle) {
                        _commitTrimGesture();
                      }

                      _setTrimTimelineInteraction(
                        _TrimTimelineInteraction.endHandle,
                      );
                      _isTrimEndHandleDragging = true;
                      _isTrimStartHandleDragging = false;
                      _startTrimGesture();
                    },
                    onHorizontalDragUpdate: (details) {
                      if (_activeTrimTimelineInteraction !=
                          _TrimTimelineInteraction.endHandle) {
                        return;
                      }
                      final state = _trimUiStateNotifier?.value ?? uiState;
                      double newEndMs =
                          state.endMs +
                          (details.delta.dx / itemWidth * state.maxMs);
                      newEndMs = newEndMs.clamp(
                        state.startMs + 500,
                        state.maxMs,
                      );
                      if ((newEndMs - clip.endTime.inMilliseconds).abs() < 4) {
                        return;
                      }
                      final newEnd = Duration(milliseconds: newEndMs.toInt());
                      if (newEnd == clip.endTime) return;
                      clip.endTime = newEnd;
                      _trimGestureDirty = true;
                      final currentClamped = state.currentMs > newEndMs
                          ? newEndMs
                          : state.currentMs;
                      _trimUiStateNotifier?.value = state.copyWith(
                        endMs: newEndMs,
                        currentMs: currentClamped,
                      );
                      _scheduleTrimPreviewSeek(
                        newEnd,
                        reason: _TrimTimelineInteraction.endHandle,
                      );
                      _requestTrimUiRebuild();
                    },
                    onHorizontalDragEnd: (_) {
                      if (_activeTrimTimelineInteraction !=
                          _TrimTimelineInteraction.endHandle) {
                        return;
                      }
                      _isTrimEndHandleDragging = false;
                      _setTrimTimelineInteraction(
                        _TrimTimelineInteraction.none,
                      );
                      _commitTrimGesture();
                    },
                    child: Container(
                      width: 24,
                      height: height,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF2F20D),
                        borderRadius: BorderRadius.horizontal(
                          right: Radius.circular(8),
                        ),
                      ),
                      child: const Center(
                        child: Icon(Icons.chevron_right, size: 16),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: (itemWidth * scrubberPercent) - 14,
                  top: 0,
                  bottom: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (details) {
                      if (_activeTrimTimelineInteraction ==
                          _TrimTimelineInteraction.startHandle) {
                        _commitTrimGesture();
                      }
                      if (_activeTrimTimelineInteraction ==
                          _TrimTimelineInteraction.endHandle) {
                        _commitTrimGesture();
                      }

                      final state = _trimUiStateNotifier?.value ?? uiState;
                      _setTrimTimelineInteraction(
                        _TrimTimelineInteraction.playhead,
                      );
                      _startTrimGesture();
                      _isTrimPlayheadDragging = true;
                      _isTrimStartHandleDragging = false;
                      _isTrimEndHandleDragging = false;

                      final timelineBox =
                          timelineContext.findRenderObject() as RenderBox?;
                      if (timelineBox == null) return;
                      final localX = timelineBox
                          .globalToLocal(details.globalPosition)
                          .dx;
                      final nextCurrentMs = _trimTimelineMsFromLocalX(
                        localX: localX,
                        state: state,
                        timelineWidth: itemWidth,
                      );
                      _trimUiStateNotifier?.value = state.copyWith(
                        currentMs: nextCurrentMs,
                      );
                      _trimGestureDirty = true;
                      _scheduleTrimPreviewSeek(
                        Duration(milliseconds: nextCurrentMs.toInt()),
                        reason: _TrimTimelineInteraction.playhead,
                      );
                      _requestTrimUiRebuild();
                    },
                    onHorizontalDragUpdate: (details) {
                      if (_activeTrimTimelineInteraction !=
                          _TrimTimelineInteraction.playhead) {
                        return;
                      }
                      final state = _trimUiStateNotifier?.value ?? uiState;
                      final timelineBox =
                          timelineContext.findRenderObject() as RenderBox?;
                      if (timelineBox == null) return;
                      final localX = timelineBox
                          .globalToLocal(details.globalPosition)
                          .dx;
                      final nextCurrentMs = _trimTimelineMsFromLocalX(
                        localX: localX,
                        state: state,
                        timelineWidth: itemWidth,
                      );
                      _trimUiStateNotifier?.value = state.copyWith(
                        currentMs: nextCurrentMs,
                      );
                      _trimGestureDirty = true;
                      _scheduleTrimPreviewSeek(
                        Duration(milliseconds: nextCurrentMs.toInt()),
                        reason: _TrimTimelineInteraction.playhead,
                      );
                      _requestTrimUiRebuild();
                    },
                    onHorizontalDragEnd: (_) {
                      if (_activeTrimTimelineInteraction !=
                          _TrimTimelineInteraction.playhead) {
                        return;
                      }
                      _isTrimPlayheadDragging = false;
                      _setTrimTimelineInteraction(
                        _TrimTimelineInteraction.none,
                      );
                      _commitTrimGesture();
                    },
                    onTapDown: (details) {
                      if (_isTrimStartHandleDragging ||
                          _isTrimEndHandleDragging) {
                        _commitTrimGesture();
                        _isTrimStartHandleDragging = false;
                        _isTrimEndHandleDragging = false;
                      }
                      _setTrimTimelineInteraction(
                        _TrimTimelineInteraction.playhead,
                      );
                      _startTrimGesture();
                      _isTrimPlayheadDragging = false;
                      _isTrimStartHandleDragging = false;
                      _isTrimEndHandleDragging = false;
                      final state = _trimUiStateNotifier?.value ?? uiState;
                      final timelineBox =
                          timelineContext.findRenderObject() as RenderBox?;
                      if (timelineBox == null) return;
                      final localX = timelineBox
                          .globalToLocal(details.globalPosition)
                          .dx;
                      final targetMs = _trimTimelineMsFromLocalX(
                        localX: localX,
                        state: state,
                        timelineWidth: itemWidth,
                      );
                      _trimUiStateNotifier?.value = state.copyWith(
                        currentMs: targetMs,
                      );
                      _trimGestureDirty = true;
                      _scheduleTrimPreviewSeek(
                        Duration(milliseconds: targetMs.toInt()),
                        reason: _TrimTimelineInteraction.playhead,
                      );
                      _requestTrimUiRebuild();
                    },
                    child: Container(
                      width: 28,
                      alignment: Alignment.center,
                      child: Center(
                        child: Container(
                          width: 2,
                          height: 70,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black45,
                                blurRadius: 3,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<List<Uint8List>> _getTrimTimelineFuture(
    VlogClip clip,
    int durationMs,
  ) {
    final clipPath = clip.path;
    final count = VideoManager.trimTimelineThumbCount;
    final key = '$clipPath|$durationMs|$count';
    final cached = _trimTimelineFutureCache[key];
    if (cached != null) {
      return cached;
    }

    final future = _videoManager.getTimelineThumbnails(
      clipPath,
      durationMs,
      count,
      clip: clip,
    );
    _trimTimelineFutureCache[key] = future;
    return future;
  }

  // 내보내기 및 유틸

  void _togglePlayPause() {
    if (_playbackLockedByTransform) {
      Fluttertoast.showToast(msg: '편집 모드에서 재생이 잠김입니다.');
      return;
    }
    if (_controller == null || !_isInitialized) return;
    final shouldPlay = !_isPlaying;

    if (shouldPlay) {
      _controller!.play();
      _bgmController?.play();
    } else {
      _controller!.pause();
      _bgmController?.pause();
    }

    if (mounted && !_isDisposed) {
      setState(() {
        _isPlaying = shouldPlay;
      });
    }
  }

  // 'Done' / 'Export' 버튼 클릭 시 호출
  void _handleExport() {
    // Safety Net: Check all files before export dialog
    for (final clip in _clips) {
      if (!File(clip.path).existsSync()) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text(
              "Error",
              style: TextStyle(color: Colors.redAccent),
            ),
            content: const Text(
              "원본 파일이 손상되어 내보낼 수 없습니다.\n(Source file missing)",
              style: TextStyle(color: Colors.white),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              ),
            ],
          ),
        );
        return;
      }
    }
    _showExportDialog();
  }

  void _showExportDialog() {
    final userStatus = Provider.of<UserStatusManager>(context, listen: false);
    final userTier = userStatus.currentTier;
    String selectedQuality = clampExportQualityForTier(
      requestedQuality: normalizeExportQuality(widget.project.quality),
      tier: userTier,
    );

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: const Text(
                "Export Quality",
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildQualityOption(
                    label: "720p (Basic)",
                    value: kQuality720p,
                    selected: selectedQuality == kQuality720p,
                    enabled: true,
                    onChanged: (val) {
                      setStateDialog(() => selectedQuality = val);
                      _updateProjectQuality(val);
                    },
                  ),
                  _buildQualityOption(
                    label: "1080p",
                    value: kQuality1080p,
                    selected: selectedQuality == kQuality1080p,
                    enabled: userStatus.isStandardOrAbove(),
                    onChanged: (val) {
                      setStateDialog(() => selectedQuality = val);
                      _updateProjectQuality(val);
                    },
                  ),
                  _buildQualityOption(
                    label: "4K",
                    value: kQuality4k,
                    selected: selectedQuality == kQuality4k,
                    enabled: userStatus.isPremium(),
                    onChanged: (val) {
                      setStateDialog(() => selectedQuality = val);
                      _updateProjectQuality(val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _performNativeExport(
                      clampExportQualityForTier(
                        requestedQuality: selectedQuality,
                        tier: userTier,
                      ),
                    );
                  },
                  child: const Text("Export"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _updateProjectQuality(String newQuality) {
    final normalized = normalizeExportQuality(newQuality);
    if (widget.project.quality != normalized) {
      widget.project.quality = normalized;
      Provider.of<VideoManager>(
        context,
        listen: false,
      ).saveProject(widget.project);
    }
  }

  Widget _buildQualityOption({
    required String label,
    required String value,
    required bool selected,
    required bool enabled,
    required ValueChanged<String> onChanged,
  }) {
    return ListTile(
      title: Text(
        label,
        style: TextStyle(color: enabled ? Colors.white : Colors.white24),
      ),
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: enabled
            ? (selected ? Colors.blueAccent : Colors.white)
            : Colors.white24,
      ),
      trailing: enabled
          ? null
          : const Icon(Icons.lock, size: 16, color: Colors.white24),
      onTap: enabled ? () => onChanged(value) : null,
    );
  }

  Future<void> _performNativeExport(String quality) async {
    final videoManager = Provider.of<VideoManager>(context, listen: false);
    final userStatus = Provider.of<UserStatusManager>(context, listen: false);
    final userTier = userStatus.currentTier;
    final finalQuality = clampExportQualityForTier(
      requestedQuality: quality,
      tier: userTier,
    );
    final userTierKey = userTierKeyFromManager(userStatus);

    await _prepareForExportRendering();
    if (!mounted) return;

    debugPrint('[EditScreen][Export] open loading dialog mounted=$mounted');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        backgroundColor: Colors.black87,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.blueAccent),
            SizedBox(height: 20),
            Text("Rendering Vlog... 🎬", style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );

    try {
      // Sync State to Project before Export
      // widget.project.clips is already updated via reference in _clips (if we modified objects directly)
      // If _clips are copies, we'd need to sync back.
      // Assuming _clips are references or we need to update project.clips:
      widget.project.clips = _clips;

      widget.project.bgmPath = _currentState.bgmPath;
      widget.project.bgmVolume = _currentState.bgmVolume;
      widget.project.quality = finalQuality;

      await videoManager.saveProject(widget.project);

      final resultPath = await videoManager.exportVlog(
        clips: widget.project.clips,
        audioConfig: widget.project.audioConfig,
        bgmPath: widget.project.bgmPath,
        bgmVolume: widget.project.bgmVolume,
        quality: widget.project.quality,
        userTier: userTierKey,
      );

      if (!mounted) return;
      debugPrint('[EditScreen][Export] close loading dialog mounted=$mounted');
      Navigator.pop(context); // Close Loader

      if (resultPath != null) {
        Fluttertoast.showToast(msg: "Vlog Saved Successfully! 🎉");
        Navigator.pop(context, true); // Return success
      } else {
        Fluttertoast.showToast(msg: "Export Failed. Please try again.");
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      Fluttertoast.showToast(msg: "Error: $e");
    }
  }

  // ignore: unused_element
  void _showSoundMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: 420,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              decoration: const BoxDecoration(
                color: Color(0xFFF5F7F9),
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD9E0E7),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'AUDIO MIXER',
                          style: TextStyle(
                            color: _textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setModalState(() {
                            _videoVolume = 1.0;
                            _bgmVolume = 0.5;
                          });
                          _updateVolumes();
                          final newState = EditorState(
                            subtitles: _currentState.subtitles,
                            stickers: _currentState.stickers,
                            filter: _currentState.filter,
                            filterOpacity: _currentState.filterOpacity,
                            brightnessAdjustments:
                                _currentState.brightnessAdjustments,
                            bgmPath: _currentState.bgmPath,
                            videoVolume: 1.0,
                            bgmVolume: 0.5,
                            clips: _currentState.clips,
                            currentClipIndex: _currentState.currentClipIndex,
                          );
                          _executeStateChange(newState);
                        },
                        child: const Text(
                          'Reset',
                          style: TextStyle(
                            color: _textSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Apply',
                          style: TextStyle(
                            color: _primaryColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.music_note),
                        label: Text(
                          _bgmPath == null ? "Add Music" : "Change Music",
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: _textPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          final result = await FilePicker.platform.pickFiles(
                            type: FileType.audio,
                          );
                          if (result != null &&
                              result.files.single.path != null) {
                            final path = result.files.single.path!;

                            // Update State via Command

                            // But copy doesn't allow changing fields easily as they are final and copy() takes args.
                            // Actually copy() args are optional? Check EditorState.
                            // No, copy() implementation above maps fields.

                            // We need to construct new state manually or update copy() to support overrides better.
                            // Let's use manual construction provided _currentState access.
                            final newState = EditorState(
                              subtitles: _currentState.subtitles,
                              stickers: _currentState.stickers,
                              filter: _currentState.filter,
                              filterOpacity: _currentState.filterOpacity,
                              brightnessAdjustments:
                                  _currentState.brightnessAdjustments,
                              bgmPath: path,
                              videoVolume: _currentState.videoVolume,
                              bgmVolume: _currentState.bgmVolume,
                              clips: _currentState.clips,
                              currentClipIndex: _currentState.currentClipIndex,
                            );

                            _executeStateChange(newState);
                            setModalState(() {}); // Refresh modal UI
                          }
                        },
                      ),
                      if (_bgmPath != null)
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            final newState = EditorState(
                              subtitles: _currentState.subtitles,
                              stickers: _currentState.stickers,
                              filter: _currentState.filter,
                              filterOpacity: _currentState.filterOpacity,
                              brightnessAdjustments:
                                  _currentState.brightnessAdjustments,
                              bgmPath: null,
                              videoVolume: _currentState.videoVolume,
                              bgmVolume: _currentState.bgmVolume,
                              clips: _currentState.clips,
                              currentClipIndex: _currentState.currentClipIndex,
                            );
                            _executeStateChange(newState);
                            setModalState(() {});
                          },
                        ),
                    ],
                  ),
                  if (_bgmPath != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        "Current: ${_bgmPath!.split('/').last}",
                        style: const TextStyle(
                          color: _textSecondary,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                  const SizedBox(height: 16),
                  _buildAudioSliderRow(
                    icon: Icons.graphic_eq,
                    label: 'Original',
                    value: _videoVolume,
                    color: _primaryColor,
                    onChanged: (val) {
                      setModalState(() => _videoVolume = val);
                      _updateVolumes();
                    },
                    onChangeEnd: (val) {
                      final newState = EditorState(
                        subtitles: _currentState.subtitles,
                        stickers: _currentState.stickers,
                        filter: _currentState.filter,
                        filterOpacity: _currentState.filterOpacity,
                        brightnessAdjustments:
                            _currentState.brightnessAdjustments,
                        bgmPath: _currentState.bgmPath,
                        videoVolume: val,
                        bgmVolume: _currentState.bgmVolume,
                        clips: _currentState.clips,
                        currentClipIndex: _currentState.currentClipIndex,
                      );
                      _executeStateChange(newState);
                    },
                  ),
                  const SizedBox(height: 20),
                  _buildAudioSliderRow(
                    icon: Icons.music_note,
                    label: 'BGM',
                    value: _bgmVolume,
                    color: const Color(0xFF6F3CEB),
                    onChanged: (val) {
                      setModalState(() => _bgmVolume = val);
                      _updateVolumes();
                    },
                    onChangeEnd: (val) {
                      final newState = EditorState(
                        subtitles: _currentState.subtitles,
                        stickers: _currentState.stickers,
                        filter: _currentState.filter,
                        filterOpacity: _currentState.filterOpacity,
                        brightnessAdjustments:
                            _currentState.brightnessAdjustments,
                        bgmPath: _currentState.bgmPath,
                        videoVolume: _currentState.videoVolume,
                        bgmVolume: val,
                        clips: _currentState.clips,
                        currentClipIndex: _currentState.currentClipIndex,
                      );
                      _executeStateChange(newState);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAudioSliderRow({
    required IconData icon,
    required String label,
    required double value,
    required Color color,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    final percent = '${(value * 100).round()}%';
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _textPrimary, size: 20),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 66,
          child: Text(
            label,
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: const Color(0xFFDCE4EC),
              inactiveTrackColor: const Color(0xFFE8EEF4),
              thumbColor: Colors.white,
              overlayColor: color.withValues(alpha: 0.12),
            ),
            child: Slider(
              value: value,
              min: 0.0,
              max: 1.0,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            percent,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  void _showCanvasPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            String selectedAspect = widget.project.canvasAspectRatioPreset;
            String selectedBgMode = widget.project.canvasBackgroundMode;
            return Container(
              height: 260,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              decoration: const BoxDecoration(
                color: Color(0xFFF5F7F9),
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD9E0E7),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'CANVAS',
                    style: TextStyle(
                      color: _textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: ['r9_16', 'r1_1', 'r16_9'].map((preset) {
                      final selected = selectedAspect == preset;
                      return ChoiceChip(
                        label: Text(_canvasAspectLabel(preset)),
                        selected: selected,
                        onSelected: (_) {
                          setModalState(() => selectedAspect = preset);
                          final oldState = _currentState.copy();
                          setState(() {
                            widget.project.canvasAspectRatioPreset = preset;
                          });
                          final newState = _currentState.copy();
                          _executeStateTransition(oldState, newState);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Background',
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['crop_fill', 'blur_fill', 'solid_fill'].map((
                      mode,
                    ) {
                      final selected = selectedBgMode == mode;
                      return ChoiceChip(
                        label: Text(mode),
                        selected: selected,
                        onSelected: (_) {
                          setModalState(() => selectedBgMode = mode);
                          final oldState = _currentState.copy();
                          setState(() {
                            widget.project.canvasBackgroundMode = mode;
                          });
                          final newState = _currentState.copy();
                          _executeStateTransition(oldState, newState);
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      builder: (context) {
        return Container(
          height: 150,
          padding: const EdgeInsets.all(20),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: FilterPreset.values.map((filter) {
              return GestureDetector(
                onTap: () {
                  // final newState = _currentState.copy(); // Unused
                  // We need to construct new state.
                  final nextState = EditorState(
                    subtitles: _currentState.subtitles,
                    stickers: _currentState.stickers,
                    filter: filter,
                    filterOpacity: _currentState.filterOpacity,
                    brightnessAdjustments: _currentState.brightnessAdjustments,
                    bgmPath: _currentState.bgmPath,
                    videoVolume: _currentState.videoVolume,
                    bgmVolume: _currentState.bgmVolume,
                    clips: _currentState.clips,
                    currentClipIndex: _currentState.currentClipIndex,
                  );
                  _executeStateChange(nextState);
                  Navigator.pop(context);
                },
                child: Container(
                  width: 80,
                  margin: const EdgeInsets.only(right: 10),
                  color: _selectedFilter == filter
                      ? Colors.blue
                      : Colors.grey[800],
                  child: Center(
                    child: Text(
                      filter.name,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  // Reuse existing methods via StateChangeCommand wrapper logic...
  // For brevity, I'll need to adapt _showAdvancedCaptionDialog similarly.
  // ignore: unused_element
  Future<void> _showAdvancedCaptionDialog({SubtitleModel? editing}) async {
    final controller = TextEditingController(text: editing?.text ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          editing == null ? "Add Subtitle" : "Edit Subtitle",
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Enter text",
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text("Confirm"),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      List<SubtitleModel> nextSubs = List.from(_subtitles);

      if (editing != null) {
        // Update existing
        final index = nextSubs.indexWhere(
          (s) => s.text == editing.text && s.dx == editing.dx,
        ); // Weak ID, but ok for now
        if (index != -1) {
          nextSubs[index] = editing.copy()..text = result;
        }
      } else {
        // Add new
        nextSubs.add(SubtitleModel(text: result, dx: 0.5, dy: 0.5));
      }

      final nextState = EditorState(
        subtitles: nextSubs,
        stickers: _currentState.stickers,
        filter: _currentState.filter,
        filterOpacity: _currentState.filterOpacity,
        brightnessAdjustments: _currentState.brightnessAdjustments,
        bgmPath: _currentState.bgmPath,
        videoVolume: _currentState.videoVolume,
        bgmVolume: _currentState.bgmVolume,
        clips: _currentState.clips,
        currentClipIndex: _currentState.currentClipIndex,
      );
      _executeStateChange(nextState);
    }
  }

  // ignore: unused_element
  void _showStickerLibrary() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: 300,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: _stickerAssets.length,
            itemBuilder: (context, index) {
              final asset = _stickerAssets[index];
              return GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  _addSticker(asset);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Image.asset(asset, fit: BoxFit.contain),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _addSticker(String assetPath) {
    final nextStickers = List<StickerModel>.from(_stickers)
      ..add(StickerModel(imagePath: assetPath, dx: 0.5, dy: 0.5));

    final nextState = EditorState(
      subtitles: _currentState.subtitles,
      stickers: nextStickers,
      filter: _currentState.filter,
      filterOpacity: _currentState.filterOpacity,
      brightnessAdjustments: _currentState.brightnessAdjustments,
      bgmPath: _currentState.bgmPath,
      videoVolume: _currentState.videoVolume,
      bgmVolume: _currentState.bgmVolume,
      clips: _currentState.clips,
      currentClipIndex: _currentState.currentClipIndex,
    );
    _executeStateChange(nextState);
  }

  // Overlay Widgets
  Widget _buildStickerWidget(StickerModel sticker) {
    return Positioned(
      left: sticker.dx * MediaQuery.of(context).size.width,
      top: sticker.dy * MediaQuery.of(context).size.height,
      child: GestureDetector(
        onScaleStart: (details) {
          _tempBaseScale = sticker.scale;
          _startOverlayGesture();
        },
        onScaleUpdate: (details) {
          setState(() {
            // Handle Movement
            final screenW = MediaQuery.of(context).size.width;
            final screenH = MediaQuery.of(context).size.height;

            sticker.dx += details.focalPointDelta.dx / screenW;
            sticker.dy += details.focalPointDelta.dy / screenH;

            // Handle Scaling (Pinch)
            if (details.scale != 1.0) {
              sticker.scale = _tempBaseScale * details.scale;
            }
            _overlayGestureDirty = true;
          });
        },
        onScaleEnd: (details) {
          _commitOverlayGesture();
        },
        child: Image.asset(sticker.imagePath, width: 100 * sticker.scale),
      ),
    );
  }

  Widget _buildSubtitleWidget(SubtitleModel subtitle) {
    return Positioned(
      left: subtitle.dx * MediaQuery.of(context).size.width,
      top: subtitle.dy * MediaQuery.of(context).size.height,
      child: GestureDetector(
        onScaleStart: (details) {
          _tempBaseFontSize = subtitle.fontSize;
          _startOverlayGesture();
        },
        onScaleUpdate: (details) {
          setState(() {
            final screenW = MediaQuery.of(context).size.width;
            final screenH = MediaQuery.of(context).size.height;

            subtitle.dx += details.focalPointDelta.dx / screenW;
            subtitle.dy += details.focalPointDelta.dy / screenH;

            if (details.scale != 1.0) {
              subtitle.fontSize = _tempBaseFontSize * details.scale;
            }
            _overlayGestureDirty = true;
          });
        },
        onScaleEnd: (details) {
          _commitOverlayGesture();
        },
        child: Text(
          subtitle.text,
          style: TextStyle(
            color: subtitle.textColor,
            fontSize: subtitle.fontSize,
            backgroundColor: subtitle.backgroundColor,
          ),
        ),
      ),
    );
  }
}

class _GenericStateCommand implements EditCommand {
  final EditorState oldState;
  final EditorState newState;
  final Function(EditorState) onRestore;

  _GenericStateCommand({
    required this.oldState,
    required this.newState,
    required this.onRestore,
  });

  @override
  void execute() {
    onRestore(newState);
  }

  @override
  void undo() {
    onRestore(oldState);
  }
}
