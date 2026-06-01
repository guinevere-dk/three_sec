import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../managers/video_manager.dart';
import '../models/edit_command.dart';
import '../managers/user_status_manager.dart';
import '../models/vlog_project.dart';
import '../services/cloud_clip_session_resolver.dart';
import '../services/cloud_service.dart';
import '../constants/clip_policy.dart';
import '../utils/brightness_adjustment_policy.dart';
import '../utils/clip_duration_label.dart';
import '../utils/color_filter_preset_policy.dart';
import '../utils/quality_policy.dart';
import 'subscription_management_screen.dart';

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
  final String colorFilterPresetId;
  final double colorFilterIntensity;

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
    this.colorFilterPresetId = kColorFilterPresetNone,
    this.colorFilterIntensity = kColorFilterIntensityDefault,
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
      colorFilterPresetId: colorFilterPresetId,
      colorFilterIntensity: colorFilterIntensity,
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

enum _TransformAngleMode { tilt }

enum _TransformQuickAction { flip, rotate, angle }

enum _BottomInlinePanel { none, sound, trimSpeedPreset, colorFilter }

enum _TrimTimelineInteraction { none, playhead, startHandle, endHandle }

enum _CloudClipEditState {
  cloudResolving,
  cloudBuffering,
  cloudReady,
  cloudFailed,
}

enum _ProjectSaveUiState {
  idle,
  saving,
  localSaved,
  cloudSaved,
  cloudFailed,
  retrying,
}

class _ColorFilterMoodMeta {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradientColors;
  final Color accentColor;

  const _ColorFilterMoodMeta({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradientColors,
    required this.accentColor,
  });
}

class _ExportClipResolveException implements Exception {
  final int index;
  final String message;
  final CloudClipResolveFailureCode? cloudFailureCode;

  const _ExportClipResolveException({
    required this.index,
    required this.message,
    this.cloudFailureCode,
  });

  @override
  String toString() => message;
}

// 메인 편집 화면

class _ExportPreflightException implements Exception {
  final String code;
  final String message;

  const _ExportPreflightException(this.code, this.message);

  @override
  String toString() => '$code: $message';
}

class VideoEditScreen extends StatefulWidget {
  final VlogProject project;
  final String? mergeSessionId;

  const VideoEditScreen({
    super.key,
    required this.project,
    this.mergeSessionId,
  });

  @override
  State<VideoEditScreen> createState() => _VideoEditScreenState();
}

class _VideoEditScreenState extends State<VideoEditScreen> {
  static const Color _editorBackground = Color(0xFF0E141D);
  static const Color _editorGlassSurface = Color(0xB3192536);
  static const Color _editorHeaderSurface = Color(0xCC121A24);
  static const Color _editorSoftSurface = Color(0xE616202D);
  static const Color _editorStroke = Color(0x26FFFFFF);
  static const Color _editorHeaderStroke = Color(0x22FFFFFF);
  static const Color _editorPrimaryAccent = Color(0xFF59D5FF);
  static const Color _editorSecondaryAccent = Color(0xFFFFB86C);
  static const Color _editorCtaStart = Color(0xFF67E8F9);
  static const Color _editorCtaEnd = Color(0xFF38BDF8);
  static const Color _editorModalBarrier = Color(0x73000000);
  static const Color _editorChipSurface = Color(0xFF1E2633);
  static const Color _editorChipSelected = Color(0xFFB9F3FF);
  static const Color _editorChipText = Color(0xFFB7C0CC);
  static const Color _editorChipSelectedText = Color(0xFF071018);
  static const Color _editorTextPrimary = Color(0xFFF8FAFC);
  static const Color _editorTextMuted = Color(0xFFAAB7C8);
  static const double _editorRadiusLarge = 24.0;
  static const double _editorRadius = 18.0;
  static const double _editorRadiusSmall = 12.0;
  static const List<BoxShadow> _editorPanelShadow = <BoxShadow>[
    BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 12)),
  ];
  static const List<BoxShadow> _editorHeaderShadow = <BoxShadow>[
    BoxShadow(color: Color(0x33000000), blurRadius: 20, offset: Offset(0, 8)),
  ];
  static const Color _bgColor = _editorBackground;
  static const Color _primaryColor = _editorPrimaryAccent;
  static const Color _textPrimary = _editorTextPrimary;
  static const Color _textSecondary = _editorTextMuted;
  static const double _bottomToolbarHeight = 88.0;
  static const double _inlineModePanelHeight = 110.0;
  static const double _colorFilterPanelHeight = 138.0;
  static const double _inlineModePanelGap = 2.0;
  static const double _transformOverlayBottomInset = 14.0;
  static const double _inlineModePanelSpacing = 1.0;
  static const double _headerRowSpacing = 2.0;
  static const double _inlineModePanelSidePadding = 12.0;
  static const double _inlineModePanelVerticalPadding = 6.0;
  static const double _inlineModeChipRowHeight = 28.0;
  static const bool _enableDormantEditFeatures = false;
  static final BoxDecoration _inlineModePanelDecoration = BoxDecoration(
    color: _editorGlassSurface,
    border: Border.all(color: _editorStroke),
    borderRadius: BorderRadius.circular(_editorRadiusLarge),
    boxShadow: _editorPanelShadow,
  );
  static const Map<String, _ColorFilterMoodMeta> _colorFilterMoodMetaById =
      <String, _ColorFilterMoodMeta>{
        kColorFilterPresetNone: _ColorFilterMoodMeta(
          title: '원본',
          subtitle: '보정 없음',
          icon: Icons.trip_origin_rounded,
          gradientColors: <Color>[Color(0xFF343A40), Color(0xFF8B96A3)],
          accentColor: Color(0xFFCBD5E1),
        ),
        kColorFilterPresetClearSky: _ColorFilterMoodMeta(
          title: '청량',
          subtitle: '맑은 여행톤',
          icon: Icons.water_drop_rounded,
          gradientColors: <Color>[Color(0xFF39D2FF), Color(0xFF49F2B4)],
          accentColor: Color(0xFF7DD3FC),
        ),
        kColorFilterPresetWarmSunset: _ColorFilterMoodMeta(
          title: '노을',
          subtitle: '따뜻한 카페톤',
          icon: Icons.wb_twilight_rounded,
          gradientColors: <Color>[Color(0xFFFF8A3D), Color(0xFFFFD166)],
          accentColor: Color(0xFFFBBF24),
        ),
        kColorFilterPresetFilmGreen: _ColorFilterMoodMeta(
          title: '필름',
          subtitle: '부드러운 그린',
          icon: Icons.local_movies_rounded,
          gradientColors: <Color>[Color(0xFF234F3B), Color(0xFFA7C957)],
          accentColor: Color(0xFFBEF264),
        ),
        kColorFilterPresetKoreanTravelPop: _ColorFilterMoodMeta(
          title: '여행',
          subtitle: '선명한 브이로그',
          icon: Icons.flight_takeoff_rounded,
          gradientColors: <Color>[Color(0xFFFF4D8D), Color(0xFF3B82F6)],
          accentColor: Color(0xFF93C5FD),
        ),
        kColorFilterPresetCityNightWarm: _ColorFilterMoodMeta(
          title: '도시밤',
          subtitle: '따뜻한 야경',
          icon: Icons.nightlife_rounded,
          gradientColors: <Color>[Color(0xFF101827), Color(0xFFFFB347)],
          accentColor: Color(0xFFF59E0B),
        ),
      };

  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isMissingFile = false;
  bool _isCloudClipLoadFailed = false;
  int? _activeMissingClipIndex;
  int? _activeCloudClipFailureIndex;
  Set<int> _missingClipIndexes = <int>{};
  final Set<int> _cloudResolvingClipIndexes = <int>{};
  final Map<int, _CloudClipEditState> _cloudClipStates =
      <int, _CloudClipEditState>{};
  final Map<int, CloudClipResolveFailureCode> _cloudClipFailureCodes =
      <int, CloudClipResolveFailureCode>{};
  final Map<String, CloudClipResolvedSource> _resolvedCloudClipSources =
      <String, CloudClipResolvedSource>{};
  final Map<String, CloudClipResolvedSource> _resolvedExportCloudClipSources =
      <String, CloudClipResolvedSource>{};
  CloudClipSessionResolver? _cloudClipSessionResolver;

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
  _BottomInlinePanel _bottomInlinePanel = _BottomInlinePanel.none;
  bool _playbackLockedByTransform = false;
  double _transformGestureBaseScale = 1.0;
  bool _transformPreviewFrameScheduled = false;
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
  Map<String, double> _brightnessAdjustments = defaultBrightnessAdjustments();
  String _selectedColorFilterPresetId = kColorFilterPresetNone;
  double _colorFilterIntensity = kColorFilterIntensityDefault;
  EditorState? _colorFilterGestureBaseState;
  bool _colorFilterGestureDirty = false;

  bool get _isPlaybackLockedForEditing =>
      _playbackLockedByTransform ||
      _isBrightnessMode ||
      _bottomInlinePanel == _BottomInlinePanel.sound;

  bool get _canUseTopClipNavigation => !_isExportUiBlocking;

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

  EditorState _sanitizeEditorStateForSupportedFeatures(EditorState state) {
    if (_enableDormantEditFeatures) return state;
    return EditorState(
      subtitles: const <SubtitleModel>[],
      stickers: const <StickerModel>[],
      filter: FilterPreset.none,
      filterOpacity: 0.0,
      bgmPath: state.bgmPath,
      videoVolume: state.videoVolume,
      bgmVolume: state.bgmVolume,
      clips: state.clips.map((clip) => clip.copyWith()).toList(),
      currentClipIndex: state.currentClipIndex,
      canvasAspectRatioPreset: state.canvasAspectRatioPreset,
      canvasBackgroundMode: state.canvasBackgroundMode,
      brightnessAdjustments: Map<String, double>.from(
        state.brightnessAdjustments,
      ),
      colorFilterPresetId: normalizeColorFilterPresetId(
        state.colorFilterPresetId,
      ),
      colorFilterIntensity: normalizeColorFilterIntensity(
        state.colorFilterIntensity,
      ),
    );
  }

  // State for Snapshot
  EditorState get _currentState => _sanitizeEditorStateForSupportedFeatures(
    EditorState(
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
      brightnessAdjustments: normalizeBrightnessAdjustments(
        _brightnessAdjustments,
      ),
      colorFilterPresetId: normalizeColorFilterPresetId(
        _selectedColorFilterPresetId,
      ),
      colorFilterIntensity: normalizeColorFilterIntensity(
        _colorFilterIntensity,
      ),
    ),
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
  late final String _editExportSessionId;
  late final UserTier _sessionStartTier;
  late final UserTier _sessionRuntimeTier;
  UserTier _currentRuntimeTier = UserTier.free;
  bool _subscriptionRestrictedDuringEdit = false;
  final ScrollController _timelineScrollController = ScrollController();
  bool _didCheckAccessGate = false;
  bool _isAccessDenied = false;
  Timer? _autosaveDebounceTimer;
  Future<void> _autosaveChain = Future.value();
  _ProjectSaveUiState _saveUiState = _ProjectSaveUiState.idle;
  ProjectSaveResult? _lastProjectSaveResult;
  String? _lastProjectSaveReason;
  bool _isClosingWithSave = false;
  bool _isExportInProgress = false;
  bool _isExportCancelRequested = false;
  bool get _isExportUiBlocking =>
      _isExportInProgress ||
      _isExportProgressDialogOpen ||
      _isExportCancelRequested;
  String _exportProgressPhase = 'ready';
  String? _exportCancelReason;
  double _exportDialogProgress = 0.0;
  String _exportDialogLabel = '';
  bool _isExportProgressDialogOpen = false;
  BuildContext? _exportProgressDialogContext;
  StateSetter? _exportProgressDialogStateSetter;

  int get _safeCurrentClipDisplayIndex {
    if (_clips.isEmpty) return 0;
    return (_currentClipIndex + 1).clamp(1, _clips.length);
  }

  String get _currentClipBadgeText =>
      '현재 $_safeCurrentClipDisplayIndex / ${_clips.length}';

  CloudClipSessionResolver get _cloudResolver =>
      _cloudClipSessionResolver ??= CloudClipSessionResolver(
        metadataSource: CallbackCloudClipMetadataSource(
          _videoManager.getCloudMetadataForPath,
        ),
        downloadClient: CloudServiceSessionDownloadClient(CloudService()),
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _videoManager = Provider.of<VideoManager>(context, listen: false);
  }

  @override
  void initState() {
    super.initState();
    _brightnessAdjustments = normalizeBrightnessAdjustments(
      widget.project.brightnessAdjustments,
    );
    _selectedColorFilterPresetId = normalizeColorFilterPresetId(
      widget.project.colorFilterPresetId,
    );
    _colorFilterIntensity = normalizeColorFilterIntensity(
      widget.project.colorFilterIntensity,
    );
    _sessionStartTier = UserStatusManager().currentTier;
    _sessionRuntimeTier = normalizeRuntimeUserTier(_sessionStartTier);
    _currentRuntimeTier = _sessionRuntimeTier;
    _editExportSessionId = widget.mergeSessionId?.trim().isNotEmpty == true
        ? widget.mergeSessionId!.trim()
        : 'edit_${widget.project.id}_${DateTime.now().millisecondsSinceEpoch}';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runAccessGateThenInit();
    });
  }

  Future<void> _runAccessGateThenInit() async {
    if (_didCheckAccessGate || !mounted || _isDisposed) return;
    _didCheckAccessGate = true;

    final userStatus = UserStatusManager();
    await userStatus.evaluateAndAutoDowngradeIfExpired(
      reason: 'edit_screen_access_gate',
    );
    if (!mounted || _isDisposed) return;

    final evaluatedRuntimeTier = _effectiveTierForEditWrite(userStatus);
    final clampedQuality = clampExportQuality(
      evaluatedRuntimeTier,
      widget.project.quality,
    );
    if (widget.project.quality != clampedQuality) {
      widget.project.quality = clampedQuality;
      debugPrint(
        '[EditScreen][AccessGate] clampedProjectQuality=$clampedQuality '
        'project=${widget.project.id}',
      );
    }

    debugPrint(
      '[EditScreen][AccessGate] sessionStartTier=$_sessionStartTier '
      'runtimeTier=$_sessionRuntimeTier currentTier=${userStatus.currentTier} '
      'evaluatedRuntimeTier=$evaluatedRuntimeTier '
      'canCloudWrite=${userStatus.canStartNewCloudWrite()} '
      'project=${widget.project.id}',
    );

    if (!canAccessVideoEditScreenForTier(evaluatedRuntimeTier)) {
      debugPrint(
        '[EditScreen][AccessGate] blocked project=${widget.project.id} '
        'sessionStartTier=$_sessionStartTier '
        'sessionRuntimeTier=$_sessionRuntimeTier '
        'evaluatedRuntimeTier=$evaluatedRuntimeTier',
      );
      if (mounted) {
        setState(() {
          _currentRuntimeTier = evaluatedRuntimeTier;
          _subscriptionRestrictedDuringEdit = true;
          _isAccessDenied = true;
        });
      }
      return;
    }

    _currentRuntimeTier = evaluatedRuntimeTier;
    _subscriptionRestrictedDuringEdit = false;
    await _refreshSubscriptionRuntimeTier(reason: 'session_start');
    if (!mounted || _isDisposed) return;

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

  UserTier _effectiveTierForEditWrite(UserStatusManager userStatus) {
    if (!userStatus.canStartNewCloudWrite()) {
      return UserTier.free;
    }
    return normalizeRuntimeUserTier(userStatus.currentTier);
  }

  Future<UserTier> _refreshSubscriptionRuntimeTier({
    required String reason,
    bool notifyUser = false,
  }) async {
    final userStatus = UserStatusManager();
    await userStatus.evaluateAndAutoDowngradeIfExpired(
      reason: 'edit_screen_$reason',
    );

    final nextRuntimeTier = _effectiveTierForEditWrite(userStatus);
    final restricted = !canAccessVideoEditScreenForTier(nextRuntimeTier);
    final clampedQuality = clampExportQuality(
      nextRuntimeTier,
      widget.project.quality,
    );
    final didChange =
        nextRuntimeTier != _currentRuntimeTier ||
        restricted != _subscriptionRestrictedDuringEdit ||
        clampedQuality != widget.project.quality;

    if (clampedQuality != widget.project.quality) {
      widget.project.quality = clampedQuality;
    }

    if (didChange) {
      debugPrint(
        '[EditScreen][SubscriptionChange] reason=$reason '
        'sessionStart=$_sessionStartTier sessionRuntime=$_sessionRuntimeTier '
        'currentTier=${userStatus.currentTier} '
        'effectiveRuntimeTier=$nextRuntimeTier '
        'canCloudWrite=${userStatus.canStartNewCloudWrite()} '
        'restricted=$restricted '
        'projectQuality=${widget.project.quality}',
      );
      if (mounted && !_isDisposed) {
        setState(() {
          _currentRuntimeTier = nextRuntimeTier;
          _subscriptionRestrictedDuringEdit = restricted;
        });
      } else {
        _currentRuntimeTier = nextRuntimeTier;
        _subscriptionRestrictedDuringEdit = restricted;
      }
    }

    if (restricted && notifyUser) {
      Fluttertoast.showToast(
        msg: '구독 상태가 변경되어 Cloud 저장은 중단되고 내보내기는 720p로 제한됩니다.',
      );
    }

    return nextRuntimeTier;
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
          debugPrint('Error fetching duration for <redacted-path>: $e');
          clip.originalDuration = Duration(
            milliseconds: kTargetClipMs,
          ); // Fallback
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
      unawaited(_enqueueAutosave(reason: 'preload_duration'));
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
      await _enqueueAutosave(reason: 'timeline_thumbnail');
    }
    debugPrint('[EditScreen] _preloadTimelineThumbnails DONE');
  }

  bool _isCloudOnlyClipPath(String path) =>
      CloudClipSessionResolver.isCloudOnlyPlaceholder(path);

  void _setCloudClipState(
    int index,
    _CloudClipEditState state, {
    CloudClipResolveFailureCode? failureCode,
  }) {
    _cloudClipStates[index] = state;
    if (state == _CloudClipEditState.cloudResolving ||
        state == _CloudClipEditState.cloudBuffering) {
      _cloudResolvingClipIndexes.add(index);
    } else {
      _cloudResolvingClipIndexes.remove(index);
    }

    if (state == _CloudClipEditState.cloudFailed && failureCode != null) {
      _cloudClipFailureCodes[index] = failureCode;
    } else if (state != _CloudClipEditState.cloudFailed) {
      _cloudClipFailureCodes.remove(index);
    }

    debugPrint(
      '[EditScreen][CloudClip][state] index=$index state=${state.name} '
      'failure=${failureCode?.name ?? ''}',
    );
  }

  bool _isClipPotentiallyPlayable(VlogClip clip) {
    if (_isCloudOnlyClipPath(clip.path)) return true;
    return File(clip.path).existsSync();
  }

  Future<File?> _resolvePlaybackFileForClip(
    int index,
    VlogClip clip, {
    bool updateUi = true,
  }) async {
    if (!_isCloudOnlyClipPath(clip.path)) {
      final file = File(clip.path);
      return await file.exists() ? file : null;
    }

    final cached = _resolvedCloudClipSources[clip.path];
    if (cached != null) {
      final cachedFile = File(cached.sessionLocalPath);
      if (await cachedFile.exists() &&
          await cachedFile.length() == cached.fileSize) {
        _setCloudClipState(index, _CloudClipEditState.cloudReady);
        return cachedFile;
      }
      _resolvedCloudClipSources.remove(clip.path);
    }

    if (updateUi && mounted && !_isDisposed) {
      setState(() {
        _currentClipIndex = index;
        _setCloudClipState(index, _CloudClipEditState.cloudResolving);
        _isCloudClipLoadFailed = false;
        _activeCloudClipFailureIndex = null;
        _isMissingFile = false;
      });
    } else {
      _setCloudClipState(index, _CloudClipEditState.cloudResolving);
    }

    final appDocumentsDirectory = await getApplicationDocumentsDirectory();
    if (updateUi && mounted && !_isDisposed) {
      setState(() {
        _setCloudClipState(index, _CloudClipEditState.cloudBuffering);
      });
    } else {
      _setCloudClipState(index, _CloudClipEditState.cloudBuffering);
    }

    final result = await _cloudResolver.resolve(
      placeholderPath: clip.path,
      appDocumentsDirectory: appDocumentsDirectory,
      purpose: CloudClipSessionPurpose.edit,
    );
    if (_isDisposed) return null;

    if (!result.isSuccess) {
      final code =
          result.failure?.code ?? CloudClipResolveFailureCode.downloadFailed;
      _setCloudClipState(
        index,
        _CloudClipEditState.cloudFailed,
        failureCode: code,
      );
      debugPrint(
        '[EditScreen][CloudClip][resolve_failed] index=$index code=$code',
      );
      if (updateUi && mounted && !_isDisposed) {
        setState(() {
          _isCloudClipLoadFailed = true;
          _activeCloudClipFailureIndex = index;
          _isInitialized = false;
          _isPlaying = false;
        });
      }
      return null;
    }

    final source = result.source!;
    _resolvedCloudClipSources[clip.path] = source;
    _setCloudClipState(index, _CloudClipEditState.cloudReady);
    _missingClipIndexes.remove(index);
    if (source.duration != null && source.duration! > Duration.zero) {
      if (clip.originalDuration == Duration.zero) {
        clip.originalDuration = source.duration!;
      }
      if (clip.endTime == Duration.zero) {
        clip.endTime = source.duration!;
      }
    }
    debugPrint(
      '[EditScreen][CloudClip][resolved] index=$index fromCache=${source.fromCache}',
    );
    if (updateUi && mounted && !_isDisposed) {
      setState(() {
        _isCloudClipLoadFailed = false;
        _activeCloudClipFailureIndex = null;
      });
    }
    return File(source.sessionLocalPath);
  }

  Future<Uint8List?> _getTimelineCardThumbnail(VlogClip clip) async {
    if (!_isCloudOnlyClipPath(clip.path)) {
      return _videoManager.getThumbnail(clip.path);
    }

    final cloudThumbnail = await _videoManager.getThumbnail(clip.path);
    if (cloudThumbnail != null) return cloudThumbnail;

    final resolved = _resolvedCloudClipSources[clip.path];
    if (resolved == null) return null;
    return _videoManager.getThumbnail(resolved.sessionLocalPath);
  }

  String _timelineSourcePathForClip(VlogClip clip) {
    if (!_isCloudOnlyClipPath(clip.path)) return clip.path;
    return _resolvedCloudClipSources[clip.path]?.sessionLocalPath ?? clip.path;
  }

  Future<List<VlogClip>?> _resolveExportClips() async {
    if (_clips.isEmpty) return const <VlogClip>[];

    final appDocumentsDirectory = await getApplicationDocumentsDirectory();
    final exportClips = <VlogClip>[];

    for (var i = 0; i < _clips.length; i++) {
      if (_isDisposed || _isExportCancelRequested) return null;
      final clip = _clips[i];

      if (!_isCloudOnlyClipPath(clip.path)) {
        final file = File(clip.path);
        if (!await file.exists()) {
          throw _ExportClipResolveException(
            index: i,
            message: 'local_source_missing',
          );
        }
        exportClips.add(clip.copyWith());
        continue;
      }

      _setExportProgress(
        phase: 'prepare_cloud',
        label: 'Cloud Clip 준비 중 ${i + 1}/${_clips.length}',
        progress: 0.12 + (0.18 * ((i + 1) / _clips.length)),
      );

      final result = await _cloudResolver.resolve(
        placeholderPath: clip.path,
        appDocumentsDirectory: appDocumentsDirectory,
        purpose: CloudClipSessionPurpose.export,
      );
      if (_isDisposed || _isExportCancelRequested) return null;

      if (!result.isSuccess) {
        throw _ExportClipResolveException(
          index: i,
          message: 'cloud_clip_materialize_failed',
          cloudFailureCode: result.failure?.code,
        );
      }

      final source = result.source!;
      _resolvedExportCloudClipSources[clip.path] = source;
      debugPrint(
        '[EditScreen][Export][CloudClip][resolved] '
        'index=$i fromCache=${source.fromCache}',
      );
      exportClips.add(clip.copyWith(path: source.sessionLocalPath));
    }

    return exportClips;
  }

  Future<ProjectSaveResult> _runExportPreflight({
    required VideoManager videoManager,
    required String quality,
  }) async {
    _setExportProgress(
      phase: 'preflight',
      label: 'Export preflight',
      progress: 0.28,
    );

    final cloudClipCount = _clips
        .where((clip) => _isCloudOnlyClipPath(clip.path))
        .length;
    final estimatedBytes = _estimateExportOutputBytes(quality);
    final estimatedMaterializeBytes = _estimateCloudMaterializeBytes();
    final canWriteScratch = await _probeExportScratchWritable();
    if (!canWriteScratch) {
      throw const _ExportPreflightException(
        'storage_unavailable',
        'export_scratch_write_failed',
      );
    }

    for (var i = 0; i < _clips.length; i++) {
      final clip = _clips[i];
      if (_isCloudOnlyClipPath(clip.path)) continue;
      if (!await File(clip.path).exists()) {
        throw _ExportClipResolveException(
          index: i,
          message: 'local_source_missing',
        );
      }
    }

    final saveResult = await videoManager.saveProject(
      widget.project,
      reason: 'edit_export_preflight_save',
    );
    _applyProjectSaveResult(saveResult, reason: 'export_preflight_save');
    if (!saveResult.localSaved) {
      throw const _ExportPreflightException(
        'project_save_failed',
        'local_project_save_failed',
      );
    }

    debugPrint(
      '[EditScreen][Export][Preflight] '
      'quality=$quality clipCount=${_clips.length} '
      'cloudClipCount=$cloudClipCount '
      'networkRequired=${cloudClipCount > 0} '
      'estimatedOutputBytes=$estimatedBytes '
      'estimatedMaterializeBytes=$estimatedMaterializeBytes '
      'localSave=${saveResult.localStatus.name} '
      'cloudSave=${saveResult.cloudStatus.name} '
      'partialOutputPolicy=do_not_register_before_success',
    );

    if (cloudClipCount > 0) {
      _setExportProgress(
        phase: 'preflight_cloud',
        label: 'Cloud Clip network required',
        progress: 0.3,
      );
    }

    return saveResult;
  }

  int _estimateExportOutputBytes(String quality) {
    final profile = videoQualityProfile(quality);
    final totalMs = _clips.fold<int>(0, (sum, clip) {
      final duration = _getTrimmedDuration(clip);
      final safeMs = duration.inMilliseconds > 0
          ? duration.inMilliseconds
          : kTargetClipMs;
      return sum + safeMs;
    });
    final videoBytes = (profile.targetBitrate / 8 * (totalMs / 1000)).ceil();
    return (videoBytes * 1.25).ceil();
  }

  int _estimateCloudMaterializeBytes() {
    var total = 0;
    for (final clip in _clips) {
      if (!_isCloudOnlyClipPath(clip.path)) continue;
      final meta = _videoManager.getCloudMetadataForPath(clip.path);
      final size = meta?.fileSize ?? 0;
      if (size > 0) total += size;
    }
    return total;
  }

  Future<bool> _probeExportScratchWritable() async {
    File? probe;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      probe = File(
        '${appDir.path}${Platform.pathSeparator}.export_preflight_probe',
      );
      await probe.writeAsBytes(const <int>[1], flush: true);
      await probe.delete();
      return true;
    } catch (e) {
      debugPrint(
        '[EditScreen][Export][Preflight] scratch_write_failed '
        'errorType=${e.runtimeType}',
      );
      try {
        if (probe != null && await probe.exists()) {
          await probe.delete();
        }
      } catch (_) {}
      return false;
    }
  }

  void _markExportSourceFailureForUi(_ExportClipResolveException e) {
    if (!mounted || _isDisposed) return;
    final isCloudFailure = e.cloudFailureCode != null;
    setState(() {
      if (isCloudFailure) {
        _isCloudClipLoadFailed = true;
        _activeCloudClipFailureIndex = e.index;
        if (e.cloudFailureCode != null) {
          _cloudClipFailureCodes[e.index] = e.cloudFailureCode!;
        }
      } else {
        _isMissingFile = true;
        _activeMissingClipIndex = e.index;
        _missingClipIndexes.add(e.index);
      }
    });
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
    final file = await _resolvePlaybackFileForClip(
      nextIndex,
      nextClip,
      updateUi: false,
    );
    if (file == null || !await file.exists()) return;
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
      if (_isClipPotentiallyPlayable(_clips[i])) return i;
    }
    return null;
  }

  int? _findPreviousExistingClipIndex(int startIndex) {
    for (int i = startIndex; i >= 0; i--) {
      if (_isClipPotentiallyPlayable(_clips[i])) return i;
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
      'path=<redacted-path> missingBefore=${_missingClipIndexes.toList()}',
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
      final shiftedCloudResolving = _cloudResolvingClipIndexes
          .where((i) => i != index)
          .map((i) => i > index ? i - 1 : i)
          .toSet();
      _cloudResolvingClipIndexes
        ..clear()
        ..addAll(shiftedCloudResolving);
      final shiftedCloudStates = <int, _CloudClipEditState>{};
      for (final entry in _cloudClipStates.entries) {
        if (entry.key == index) continue;
        shiftedCloudStates[entry.key > index ? entry.key - 1 : entry.key] =
            entry.value;
      }
      _cloudClipStates
        ..clear()
        ..addAll(shiftedCloudStates);
      final shiftedCloudFailures = <int, CloudClipResolveFailureCode>{};
      for (final entry in _cloudClipFailureCodes.entries) {
        if (entry.key == index) continue;
        shiftedCloudFailures[entry.key > index ? entry.key - 1 : entry.key] =
            entry.value;
      }
      _cloudClipFailureCodes
        ..clear()
        ..addAll(shiftedCloudFailures);

      final active = _activeMissingClipIndex;
      if (active == index) {
        _activeMissingClipIndex = null;
      } else if (active != null && active > index) {
        _activeMissingClipIndex = active - 1;
      }
      final activeCloudFailure = _activeCloudClipFailureIndex;
      if (activeCloudFailure == index) {
        _activeCloudClipFailureIndex = null;
        _isCloudClipLoadFailed = false;
      } else if (activeCloudFailure != null && activeCloudFailure > index) {
        _activeCloudClipFailureIndex = activeCloudFailure - 1;
      }

      if (_clips.isEmpty) {
        _currentClipIndex = 0;
        _isInitialized = false;
        _isPlaying = false;
        _isMissingFile = false;
        _isCloudClipLoadFailed = false;
        _cloudClipStates.clear();
        _cloudClipFailureCodes.clear();
        _cloudResolvingClipIndexes.clear();
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
      barrierColor: _editorModalBarrier,
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
            _currentClipIndex = (_currentClipIndex + 1).clamp(
              0,
              _clips.length - 1,
            );
            _controller!.addListener(_videoListener);
            _controller!.play();

            // 4. Trigger rebuild LAST (old is already gone)
            if (mounted && !_isDisposed) setState(() {});
            if (_isTrimMode) {
              _ensureTrimUiStateForCurrentClip(force: true);
            }
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
          // Stop at project end and reset to the first playable clip.
          _controller!.pause();
          _bgmController?.pause();
          if (mounted && !_isDisposed) {
            setState(() {
              _isPlaying = false;
            });
          }
          final resetIndex = _findNextExistingClipIndex(0) ?? 0;
          unawaited(_loadClip(resetIndex, autoPlay: false));
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
    debugPrint(
      '[EditScreen][Diag][Missing][load] index=$index '
      'path=<redacted-path> missingNow=${_missingClipIndexes.toList()}',
    );

    final file = await _resolvePlaybackFileForClip(index, clip);
    if (_isDisposed || loadEpoch != _controllerEpoch) return;

    if (file == null || !await file.exists()) {
      if (_isCloudOnlyClipPath(clip.path)) {
        return;
      }
      _missingClipIndexes.add(index);

      final nextPlayable = _findNextExistingClipIndex(index + 1);
      final prevPlayable = _findPreviousExistingClipIndex(index - 1);
      debugPrint(
        '[EditScreen][Diag][Missing][not_found] '
        'index=$index path=<redacted-path> '
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
          _isCloudClipLoadFailed = false;
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
        _isCloudClipLoadFailed = false;
        _activeMissingClipIndex = null;
        _activeCloudClipFailureIndex = null;
      });
      if (_isTrimMode) {
        _ensureTrimUiStateForCurrentClip(force: true);
      }
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
    widget.project.brightnessAdjustmentScope =
        kBrightnessAdjustmentScopeProjectWide;
    widget.project.brightnessAdjustments = normalizeBrightnessAdjustments(
      _brightnessAdjustments,
    );
    widget.project.colorFilterPresetId = normalizeColorFilterPresetId(
      _selectedColorFilterPresetId,
    );
    widget.project.colorFilterIntensity = normalizeColorFilterIntensity(
      _colorFilterIntensity,
    );
  }

  double _canvasAspectRatioForPreset(String preset) {
    switch (preset) {
      case 'r3_4':
        return 3 / 4;
      case 'r4_3':
        return 4 / 3;
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
      case 'r3_4':
        return '3:4';
      case 'r4_3':
        return '4:3';
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

  Future<ProjectSaveResult> _persistProjectAutosave({
    required String reason,
  }) async {
    await _refreshSubscriptionRuntimeTier(reason: 'autosave_$reason');
    _syncEditorStateToProject();
    final result = await _videoManager.saveProject(
      widget.project,
      reason: 'edit_autosave_$reason',
    );
    debugPrint(
      '[EditScreen][Autosave] saved: reason=$reason '
      'local=${result.localStatus.name} cloud=${result.cloudStatus.name}',
    );
    return result;
  }

  Future<void> _enqueueAutosave({required String reason}) {
    _setProjectSaveUiState(
      _ProjectSaveUiState.saving,
      reason: reason,
      result: _lastProjectSaveResult,
    );
    _autosaveChain = _autosaveChain
        .then((_) => _persistProjectAutosave(reason: reason))
        .then((result) {
          _applyProjectSaveResult(result, reason: reason);
        })
        .catchError((Object e, StackTrace st) {
          debugPrint('[EditScreen][Autosave] failed: reason=$reason, error=$e');
          _setProjectSaveUiState(
            _ProjectSaveUiState.cloudFailed,
            reason: reason,
          );
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

  void _applyProjectSaveResult(
    ProjectSaveResult result, {
    required String reason,
  }) {
    final nextState = result.cloudSaved
        ? _ProjectSaveUiState.cloudSaved
        : result.localSaved && result.cloudFailed
        ? _ProjectSaveUiState.cloudFailed
        : result.localSaved
        ? _ProjectSaveUiState.localSaved
        : _ProjectSaveUiState.cloudFailed;
    _setProjectSaveUiState(nextState, reason: reason, result: result);
  }

  void _setProjectSaveUiState(
    _ProjectSaveUiState nextState, {
    required String reason,
    ProjectSaveResult? result,
  }) {
    if (_isDisposed) return;
    if (mounted) {
      setState(() {
        _saveUiState = nextState;
        _lastProjectSaveReason = reason;
        if (result != null) {
          _lastProjectSaveResult = result;
        }
      });
    } else {
      _saveUiState = nextState;
      _lastProjectSaveReason = reason;
      if (result != null) {
        _lastProjectSaveResult = result;
      }
    }
  }

  Future<void> _retryProjectCloudSave() async {
    if (_isDisposed || _saveUiState == _ProjectSaveUiState.saving) return;
    _setProjectSaveUiState(
      _ProjectSaveUiState.retrying,
      reason: 'manual_retry',
      result: _lastProjectSaveResult,
    );
    await _flushAutosave(reason: 'manual_retry');
  }

  Future<void> _handleClosePressed() async {
    if (_isClosingWithSave) return;
    setState(() {
      _isClosingWithSave = true;
    });
    try {
      _setProjectSaveUiState(
        _ProjectSaveUiState.saving,
        reason: 'close_button_flush',
      );
      debugPrint(
        '[EditScreen][Autosave] close flush start project=${widget.project.id}',
      );
      await _flushAutosave(reason: 'close_button');
      await _refreshSubscriptionRuntimeTier(
        reason: 'close_button_save',
        notifyUser: true,
      );
      final result = await _videoManager.saveProject(
        widget.project,
        reason: 'edit_close_button_save',
      );
      _applyProjectSaveResult(result, reason: 'close_button_save');
      debugPrint(
        '[EditScreen][Autosave] close flush done project=${widget.project.id} '
        'local=${result.localStatus.name} cloud=${result.cloudStatus.name}',
      );
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

  Future<void> _cleanupSessionCacheBestEffort({
    required String trigger,
    Iterable<String> protectedPaths = const <String>[],
  }) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final result = await CloudClipSessionResolver.cleanupExpiredSessionCache(
        appDocumentsDirectory: appDir,
        protectedPaths: protectedPaths,
      );
      debugPrint(
        '[EditScreen][SessionCacheCleanup] trigger=$trigger '
        'deleted=${result.deletedFileCount} '
        'protected=${result.skippedProtectedCount} '
        'fresh=${result.skippedFreshCount} '
        'failed=${result.failedDeleteCount}',
      );
    } catch (e) {
      debugPrint(
        '[EditScreen][SessionCacheCleanup] trigger=$trigger failed '
        'errorType=${e.runtimeType}',
      );
    }
  }

  @override
  void dispose() {
    debugPrint('[EditScreen] dispose START');
    final protectedCachePaths = <String>[
      ..._resolvedCloudClipSources.values.map(
        (source) => source.sessionLocalPath,
      ),
      ..._resolvedExportCloudClipSources.values.map(
        (source) => source.sessionLocalPath,
      ),
    ];
    unawaited(_closeExportProgressDialog());
    _autosaveDebounceTimer?.cancel();
    _autosaveDebounceTimer = null;
    _isDisposed = true;
    unawaited(_enqueueAutosave(reason: 'dispose'));

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
    unawaited(
      _cleanupSessionCacheBestEffort(
        trigger: 'edit_dispose',
        protectedPaths: protectedCachePaths,
      ),
    );

    debugPrint('[EditScreen] dispose DONE');
    super.dispose();
  }

  // Undo/Redo 상태 복원

  void _applyEditorState(EditorState state, {bool keepPlayback = false}) {
    final wasPlaying = keepPlayback ? _isPlaying : false;
    state = _sanitizeEditorStateForSupportedFeatures(state);
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
      _brightnessAdjustments = normalizeBrightnessAdjustments(
        state.brightnessAdjustments,
      );
      _selectedColorFilterPresetId = normalizeColorFilterPresetId(
        state.colorFilterPresetId,
      );
      _colorFilterIntensity = normalizeColorFilterIntensity(
        state.colorFilterIntensity,
      );
      _bgmPath = state.bgmPath;
      _videoVolume = state.videoVolume;
      _bgmVolume = state.bgmVolume;
      _clips = state.clips.map((e) => e.copyWith()).toList();
      _currentClipIndex = normalizedNextIndex;
      widget.project.canvasAspectRatioPreset = state.canvasAspectRatioPreset;
      widget.project.canvasBackgroundMode = state.canvasBackgroundMode;
      widget.project.brightnessAdjustmentScope =
          kBrightnessAdjustmentScopeProjectWide;
      widget.project.brightnessAdjustments = normalizeBrightnessAdjustments(
        _brightnessAdjustments,
      );
      widget.project.colorFilterPresetId = normalizeColorFilterPresetId(
        _selectedColorFilterPresetId,
      );
      widget.project.colorFilterIntensity = normalizeColorFilterIntensity(
        _colorFilterIntensity,
      );
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
        _showTransformAngleNumericLabel = false;
        _isTransformAngleDragging = false;
        _transformInlinePanel = _TransformInlinePanel.none;
      }
    });
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

  String _transformAngleModeLabel(_TransformAngleMode mode) {
    switch (mode) {
      case _TransformAngleMode.tilt:
        return '기울기';
    }
  }

  String _getBrightnessTransitionFromMode() {
    if (_isTrimMode) return 'trim';
    if (_isTransformModeActive) return 'transform';
    if (_bottomInlinePanel == _BottomInlinePanel.trimSpeedPreset) {
      return 'trim_speed_preset';
    }
    if (_bottomInlinePanel == _BottomInlinePanel.sound) return 'sound_panel';
    if (_bottomInlinePanel == _BottomInlinePanel.colorFilter) {
      return 'color_filter_panel';
    }
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
    if (maxMs <= 0) maxMs = kTargetClipMs.toDouble();
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

  void _openExportProgressDialog() {
    if (_isExportProgressDialogOpen || !mounted || _isDisposed) return;

    _isExportProgressDialogOpen = true;
    _exportProgressPhase = 'ready';
    _exportDialogProgress = 0.25;
    _exportDialogLabel = '내보내기 준비 중';
    _exportCancelReason = null;

    showDialog(
      context: context,
      barrierColor: _editorModalBarrier,
      barrierDismissible: false,
      builder: (dialogContext) {
        _exportProgressDialogContext = dialogContext;
        return PopScope(
          canPop: false,
          child: StatefulBuilder(
            builder: (innerContext, setDialogState) {
              _exportProgressDialogStateSetter = setDialogState;
              return AlertDialog(
                backgroundColor: _editorSoftSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_editorRadiusLarge),
                  side: const BorderSide(color: _editorStroke),
                ),
                title: const Text(
                  '내보내기 진행 중',
                  style: TextStyle(color: _editorTextPrimary),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: kAlwaysDismissedAnimation,
                      builder: (context, _) {
                        return LinearProgressIndicator(
                          value: _exportDialogProgress,
                          minHeight: 8,
                          backgroundColor: Colors.white24,
                          color: _editorPrimaryAccent,
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _exportDialogLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _editorTextPrimary),
                    ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: _requestExportCancel,
                      child: const Text(
                        '취소',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _setExportProgress({
    required String phase,
    required String label,
    required double progress,
  }) {
    _exportProgressPhase = phase;
    _exportDialogLabel = label;
    _exportDialogProgress = progress.clamp(0.0, 1.0);
    if (!mounted || !_isExportProgressDialogOpen) return;
    final setter = _exportProgressDialogStateSetter;
    if (setter != null) {
      setter(() {});
    }
  }

  void _updateExportProgress(String label, double progress) {
    _setExportProgress(
      phase: _exportProgressPhase,
      label: label,
      progress: progress,
    );
  }

  void _setExportCancelledProgress({
    required String reason,
    required String phase,
    required double progress,
  }) {
    _exportCancelReason = reason;
    _setExportProgress(phase: phase, label: '내보내기 취소 요청됨', progress: progress);
  }

  double _defaultExportProgressForPhase(String phase) {
    switch (phase) {
      case 'ready':
      case 'prepare':
        return 0.25;
      case 'rendering':
        return 0.5;
      case 'saving':
        return 0.75;
      case 'done':
        return 1.0;
      default:
        return _exportDialogProgress;
    }
  }

  Future<void> _closeExportProgressDialog() async {
    final dialogContext = _exportProgressDialogContext;
    _isExportProgressDialogOpen = false;
    _exportProgressDialogContext = null;
    _exportProgressDialogStateSetter = null;
    _exportProgressPhase = 'ready';
    _exportCancelReason = null;

    if (dialogContext != null && Navigator.canPop(dialogContext)) {
      Navigator.pop(dialogContext);
    }

    if (!mounted) return;
    if (_isExportInProgress) {
      setState(() {
        _isExportInProgress = false;
      });
    }
  }

  void _requestExportCancel() {
    if (_isExportCancelRequested || !_isExportInProgress) return;
    _isExportCancelRequested = true;
    _setExportCancelledProgress(
      reason: 'user_requested',
      phase: 'cancelled',
      progress: _defaultExportProgressForPhase(_exportProgressPhase),
    );
    _closeExportProgressDialog();
    Fluttertoast.showToast(msg: '내보내기 취소를 요청했습니다.');
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
    if (_isAccessDenied) {
      return Scaffold(
        backgroundColor: _bgColor,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.workspace_premium_rounded,
                    color: _primaryColor,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Standard 구독 필요',
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Free는 선택 클립의 720p 빠른 내보내기만 사용할 수 있습니다.\n프로젝트 편집과 저장은 Standard 구독이 필요합니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _textSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SubscriptionManagementScreen(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: const Color(0xFF07111F),
                    ),
                    child: const Text('구독하러 가기'),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.maybePop(context, false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _editorSoftSurface,
                      foregroundColor: _textPrimary,
                      side: const BorderSide(color: _editorStroke),
                    ),
                    child: const Text('돌아가기'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: !_isTrimMode && !_isExportUiBlocking,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isExportUiBlocking) {
          Fluttertoast.showToast(msg: '내보내기 진행 중에는 뒤로가기를 할 수 없습니다.');
          return;
        }
        _handleTrimBackAction();
      },
      child: Scaffold(
        backgroundColor: _bgColor,
        body: AbsorbPointer(
          absorbing: _isExportUiBlocking,
          child: SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: Stack(
                    children: [
                      _buildPreviewSection(),
                      if (_enableDormantEditFeatures)
                        ..._stickers.map((s) => _buildStickerWidget(s)),
                      if (_enableDormantEditFeatures)
                        ..._subtitles.map((s) => _buildSubtitleWidget(s)),
                    ],
                  ),
                ),
                _buildBottomControls(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    final bool showSoundPanel = _bottomInlinePanel == _BottomInlinePanel.sound;
    final bool showColorFilterPanel =
        _bottomInlinePanel == _BottomInlinePanel.colorFilter;
    final bool showBrightnessPanel = _isBrightnessMode;
    final double activeInlinePanelHeight = showColorFilterPanel
        ? _colorFilterPanelHeight
        : _inlineModePanelHeight;
    final double bottomPanelHeight =
        activeInlinePanelHeight + _inlineModePanelGap + _bottomToolbarHeight;

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
                : showColorFilterPanel
                ? KeyedSubtree(
                    key: const ValueKey('panel_color_filter'),
                    child: _buildColorFilterInlinePanel(),
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
    if (_isCloudClipLoadFailed) {
      final failureIndex = _activeCloudClipFailureIndex;
      final clipNumber = failureIndex == null ? '-' : '${failureIndex + 1}';
      final code = failureIndex == null
          ? null
          : _cloudClipFailureCodes[failureIndex];
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _editorSoftSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _editorStroke),
            boxShadow: _editorPanelShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off,
                color: _editorSecondaryAccent,
                size: 54,
              ),
              const SizedBox(height: 12),
              const Text(
                'Cloud Clip 로드 실패',
                style: TextStyle(
                  color: _editorTextPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '클립: $clipNumber 번',
                style: const TextStyle(
                  color: _editorTextPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                code == null ? 'cloud_clip_load_failed' : code.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _editorTextMuted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              if (failureIndex != null)
                ElevatedButton.icon(
                  onPressed: () => _loadClip(failureIndex),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: const Color(0xFF07111F),
                  ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('다시 시도'),
                ),
            ],
          ),
        ),
      );
    }

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
            color: _editorSoftSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _editorStroke),
            boxShadow: _editorPanelShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 54),
              const SizedBox(height: 12),
              const Text(
                'File Missing',
                style: TextStyle(
                  color: _editorTextPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '누락 클립: $clipNumber 번',
                style: const TextStyle(
                  color: _editorTextPrimary,
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
                style: const TextStyle(color: _editorTextMuted, fontSize: 12),
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
      final isCloudResolving = _cloudResolvingClipIndexes.contains(
        _currentClipIndex,
      );
      if (isCloudResolving) {
        final state = _cloudClipStates[_currentClipIndex];
        final label = state == _CloudClipEditState.cloudResolving
            ? 'Cloud Clip 확인 중'
            : 'Cloud Clip 준비 중';
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: _primaryColor),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(
                  color: _editorTextMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }
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
                      onHorizontalDragEnd: _handlePreviewSwipe,
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
        color: _editorGlassSurface,
        borderRadius: BorderRadius.circular(_editorRadius),
        border: Border.all(color: _editorStroke),
        boxShadow: _editorPanelShadow,
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
            child: Row(
              children: [
                Icon(
                  Icons.straighten_rounded,
                  color: _showTransformAngleNumericLabel
                      ? _editorSecondaryAccent
                      : _editorPrimaryAccent,
                  size: 16,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _transformAngleModeLabel(_TransformAngleMode.tilt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _editorTextPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _editorPrimaryAccent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _editorPrimaryAccent.withValues(alpha: 0.36),
                    ),
                  ),
                  child: Text(
                    '${currentValue.toStringAsFixed(1)}°',
                    style: const TextStyle(
                      color: _editorPrimaryAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
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
                color: active
                    ? _editorPrimaryAccent.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(_editorRadiusSmall),
                border: Border.all(
                  color: active
                      ? _editorPrimaryAccent.withValues(alpha: 0.5)
                      : _editorStroke,
                ),
              ),
              child: Icon(
                icon,
                size: 24,
                color: active ? _editorPrimaryAccent : _editorTextPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  ColorFilter _getFilterMatrix() {
    final brightnessFilter = ColorFilter.matrix(
      brightnessPreviewColorMatrix(_previewAdjustmentsWithColorFilter()),
    );
    if (!_enableDormantEditFeatures) {
      return brightnessFilter;
    }
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
        return brightnessFilter;
    }
  }

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 3),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: _editorHeaderSurface,
        borderRadius: BorderRadius.circular(_editorRadiusLarge),
        border: Border.all(color: _editorHeaderStroke),
        boxShadow: _editorHeaderShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildHeaderIconButton(
                icon: Icons.close,
                onPressed: _isClosingWithSave || _isExportInProgress
                    ? null
                    : _handleClosePressed,
                tooltip: '닫기',
                iconSize: 26,
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
              const SizedBox(width: 8),
              _buildExportCtaButton(),
            ],
          ),
          const SizedBox(height: _headerRowSpacing),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildHeaderIconButton(
                  icon: Icons.undo,
                  onPressed: _commandManager.canUndo ? _undo : null,
                  tooltip: 'Undo',
                ),
                const SizedBox(width: 4),
                _buildHeaderIconButton(
                  icon: Icons.redo,
                  onPressed: _commandManager.canRedo ? _redo : null,
                  tooltip: 'Redo',
                ),
                const SizedBox(width: 4),
                _buildHeaderIconButton(
                  icon: Icons.aspect_ratio,
                  onPressed: _showCanvasPanel,
                  tooltip:
                      'Canvas ${_canvasAspectLabel(widget.project.canvasAspectRatioPreset)}',
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _editorPrimaryAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _editorPrimaryAccent.withValues(alpha: 0.38),
                    ),
                  ),
                  child: Text(
                    _currentClipBadgeText,
                    style: const TextStyle(
                      color: _primaryColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _buildHeaderIconButton(
                  icon: Icons.chevron_left,
                  tooltip: '이전 클립',
                  onPressed:
                      _clips.isEmpty ||
                          _currentClipIndex <= 0 ||
                          !_canUseTopClipNavigation
                      ? null
                      : () => unawaited(_moveToAdjacentClip(-1)),
                ),
                const SizedBox(width: 4),
                _buildHeaderIconButton(
                  icon: Icons.chevron_right,
                  tooltip: '다음 클립',
                  onPressed:
                      _clips.isEmpty ||
                          _currentClipIndex >= _clips.length - 1 ||
                          !_canUseTopClipNavigation
                      ? null
                      : () => unawaited(_moveToAdjacentClip(1)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: _buildProjectSaveStatusChip(),
          ),
          if (_subscriptionRestrictedDuringEdit) ...[
            const SizedBox(height: 4),
            _buildSubscriptionChangeNotice(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderIconButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
    double iconSize = 22,
  }) {
    final enabled = onPressed != null;
    final iconColor = enabled
        ? _editorTextPrimary
        : _editorTextMuted.withValues(alpha: 0.42);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(_editorRadiusSmall),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(_editorRadiusSmall),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: enabled
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.035),
                borderRadius: BorderRadius.circular(_editorRadiusSmall),
                border: Border.all(
                  color: enabled
                      ? _editorStroke
                      : _editorStroke.withValues(alpha: 0.45),
                ),
              ),
              child: Icon(icon, color: iconColor, size: iconSize),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExportCtaButton() {
    final enabled = !_isExportInProgress;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '만들기',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: enabled ? _handleExport : null,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            constraints: const BoxConstraints(minWidth: 92, minHeight: 44),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: enabled
                    ? const <Color>[_editorCtaStart, _editorCtaEnd]
                    : const <Color>[Color(0xFF263244), Color(0xFF1A2230)],
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: enabled
                    ? Colors.white.withValues(alpha: 0.38)
                    : _editorStroke.withValues(alpha: 0.55),
              ),
              boxShadow: enabled
                  ? const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x3359D5FF),
                        blurRadius: 16,
                        offset: Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              '만들기',
              style: TextStyle(
                color: enabled
                    ? const Color(0xFF07111F)
                    : _editorTextMuted.withValues(alpha: 0.72),
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubscriptionChangeNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _editorSecondaryAccent.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _editorSecondaryAccent.withValues(alpha: 0.42),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_clock, size: 16, color: _editorSecondaryAccent),
          const SizedBox(width: 7),
          const Expanded(
            child: Text(
              'Subscription changed. Local draft is kept, Cloud save is paused, export is limited to 720p.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _editorTextPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectSaveStatusChip() {
    final state = _saveUiState;
    final result = _lastProjectSaveResult;
    final canRetry =
        result?.canRetry == true || state == _ProjectSaveUiState.cloudFailed;

    late final IconData icon;
    late final String label;
    late final Color fg;
    late final Color bg;
    late final Color border;

    switch (state) {
      case _ProjectSaveUiState.saving:
        icon = Icons.sync;
        label = 'Saving';
        fg = _editorPrimaryAccent;
        bg = _editorPrimaryAccent.withValues(alpha: 0.12);
        border = _editorPrimaryAccent.withValues(alpha: 0.38);
        break;
      case _ProjectSaveUiState.retrying:
        icon = Icons.refresh;
        label = 'Retrying save';
        fg = _editorPrimaryAccent;
        bg = _editorPrimaryAccent.withValues(alpha: 0.12);
        border = _editorPrimaryAccent.withValues(alpha: 0.38);
        break;
      case _ProjectSaveUiState.localSaved:
        icon = Icons.save_outlined;
        label = 'Saved locally';
        fg = const Color(0xFF7EF0C4);
        bg = const Color(0xFF7EF0C4).withValues(alpha: 0.12);
        border = const Color(0xFF7EF0C4).withValues(alpha: 0.32);
        break;
      case _ProjectSaveUiState.cloudSaved:
        icon = Icons.cloud_done_outlined;
        label = 'Cloud saved';
        fg = const Color(0xFF7EF0C4);
        bg = const Color(0xFF7EF0C4).withValues(alpha: 0.12);
        border = const Color(0xFF7EF0C4).withValues(alpha: 0.32);
        break;
      case _ProjectSaveUiState.cloudFailed:
        icon = Icons.cloud_off_outlined;
        label = result?.localSaved == true
            ? 'Local saved, Cloud failed'
            : 'Save failed';
        fg = _editorSecondaryAccent;
        bg = _editorSecondaryAccent.withValues(alpha: 0.13);
        border = _editorSecondaryAccent.withValues(alpha: 0.38);
        break;
      case _ProjectSaveUiState.idle:
        icon = Icons.cloud_queue;
        label = 'Autosave ready';
        fg = _textSecondary;
        bg = Colors.white.withValues(alpha: 0.07);
        border = _editorStroke;
        break;
    }

    return Semantics(
      label: 'Project save status: $label',
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (_lastProjectSaveReason != null &&
                state != _ProjectSaveUiState.idle) ...[
              const SizedBox(width: 5),
              Container(width: 1, height: 12, color: border),
              const SizedBox(width: 5),
              Text(
                _saveStatusTimeLabel(result?.completedAt),
                style: TextStyle(
                  color: fg.withValues(alpha: 0.72),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (canRetry) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: _retryProjectCloudSave,
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Icon(Icons.refresh, size: 15, color: fg),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _saveStatusTimeLabel(DateTime? completedAt) {
    if (completedAt == null) return 'pending';
    final elapsed = DateTime.now().difference(completedAt);
    if (elapsed.inSeconds < 5) return 'now';
    if (elapsed.inMinutes < 1) return '${elapsed.inSeconds}s';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes}m';
    return '${elapsed.inHours}h';
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
            Icons.auto_awesome,
            "색감",
            () {
              final transitionFrom = _getBrightnessTransitionFromMode();
              if (_isTrimMode) {
                _closeTrimMode();
              }
              if (_isTransformModeActive) {
                _enterTransformMode();
              }
              if (_isBrightnessMode) {
                _exitBrightnessModeForReason(
                  'color_filter_toolbar',
                  note: 'toolbar color filter pressed',
                  fromMode: transitionFrom,
                );
              }
              if (_bottomInlinePanel == _BottomInlinePanel.trimSpeedPreset) {
                setState(() => _bottomInlinePanel = _BottomInlinePanel.none);
                return;
              }
              setState(() {
                _bottomInlinePanel =
                    _bottomInlinePanel == _BottomInlinePanel.colorFilter
                    ? _BottomInlinePanel.none
                    : _BottomInlinePanel.colorFilter;
              });
            },
            active: _bottomInlinePanel == _BottomInlinePanel.colorFilter,
          ),
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
        ? _editorPrimaryAccent
        : emphasized
        ? _editorSecondaryAccent
        : _editorTextPrimary;
    final Color borderColor = active
        ? _editorPrimaryAccent.withValues(alpha: 0.58)
        : emphasized
        ? _editorSecondaryAccent.withValues(alpha: 0.5)
        : _editorStroke;
    final Gradient? backgroundGradient = active || emphasized
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: active
                ? <Color>[
                    _editorPrimaryAccent.withValues(alpha: 0.24),
                    _editorPrimaryAccent.withValues(alpha: 0.08),
                  ]
                : <Color>[
                    _editorSecondaryAccent.withValues(alpha: 0.22),
                    _editorPrimaryAccent.withValues(alpha: 0.08),
                  ],
          )
        : null;

    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_editorRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 55.8,
                height: 55.8,
                decoration: BoxDecoration(
                  color: backgroundGradient == null
                      ? Colors.white.withValues(alpha: 0.07)
                      : null,
                  gradient: backgroundGradient,
                  borderRadius: BorderRadius.circular(_editorRadius),
                  border: Border.all(
                    color: borderColor,
                    width: active ? 1.4 : 1,
                  ),
                  boxShadow: active
                      ? const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x3359D5FF),
                            blurRadius: 14,
                            offset: Offset(0, 6),
                          ),
                        ]
                      : const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(icon, color: iconColor, size: 30),
                    if (active)
                      Positioned(
                        bottom: 7,
                        child: Container(
                          width: 16,
                          height: 3,
                          decoration: BoxDecoration(
                            color: _editorPrimaryAccent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                  ],
                ),
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
                              ? _editorPrimaryAccent.withValues(alpha: 0.18)
                              : Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: selected
                                ? _editorPrimaryAccent.withValues(alpha: 0.54)
                                : _editorStroke,
                          ),
                        ),
                        child: Text(
                          speedLabel(speed),
                          style: TextStyle(
                            color: selected
                                ? _editorPrimaryAccent
                                : _editorTextPrimary,
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

  ColorFilterPresetSpec get _selectedColorFilterSpec =>
      colorFilterPresetById(_selectedColorFilterPresetId);

  Map<String, double> _previewAdjustmentsWithColorFilter() {
    final combined = normalizeBrightnessAdjustments(_brightnessAdjustments);
    final colorAdjustments = colorFilterPreviewAdjustments(
      presetId: _selectedColorFilterPresetId,
      intensity: _colorFilterIntensity,
    );
    for (final entry in colorAdjustments.entries) {
      final nextValue = ((combined[entry.key] ?? 0.0) + entry.value)
          .clamp(-100.0, 100.0)
          .toDouble();
      combined[entry.key] = nextValue;
    }
    return combined;
  }

  void _selectColorFilterPreset(String presetId) {
    final normalized = normalizeColorFilterPresetId(presetId);
    if (normalized == _selectedColorFilterPresetId) return;

    final oldState = _currentState.copy();
    setState(() {
      _selectedColorFilterPresetId = normalized;
      if (normalized != kColorFilterPresetNone &&
          _colorFilterIntensity == 0.0) {
        _colorFilterIntensity = kColorFilterIntensityDefault;
      }
    });
    final newState = _currentState.copy();
    _executeStateTransition(oldState, newState);
  }

  void _startColorFilterGesture() {
    _colorFilterGestureBaseState = _currentState.copy();
    _colorFilterGestureDirty = false;
  }

  void _commitColorFilterGesture() {
    if (!_colorFilterGestureDirty || _colorFilterGestureBaseState == null) {
      _colorFilterGestureBaseState = null;
      _colorFilterGestureDirty = false;
      return;
    }

    final oldState = _colorFilterGestureBaseState!;
    final newState = _currentState.copy();
    _colorFilterGestureBaseState = null;
    _colorFilterGestureDirty = false;
    _executeStateTransition(oldState, newState);
  }

  Widget _buildColorFilterInlinePanel() {
    final selectedSpec = _selectedColorFilterSpec;
    final selectedNone = selectedSpec.id == kColorFilterPresetNone;
    final displayedPercent = selectedNone
        ? 0
        : (normalizeColorFilterIntensity(_colorFilterIntensity) * 100).round();
    final selectedMeta = _colorFilterMoodMetaFor(selectedSpec);

    return Container(
      height: _colorFilterPanelHeight,
      margin: EdgeInsets.fromLTRB(
        _inlineModePanelSidePadding,
        _inlineModePanelSpacing,
        _inlineModePanelSidePadding,
        _inlineModePanelSpacing,
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: _inlineModePanelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 78,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kColorFilterPresetSpecs.length,
              separatorBuilder: (_, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final preset = kColorFilterPresetSpecs[index];
                final selected = preset.id == selectedSpec.id;
                return _buildColorFilterMoodCard(preset, selected);
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              children: [
                Icon(
                  selectedMeta.icon,
                  color: selectedNone
                      ? Colors.white54
                      : selectedMeta.accentColor,
                  size: 18,
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 88,
                  child: Text(
                    selectedNone
                        ? '${selectedMeta.title} 0%'
                        : '${selectedMeta.title} $displayedPercent%',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: selectedMeta.accentColor,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      overlayColor: selectedMeta.accentColor.withAlpha(54),
                    ),
                    child: Slider(
                      value: selectedNone
                          ? 0.0
                          : normalizeColorFilterIntensity(
                              _colorFilterIntensity,
                            ),
                      min: 0.0,
                      max: 1.0,
                      divisions: 100,
                      onChangeStart: selectedNone
                          ? null
                          : (_) => _startColorFilterGesture(),
                      onChanged: selectedNone
                          ? null
                          : (value) {
                              setState(() {
                                _colorFilterIntensity =
                                    normalizeColorFilterIntensity(value);
                                _colorFilterGestureDirty = true;
                              });
                            },
                      onChangeEnd: selectedNone
                          ? null
                          : (_) => _commitColorFilterGesture(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _ColorFilterMoodMeta _colorFilterMoodMetaFor(ColorFilterPresetSpec preset) {
    return _colorFilterMoodMetaById[preset.id] ??
        _ColorFilterMoodMeta(
          title: preset.label,
          subtitle: '무드 보정',
          icon: Icons.auto_awesome_rounded,
          gradientColors: const <Color>[Color(0xFF2B8CEE), Color(0xFF7A38E5)],
          accentColor: _primaryColor,
        );
  }

  Widget _buildColorFilterMoodCard(
    ColorFilterPresetSpec preset,
    bool selected,
  ) {
    final meta = _colorFilterMoodMetaFor(preset);
    final Color borderColor = selected
        ? meta.accentColor
        : Colors.white.withAlpha(31);
    final Color backgroundColor = selected
        ? Colors.white.withAlpha(31)
        : Colors.white.withAlpha(15);

    return Semantics(
      button: true,
      selected: selected,
      label: '${meta.title}, ${meta.subtitle}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _selectColorFilterPreset(preset.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 156,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: selected ? 1.4 : 1),
            ),
            child: Row(
              children: [
                _buildColorFilterMoodSwatch(meta, selected),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meta.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        meta.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? Colors.white70 : Colors.white54,
                          fontSize: 9.5,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildColorFilterMoodSwatch(_ColorFilterMoodMeta meta, bool selected) {
    return Container(
      width: 42,
      height: 58,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: meta.gradientColors,
        ),
        border: Border.all(
          color: selected ? Colors.white.withAlpha(205) : Colors.white24,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 22,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(42),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(11),
                ),
              ),
            ),
          ),
          Center(child: Icon(meta.icon, color: Colors.white, size: 20)),
          Positioned(
            right: 5,
            top: 5,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: meta.accentColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withAlpha(190)),
              ),
            ),
          ),
        ],
      ),
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
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
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
                colorFilterPresetId: _currentState.colorFilterPresetId,
                colorFilterIntensity: _currentState.colorFilterIntensity,
              );
              _executeStateChange(newState);
            },
          ),
          const SizedBox(height: 2),
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
                colorFilterPresetId: _currentState.colorFilterPresetId,
                colorFilterIntensity: _currentState.colorFilterIntensity,
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
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _editorPrimaryAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _editorPrimaryAccent.withValues(alpha: 0.28),
              ),
            ),
            child: Icon(icon, color: _editorPrimaryAccent, size: 17),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _editorTextPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: _editorPrimaryAccent,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                overlayColor: _editorPrimaryAccent.withValues(alpha: 0.18),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
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
            width: 34,
            child: Text(
              '${(value * 100).round()}%',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: _editorPrimaryAccent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
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

  List<BrightnessAdjustmentSpec> get _brightnessProperties =>
      brightnessPreviewAdjustmentSpecs();

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
                          ? _editorPrimaryAccent.withValues(alpha: 0.18)
                          : Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: selected
                            ? _editorPrimaryAccent.withValues(alpha: 0.5)
                            : _editorStroke,
                      ),
                    ),
                    child: Text(
                      selected && _showBrightnessNumericLabel
                          ? displayedValue.toStringAsFixed(0)
                          : property.label,
                      style: TextStyle(
                        color: selected
                            ? _editorPrimaryAccent
                            : _editorTextMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
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
                  color: _editorSoftSurface,
                  border: Border.all(color: _editorStroke),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: FutureBuilder<Uint8List?>(
                    future: _getTimelineCardThumbnail(clip),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data != null) {
                        return Image.memory(snapshot.data!, fit: BoxFit.cover);
                      }
                      return const Center(
                        child: Icon(Icons.movie, color: _editorTextMuted),
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
            colorFilterPresetId: baseState.colorFilterPresetId,
            colorFilterIntensity: baseState.colorFilterIntensity,
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
                    ? Border.all(color: _editorPrimaryAccent, width: 3)
                    : Border.all(color: _editorStroke),
                borderRadius: BorderRadius.circular(12),
                color: _editorSoftSurface,
                boxShadow: [
                  if (isSelected)
                    BoxShadow(
                      color: _editorPrimaryAccent.withValues(alpha: 0.28),
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
                      future: _getTimelineCardThumbnail(clip),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data != null) {
                          return Image.memory(
                            snapshot.data!,
                            fit: BoxFit.cover,
                          );
                        }
                        return const Center(
                          child: Icon(Icons.movie, color: _editorTextMuted),
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
                            durationSec = clipDurationBadgeSeconds(
                              durationToDisplay,
                            );
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
    const double trackHeight = 70.0;
    const double outerHeight = 90.0;

    if (itemWidth.isNaN || maxMs.isNaN || itemWidth <= 0 || maxMs <= 0) {
      return Container(height: outerHeight, color: Colors.red);
    }

    return Container(
      width: itemWidth,
      height: outerHeight,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _editorGlassSurface,
        borderRadius: BorderRadius.circular(_editorRadius),
        border: Border.all(color: _editorStroke),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: SizedBox(
        height: trackHeight,
        child: FutureBuilder<List<Uint8List>>(
          future: _getTrimTimelineFuture(clip, maxMs.toInt()),
          builder: (context, snapshot) {
            final thumbs = snapshot.data ?? const <Uint8List>[];
            return Builder(
              builder: (timelineContext) => Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: thumbs.isEmpty
                          ? Container(
                              color: _editorSoftSurface,
                              child: const Center(
                                child: Icon(
                                  Icons.movie,
                                  color: _editorTextMuted,
                                ),
                              ),
                            )
                          : Row(
                              children: thumbs
                                  .map(
                                    (thumb) => Expanded(
                                      child: Container(
                                        color: Colors.black,
                                        child: Image.memory(
                                          thumb,
                                          fit: BoxFit.contain,
                                        ),
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
                          height: trackHeight,
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
                          height: trackHeight,
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
                    height: trackHeight,
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
                        newStartMs = newStartMs.clamp(0.0, state.endMs - 100);
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
                        height: trackHeight,
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
                          state.startMs + 100,
                          state.maxMs,
                        );
                        if ((newEndMs - clip.endTime.inMilliseconds).abs() <
                            4) {
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
                        height: trackHeight,
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
                            height: trackHeight,
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
      ),
    );
  }

  Future<List<Uint8List>> _getTrimTimelineFuture(
    VlogClip clip,
    int durationMs,
  ) {
    final clipPath = _timelineSourcePathForClip(clip);
    final count = VideoManager.trimTimelineThumbCount;
    final key = '${clip.path}|$clipPath|$durationMs|$count';
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

  Future<void> _moveToAdjacentClip(int direction) async {
    if (_clips.isEmpty || _isDisposed || !_canUseTopClipNavigation) return;
    final target = (_currentClipIndex + direction).clamp(0, _clips.length - 1);
    if (target == _currentClipIndex) return;
    if (_isTransformModeActive) {
      _commitTransformGesture();
    }
    if (_isBrightnessMode) {
      _commitBrightnessGesture();
    }
    await _loadClip(target, autoPlay: _isPlaying);
  }

  void _handlePreviewSwipe(DragEndDetails details) {
    if (_isTransformModeActive || _isTrimMode || _isPlaybackLockedForEditing) {
      return;
    }

    final velocityX = details.primaryVelocity ?? 0.0;
    if (velocityX <= -220) {
      unawaited(_moveToAdjacentClip(1));
      return;
    }
    if (velocityX >= 220) {
      unawaited(_moveToAdjacentClip(-1));
    }
  }

  // 'Done' / 'Export' 버튼 클릭 시 호출
  Future<void> _handleExport() async {
    if (_isExportInProgress) return;
    final exportTier = await _refreshSubscriptionRuntimeTier(
      reason: 'export_button',
      notifyUser: true,
    );
    if (!mounted || _isDisposed) return;

    // Safety Net: Check local files before export dialog.
    // Cloud-only clips are materialized after the user confirms export.
    for (final clip in _clips) {
      if (!_isCloudOnlyClipPath(clip.path) && !File(clip.path).existsSync()) {
        showDialog(
          context: context,
          barrierColor: _editorModalBarrier,
          builder: (context) => AlertDialog(
            backgroundColor: _editorSoftSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_editorRadiusLarge),
              side: const BorderSide(color: _editorStroke),
            ),
            title: const Text(
              "Error",
              style: TextStyle(color: Colors.redAccent),
            ),
            content: const Text(
              "원본 파일이 손상되어 내보낼 수 없습니다.\n(Source file missing)",
              style: TextStyle(color: _editorTextPrimary),
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
    _showExportDialog(exportTier);
  }

  void _showExportDialog(UserTier exportTier) {
    if (_isExportInProgress) return;

    final exportQualities = availableExportQualities(exportTier);
    String selectedQuality = defaultExportQuality(exportTier);

    showDialog(
      context: context,
      barrierColor: _editorModalBarrier,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: _editorSoftSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_editorRadiusLarge),
                side: const BorderSide(color: _editorStroke),
              ),
              title: const Text(
                "Export Quality",
                style: TextStyle(color: _editorTextPrimary),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: exportQualities
                    .map(
                      (quality) => _buildQualityOption(
                        label: _exportQualityOptionLabel(quality),
                        value: quality,
                        selected: selectedQuality == quality,
                        enabled: true,
                        onChanged: (val) {
                          final clamped = clampExportQuality(exportTier, val);
                          setStateDialog(() => selectedQuality = clamped);
                          _updateProjectQuality(clamped, tier: exportTier);
                        },
                      ),
                    )
                    .toList(),
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
                    backgroundColor: _editorPrimaryAccent,
                    foregroundColor: const Color(0xFF07111F),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _performNativeExport(
                      clampExportQuality(exportTier, selectedQuality),
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

  String _exportQualityOptionLabel(String quality) {
    final label = exportQualityLabel(quality);
    if (quality == kQuality720p) return '$label (Basic)';
    return label;
  }

  String _runtimeTierKey(UserTier tier) {
    switch (normalizeRuntimeUserTier(tier)) {
      case UserTier.standard:
        return kUserTierStandard;
      case UserTier.premium:
        return kUserTierStandard;
      case UserTier.free:
        return kUserTierFree;
    }
  }

  void _updateProjectQuality(String newQuality, {UserTier? tier}) {
    final userStatus = Provider.of<UserStatusManager>(context, listen: false);
    final resolvedTier = tier ?? _effectiveTierForEditWrite(userStatus);
    final normalized = clampExportQuality(resolvedTier, newQuality);
    if (widget.project.quality != normalized) {
      widget.project.quality = normalized;
      unawaited(_enqueueAutosave(reason: 'quality_change'));
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
        style: TextStyle(color: enabled ? _editorTextPrimary : Colors.white24),
      ),
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: enabled
            ? (selected ? _editorPrimaryAccent : _editorTextPrimary)
            : Colors.white24,
      ),
      trailing: enabled
          ? null
          : const Icon(Icons.lock, size: 16, color: Colors.white24),
      onTap: enabled ? () => onChanged(value) : null,
    );
  }

  Future<void> _performNativeExport(String quality) async {
    if (_isExportInProgress) return;

    final videoManager = Provider.of<VideoManager>(context, listen: false);
    var exportTier = await _refreshSubscriptionRuntimeTier(
      reason: 'export_start',
      notifyUser: true,
    );
    var finalQuality = clampExportQuality(exportTier, quality);
    var userTierKey = _runtimeTierKey(exportTier);

    if (!mounted || _isDisposed) return;
    setState(() {
      _isExportInProgress = true;
      _isExportCancelRequested = false;
    });

    _openExportProgressDialog();
    _setExportProgress(
      phase: 'prepare',
      label: '내보내기 준비 중',
      progress: _defaultExportProgressForPhase('prepare'),
    );

    await _prepareForExportRendering();
    if (!mounted || _isDisposed) {
      await _closeExportProgressDialog();
      return;
    }
    if (_isExportCancelRequested) {
      await _closeExportProgressDialog();
      return;
    }

    exportTier = await _refreshSubscriptionRuntimeTier(
      reason: 'export_pre_save',
      notifyUser: true,
    );
    finalQuality = clampExportQuality(exportTier, finalQuality);
    userTierKey = _runtimeTierKey(exportTier);

    debugPrint('[EditScreen][Export] open loading dialog mounted=$mounted');
    final exportSessionCachePaths = <String>[];

    try {
      // Sync State to Project before Export
      // widget.project.clips is already updated via reference in _clips (if we modified objects directly)
      // If _clips are copies, we'd need to sync back.
      // Assuming _clips are references or we need to update project.clips:
      widget.project.clips = _clips.map((clip) => clip.copyWith()).toList();

      widget.project.bgmPath = _currentState.bgmPath;
      widget.project.bgmVolume = _currentState.bgmVolume;
      widget.project.quality = finalQuality;
      widget.project.brightnessAdjustmentScope =
          kBrightnessAdjustmentScopeProjectWide;
      widget.project.brightnessAdjustments = normalizeBrightnessAdjustments(
        _brightnessAdjustments,
      );
      widget.project.colorFilterPresetId = normalizeColorFilterPresetId(
        _selectedColorFilterPresetId,
      );
      widget.project.colorFilterIntensity = normalizeColorFilterIntensity(
        _colorFilterIntensity,
      );

      await _runExportPreflight(
        videoManager: videoManager,
        quality: finalQuality,
      );

      _setExportProgress(
        phase: 'materialize',
        label: 'Preparing export sources',
        progress: 0.32,
      );

      final exportClips = await _resolveExportClips();
      if (exportClips == null || _isExportCancelRequested) {
        await _closeExportProgressDialog();
        return;
      }
      exportSessionCachePaths.addAll(
        exportClips
            .map((clip) => clip.path)
            .where((path) => path.contains('export_session_cache')),
      );

      final hasCachePathInProject = widget.project.clips.any(
        (clip) => clip.path.contains('cloud_clip_session_cache'),
      );
      debugPrint(
        '[EditScreen][Export][CloudClip][inputs_ready] '
        'clipCount=${exportClips.length} '
        'cloudOnlyProjectClipCount=${widget.project.clips.where((clip) => _isCloudOnlyClipPath(clip.path)).length} '
        'materializedClipCount=${exportClips.where((clip) => clip.path.contains('export_session_cache')).length} '
        'projectHasCachePath=$hasCachePathInProject',
      );

      _setExportProgress(
        phase: 'rendering',
        label: '내보내기 렌더링 중',
        progress: _defaultExportProgressForPhase('rendering'),
      );

      final resultPath = await videoManager.exportVlog(
        clips: exportClips,
        audioConfig: widget.project.audioConfig,
        bgmPath: widget.project.bgmPath,
        bgmVolume: widget.project.bgmVolume,
        quality: widget.project.quality,
        userTier: userTierKey,
        canvasAspectRatioPreset: widget.project.canvasAspectRatioPreset,
        brightnessAdjustments: _currentState.brightnessAdjustments,
        colorFilterPresetId: _currentState.colorFilterPresetId,
        colorFilterIntensity: _currentState.colorFilterIntensity,
        mergeSessionId: _editExportSessionId,
        debugTag: 'VideoEditScreen_export',
        isCancelRequested: () => _isExportCancelRequested,
        getExportPhase: () => _exportProgressPhase,
        getExportProgress: () => _exportDialogProgress,
        getExportCancelReason: () => _exportCancelReason ?? '',
      );

      if (_isExportCancelRequested) {
        if (mounted && resultPath != null) {
          Fluttertoast.showToast(msg: '내보내기가 취소되었습니다.');
        }
        await _closeExportProgressDialog();
        if (mounted) {
          setState(() {
            _isExportInProgress = false;
          });
        }
        return;
      }

      if (!mounted) return;
      debugPrint('[EditScreen][Export] close loading dialog mounted=$mounted');
      _updateExportProgress('갤러리 저장 중', 0.75);

      if (resultPath != null) {
        _setExportProgress(
          phase: 'done',
          label: '내보내기 완료',
          progress: _defaultExportProgressForPhase('done'),
        );
        await _closeExportProgressDialog();
        if (!mounted || _isDisposed) return;
        Fluttertoast.showToast(msg: "Vlog가 생성되어 갤러리에 저장되었습니다. 🎉");
        Navigator.pop(
          context,
          resultPath,
        ); // Return export result path for in-app preview
      } else {
        await _closeExportProgressDialog();
        if (!mounted || _isDisposed) return;
        Fluttertoast.showToast(msg: "Vlog 생성에 실패했습니다.");
        Navigator.pop(context, false);
      }
    } on _ExportClipResolveException catch (e) {
      if (mounted) {
        await _closeExportProgressDialog();
      }
      final reason = e.cloudFailureCode?.name ?? e.message;
      final isCloudFailure = e.cloudFailureCode != null;
      _markExportSourceFailureForUi(e);
      Fluttertoast.showToast(
        msg: isCloudFailure
            ? "Cloud Clip을 불러오지 못해 내보내기를 진행할 수 없습니다. ($reason)"
            : "원본 파일이 손상되어 내보낼 수 없습니다. ($reason)",
      );
      debugPrint(
        '[EditScreen][Export][CloudClip][failed] '
        'index=${e.index} reason=$reason',
      );
    } on _ExportPreflightException catch (e) {
      if (mounted) {
        await _closeExportProgressDialog();
      }
      Fluttertoast.showToast(msg: "Export preflight failed: ${e.message}");
      debugPrint(
        '[EditScreen][Export][Preflight][failed] '
        'code=${e.code} message=${e.message}',
      );
    } catch (e) {
      if (mounted) {
        await _closeExportProgressDialog();
      }
      Fluttertoast.showToast(msg: "Error: $e");
    } finally {
      unawaited(
        _cleanupSessionCacheBestEffort(
          trigger: 'export_end',
          protectedPaths: exportSessionCachePaths,
        ),
      );
      if (mounted) {
        setState(() {
          _isExportInProgress = false;
        });
      }
      _isExportCancelRequested = false;
    }
  }

  Widget _buildEditorSheetHandle() {
    return Center(
      child: Container(
        width: 44,
        height: 5,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  ChoiceChip _buildEditorChoiceChip({
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: onSelected,
      selectedColor: _editorChipSelected,
      backgroundColor: _editorChipSurface,
      disabledColor: _editorChipSurface.withValues(alpha: 0.55),
      side: BorderSide(
        color: selected
            ? _editorPrimaryAccent.withValues(alpha: 0.72)
            : _editorHeaderStroke,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      labelStyle: TextStyle(
        color: selected ? _editorChipSelectedText : _editorChipText,
        fontSize: 13,
        fontWeight: FontWeight.w800,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  // ignore: unused_element
  void _showSoundMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: _editorModalBarrier,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: 420,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              decoration: BoxDecoration(
                color: _editorSoftSurface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
                border: Border.all(color: _editorStroke),
                boxShadow: _editorPanelShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildEditorSheetHandle(),
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
                            colorFilterPresetId:
                                _currentState.colorFilterPresetId,
                            colorFilterIntensity:
                                _currentState.colorFilterIntensity,
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
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          foregroundColor: _textPrimary,
                          side: const BorderSide(color: _editorStroke),
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
                              colorFilterPresetId:
                                  _currentState.colorFilterPresetId,
                              colorFilterIntensity:
                                  _currentState.colorFilterIntensity,
                            );

                            _executeStateChange(newState);
                            setModalState(() {}); // Refresh modal UI
                          }
                        },
                      ),
                      if (_bgmPath != null)
                        IconButton(
                          icon: const Icon(
                            Icons.delete,
                            color: Color(0xFFFF6B6B),
                          ),
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
                              colorFilterPresetId:
                                  _currentState.colorFilterPresetId,
                              colorFilterIntensity:
                                  _currentState.colorFilterIntensity,
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
                        colorFilterPresetId: _currentState.colorFilterPresetId,
                        colorFilterIntensity:
                            _currentState.colorFilterIntensity,
                      );
                      _executeStateChange(newState);
                    },
                  ),
                  const SizedBox(height: 20),
                  _buildAudioSliderRow(
                    icon: Icons.music_note,
                    label: 'BGM',
                    value: _bgmVolume,
                    color: _editorSecondaryAccent,
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
                        colorFilterPresetId: _currentState.colorFilterPresetId,
                        colorFilterIntensity:
                            _currentState.colorFilterIntensity,
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
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, color: color, size: 20),
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
              activeTrackColor: color,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: color.withValues(alpha: 0.18),
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
      barrierColor: _editorModalBarrier,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            String selectedAspect = widget.project.canvasAspectRatioPreset;
            String selectedBgMode = widget.project.canvasBackgroundMode;
            return Container(
              height: 286,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              decoration: BoxDecoration(
                color: _editorSoftSurface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
                border: Border.all(color: _editorStroke),
                boxShadow: _editorPanelShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildEditorSheetHandle(),
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
                    children: ['r9_16', 'r3_4', 'r4_3', 'r1_1', 'r16_9'].map((
                      preset,
                    ) {
                      final selected = selectedAspect == preset;
                      return _buildEditorChoiceChip(
                        label: _canvasAspectLabel(preset),
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
                      color: _editorTextPrimary,
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
                      return _buildEditorChoiceChip(
                        label: mode,
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

  // ignore: unused_element
  void _showFilterDialog() {
    if (!_enableDormantEditFeatures) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      barrierColor: _editorModalBarrier,
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
                    colorFilterPresetId: _currentState.colorFilterPresetId,
                    colorFilterIntensity: _currentState.colorFilterIntensity,
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
    if (!_enableDormantEditFeatures) return;
    final controller = TextEditingController(text: editing?.text ?? '');

    final result = await showDialog<String>(
      context: context,
      barrierColor: _editorModalBarrier,
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
        colorFilterPresetId: _currentState.colorFilterPresetId,
        colorFilterIntensity: _currentState.colorFilterIntensity,
      );
      _executeStateChange(nextState);
    }
  }

  // ignore: unused_element
  void _showStickerLibrary() {
    if (!_enableDormantEditFeatures) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      barrierColor: _editorModalBarrier,
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
    if (!_enableDormantEditFeatures) return;
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
      colorFilterPresetId: _currentState.colorFilterPresetId,
      colorFilterIntensity: _currentState.colorFilterIntensity,
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
