import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../constants/clip_policy.dart';
import '../main.dart';
import '../managers/video_manager.dart';
import '../utils/haptics.dart';

enum _PreviewAspectPreset { ratio9x16, ratio3x4, ratio1x1 }

enum _CaptureFlowState { idle, preparing, recording, stopping, saving, error }

enum _CaptureQualityMode { auto, p1080, p4k }

extension _PreviewAspectPresetX on _PreviewAspectPreset {
  double get aspectRatio {
    switch (this) {
      case _PreviewAspectPreset.ratio9x16:
        return 9 / 16;
      case _PreviewAspectPreset.ratio3x4:
        return 3 / 4;
      case _PreviewAspectPreset.ratio1x1:
        return 1.0;
    }
  }

  String get label {
    switch (this) {
      case _PreviewAspectPreset.ratio9x16:
        return '9:16';
      case _PreviewAspectPreset.ratio3x4:
        return '3:4';
      case _PreviewAspectPreset.ratio1x1:
        return '1:1';
    }
  }
}

extension _CaptureQualityModeX on _CaptureQualityMode {
  String get label {
    switch (this) {
      case _CaptureQualityMode.auto:
        return 'Auto';
      case _CaptureQualityMode.p1080:
        return '1080p';
      case _CaptureQualityMode.p4k:
        return '4K';
    }
  }
}

class CaptureScreen extends StatefulWidget {
  final GlobalKey recordButtonKey;

  const CaptureScreen({super.key, required this.recordButtonKey});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with TickerProviderStateMixin {
  static final Map<String, ResolutionPreset> _lastSuccessfulPresetByLens =
      <String, ResolutionPreset>{};
  static final Map<String, bool> _probe4kSupportByLens = <String, bool>{};
  static final Map<String, Future<bool>> _probe4kSupportFutureByLens =
      <String, Future<bool>>{};

  CameraController? _controller;

  _CaptureFlowState _flowState = _CaptureFlowState.idle;
  int _remainingTime = kTargetClipSecForDisplay;
  static const int _targetRecordingMilliseconds = kTargetCaptureMs;
  Timer? _recordingTimer;
  Offset? _tapPosition;
  late AnimationController _focusAnimController;

  double _exposureOffset = 0.0;
  double _minExposure = 0.0;
  double _maxExposure = 0.0;
  bool _showExposureSlider = false;
  Timer? _exposureTimer;
  Stopwatch? _recordingStopwatch;
  bool _hasRecordingActuallyStarted = false;
  bool _isCheckingCameraPermission = false;

  int _cameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _pinchStartZoom = 1.0;
  double? _lastZoomDiagValue;
  String? _lastZoomDiagZone;
  bool _showExtendedZoomSlider = false;
  bool _isInitializingCamera = false;
  bool _isCameraLocked = false;
  bool _didPrepareForRecording = false;
  bool _didReportPreviewReady = false;
  String? _cameraError;
  String? _flowError;
  double? _lockedPreviewAspect;
  _CaptureQualityMode _selectedQualityMode = _CaptureQualityMode.p1080;
  bool _supports4kCapture = false;
  _PreviewAspectPreset _selectedAspectPreset = _PreviewAspectPreset.ratio9x16;
  int _cameraInitSequence = 0;
  PermissionStatus _cameraPermissionStatus = PermissionStatus.denied;

  late VideoManager videoManager;

  bool get _hasInitializedController =>
      _controller != null && _controller!.value.isInitialized;

  bool get _isBusyRecordingFlow =>
      _flowState == _CaptureFlowState.preparing ||
      _flowState == _CaptureFlowState.recording ||
      _flowState == _CaptureFlowState.stopping ||
      _flowState == _CaptureFlowState.saving;

  bool get _canStartRecording =>
      _flowState == _CaptureFlowState.idle ||
      _flowState == _CaptureFlowState.error;

  bool get _hasGrantedCameraPermission =>
      _cameraPermissionStatus == PermissionStatus.granted;

  bool get _isPermissionBlockedPermanently =>
      _cameraPermissionStatus == PermissionStatus.permanentlyDenied ||
      _cameraPermissionStatus == PermissionStatus.restricted;

  bool get _canStopRecording => _flowState == _CaptureFlowState.recording;

  double _toPortraitAspect(double rawAspect) {
    return rawAspect > 1 ? 1 / rawAspect : rawAspect;
  }

  DeviceOrientation _getApplicablePreviewOrientation(CameraValue value) {
    if (value.isRecordingVideo) {
      return value.recordingOrientation ??
          value.lockedCaptureOrientation ??
          value.deviceOrientation;
    }
    return value.previewPauseOrientation ??
        value.lockedCaptureOrientation ??
        value.deviceOrientation;
  }

  int _getPreviewQuarterTurns(DeviceOrientation orientation) {
    switch (orientation) {
      case DeviceOrientation.portraitUp:
        return 0;
      case DeviceOrientation.landscapeRight:
        return 1;
      case DeviceOrientation.portraitDown:
        return 2;
      case DeviceOrientation.landscapeLeft:
        return 3;
    }
  }

  void _logCaptureRotationDiag(String phase) {
    if (!_hasInitializedController) {
      debugPrint('[CaptureRotationDiag] phase=$phase controller=uninitialized');
      return;
    }
    final value = _controller!.value;
    final appliedOrientation = _getApplicablePreviewOrientation(value);
    debugPrint(
      '[CaptureRotationDiag] '
      'phase=$phase '
      'orientation=${value.deviceOrientation} '
      'locked=${value.lockedCaptureOrientation} '
      'recordingOrientation=${value.recordingOrientation} '
      'previewPauseOrientation=${value.previewPauseOrientation} '
      'appliedOrientation=$appliedOrientation '
      'quarterTurns=${_getPreviewQuarterTurns(appliedOrientation)} '
      'aspect=${value.aspectRatio} '
      'preview=${value.previewSize} '
      'recording=${value.isRecordingVideo}',
    );
  }

  Future<void> _toggleFlash() async {
    if (!_hasInitializedController ||
        _isCameraLocked ||
        !_hasGrantedCameraPermission) {
      return;
    }

    final newMode = _flashMode == FlashMode.off
        ? FlashMode.torch
        : FlashMode.off;
    try {
      await _controller!.setFlashMode(newMode);
      setState(() => _flashMode = newMode);
      hapticFeedback();
    } catch (e) {
      debugPrint('[Capture] Flash error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _focusAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _initCamera();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    videoManager = Provider.of<VideoManager>(context, listen: false);
  }

  void _initCamera() {
    unawaited(_initializeCameraFlow());
  }

  Future<void> _initializeCameraFlow() async {
    final hasPermission = await _ensureCameraPermission(requestIfDenied: false);
    if (!mounted || !hasPermission) {
      return;
    }
    if (_isInitializingCamera) return;

    await _initCameraAsync();
  }

  String _cameraPermissionGuideText(PermissionStatus status) {
    if (status.isPermanentlyDenied || status.isRestricted) {
      return '카메라 권한이 차단되었습니다. 앱 설정에서 카메라 접근을 허용해 주세요.';
    }
    if (status.isGranted) {
      return '';
    }
    return '카메라 권한이 필요합니다. 권한 요청 버튼을 눌러 허용해 주세요.';
  }

  Future<bool> _ensureCameraPermission({required bool requestIfDenied}) async {
    if (_isCheckingCameraPermission) {
      return _hasGrantedCameraPermission;
    }

    _isCheckingCameraPermission = true;
    try {
      final status = await Permission.camera.status;
      if (!mounted) return false;

      _cameraPermissionStatus = status;
      if (status.isGranted) {
        _cameraError = null;
        return true;
      }

      if (!requestIfDenied || status.isPermanentlyDenied || status.isRestricted) {
        setState(() {
          _cameraError = _cameraPermissionGuideText(status);
        });
        return false;
      }

      final requested = await Permission.camera.request();
      if (!mounted) return false;
      _cameraPermissionStatus = requested;

      if (requested.isGranted) {
        setState(() {
          _cameraError = null;
          _flowError = null;
        });
        return true;
      }

      setState(() {
        _cameraError = _cameraPermissionGuideText(requested);
      });
      return false;
    } finally {
      _isCheckingCameraPermission = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _openCameraSystemSettings() async {
    await openAppSettings();
    if (!mounted) return;

    final hasPermission = await _ensureCameraPermission(requestIfDenied: false);
    if (hasPermission) {
      await _initCameraAsync();
    }
  }

  Future<void> _requestCameraPermissionFromUi() async {
    final granted = await _ensureCameraPermission(requestIfDenied: true);
    if (!mounted) return;
    if (granted) {
      await _initCameraAsync();
      return;
    }
    setState(() {
      _flowError = '권한 허용 전에는 촬영을 시작할 수 없습니다.';
    });
  }

  String _lensCacheKey(CameraDescription description) {
    return '${description.lensDirection.name}:${description.name}';
  }

  List<ResolutionPreset> _orderedResolutionCandidatesForMode(
    _CaptureQualityMode mode,
    String lensKey,
  ) {
    final base = List<ResolutionPreset>.from(_resolutionCandidatesForMode(mode));
    final cached = _lastSuccessfulPresetByLens[lensKey];
    if (cached == null) return base;
    final reordered = <ResolutionPreset>[cached];
    reordered.addAll(base.where((preset) => preset != cached));
    return reordered;
  }

  List<ResolutionPreset> _resolutionCandidatesForMode(_CaptureQualityMode mode) {
    switch (mode) {
      case _CaptureQualityMode.auto:
        return const <ResolutionPreset>[
          ResolutionPreset.veryHigh,
          ResolutionPreset.high,
          ResolutionPreset.medium,
          ResolutionPreset.low,
        ];
      case _CaptureQualityMode.p1080:
        return const <ResolutionPreset>[
          ResolutionPreset.veryHigh,
          ResolutionPreset.high,
          ResolutionPreset.medium,
        ];
      case _CaptureQualityMode.p4k:
        return const <ResolutionPreset>[
          ResolutionPreset.ultraHigh,
          ResolutionPreset.veryHigh,
          ResolutionPreset.high,
          ResolutionPreset.medium,
        ];
    }
  }

  Future<bool> _probe4kSupport(CameraDescription description) async {
    final lensKey = _lensCacheKey(description);
    final cached = _probe4kSupportByLens[lensKey];
    if (cached != null) {
      logFirstCameraPreviewStage(
        'probe_4k_done',
        detail: 'lens=$lensKey cached=true supported=$cached',
      );
      return cached;
    }

    final inFlight = _probe4kSupportFutureByLens[lensKey];
    if (inFlight != null) {
      final result = await inFlight;
      logFirstCameraPreviewStage(
        'probe_4k_done',
        detail: 'lens=$lensKey cached=false shared_future=true supported=$result',
      );
      return result;
    }

    final future = () async {
      bool supported = false;
      final probe = CameraController(
        description,
        ResolutionPreset.ultraHigh,
        enableAudio: true,
      );
      try {
        await probe.initialize();
        supported = true;
      } catch (_) {
        supported = false;
      } finally {
        try {
          await probe.dispose();
        } catch (_) {}
      }
      _probe4kSupportByLens[lensKey] = supported;
      return supported;
    }();

    _probe4kSupportFutureByLens[lensKey] = future;
    try {
      final result = await future;
      logFirstCameraPreviewStage(
        'probe_4k_done',
        detail: 'lens=$lensKey cached=false supported=$result',
      );
      return result;
    } finally {
      _probe4kSupportFutureByLens.remove(lensKey);
    }
  }

  Future<void> _runPostPreviewCameraSetup(
    CameraController controller,
    int initToken,
  ) async {
    try {
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } catch (e) {
      debugPrint('[Capture] lockCaptureOrientation(portraitUp) failed: $e');
    }

    try {
      await controller.setFocusMode(FocusMode.auto);
    } catch (e) {
      debugPrint('[Capture] setFocusMode(auto) failed: $e');
    }
    try {
      await controller.setExposureMode(ExposureMode.auto);
    } catch (e) {
      debugPrint('[Capture] setExposureMode(auto) failed: $e');
    }

    try {
      final minExposure = await controller.getMinExposureOffset();
      final maxExposure = await controller.getMaxExposureOffset();
      final minZoom = await controller.getMinZoomLevel();
      final maxZoom = await controller.getMaxZoomLevel();
      final clampedZoom = _currentZoom.clamp(minZoom, maxZoom);
      await controller.setZoomLevel(clampedZoom);
      logFirstCameraPreviewStage('exposure_zoom_query_done');

      if (!mounted || _cameraInitSequence != initToken || _controller != controller) {
        return;
      }
      setState(() {
        _minExposure = minExposure;
        _maxExposure = maxExposure;
        _minZoom = minZoom;
        _maxZoom = maxZoom;
        _currentZoom = clampedZoom;
      });
    } catch (e) {
      debugPrint('[Capture] Post-preview exposure/zoom setup failed: $e');
    }
  }

  Future<void> _initCameraAsync() async {
    if (!_hasGrantedCameraPermission) {
      if (mounted) {
        setState(() {
          _cameraError = '카메라 권한이 없습니다.';
        });
      }
      return;
    }

    if (_isInitializingCamera) return;
    if (!mounted) return;

    if (cameras.isEmpty) {
      setState(() {
        _cameraError = 'No camera found.';
        _isInitializingCamera = false;
      });
      return;
    }

    _isInitializingCamera = true;
    final initToken = ++_cameraInitSequence;
    _cameraError = null;
    final previousController = _controller;
    _controller = null;
    if (mounted) setState(() {});

    if (previousController != null) {
      try {
        await previousController.dispose();
      } catch (e) {
        debugPrint('[Capture] Previous controller dispose failed: $e');
      }
    }

    final description = cameras[_cameraIndex];
    final lensKey = _lensCacheKey(description);
    final cached4k = _probe4kSupportByLens[lensKey];
    if (cached4k != null) {
      _supports4kCapture = cached4k;
    }

    if (_selectedQualityMode == _CaptureQualityMode.p4k && cached4k == null) {
      _supports4kCapture = await _probe4kSupport(description);
    }

    final effectiveMode =
        (_selectedQualityMode == _CaptureQualityMode.p4k && !_supports4kCapture)
        ? _CaptureQualityMode.p1080
        : _selectedQualityMode;

    CameraController? newController;
    logFirstCameraPreviewStage(
      'candidate_selection_start',
      detail: 'lens=$lensKey mode=${effectiveMode.name}',
    );
    final candidates = _orderedResolutionCandidatesForMode(effectiveMode, lensKey);
    logFirstCameraPreviewStage(
      'candidate_selection_end',
      detail:
          'lens=$lensKey candidates=${candidates.map((e) => e.name).join(',')}',
    );
    final visited = <ResolutionPreset>{};

    for (final preset in candidates) {
      if (visited.contains(preset)) continue;
      visited.add(preset);

      final candidate = CameraController(
        description,
        preset,
        enableAudio: true,
      );

      try {
        logFirstCameraPreviewStage(
          'controller_initialize_start',
          detail: 'lens=$lensKey preset=${preset.name}',
        );
        await candidate.initialize();
        logFirstCameraPreviewStage(
          'controller_initialize_end',
          detail: 'lens=$lensKey preset=${preset.name} success=true',
        );
        newController = candidate;
        _lastSuccessfulPresetByLens[lensKey] = preset;
        break;
      } catch (e) {
        await candidate.dispose();
        logFirstCameraPreviewStage(
          'controller_initialize_end',
          detail: 'lens=$lensKey preset=${preset.name} success=false',
        );
        debugPrint('[Capture] Initialize with $preset failed: $e');
      }
    }

    if (newController == null) {
      setState(() {
        _cameraError = 'Camera initialize failed.';
      });
      _isInitializingCamera = false;
      if (mounted) {
        setState(() {});
      }
      return;
    }

    try {
      _lockedPreviewAspect = _toPortraitAspect(newController.value.aspectRatio);

      _controller = newController;
      _cameraError = null;
      _focusAnimController.reset();
      _showExposureSlider = false;
      _flowState = _CaptureFlowState.idle;
      _flowError = null;
      _recordingTimer?.cancel();
      _recordingTimer = null;
      _didPrepareForRecording = false;
      _didReportPreviewReady = false;

      unawaited(_runPostPreviewCameraSetup(newController, initToken));
    } catch (e) {
      await newController.dispose();
      if (mounted) {
        setState(() {
          _cameraError = 'Camera setup failed.';
        });
      }
    } finally {
      _isInitializingCamera = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _toggleCamera() async {
    if (_isCameraLocked ||
        cameras.length <= 1 ||
        _isBusyRecordingFlow ||
        !_hasGrantedCameraPermission) {
      return;
    }
    _isCameraLocked = true;

    try {
      _cancelRecordingTimer();
      if (_controller != null) {
        await _controller!.dispose();
      }
      _controller = null;

      _cameraIndex = (_cameraIndex + 1) % cameras.length;
      await _initCameraAsync();
    } catch (e) {
      debugPrint('[Capture] Toggle camera error: $e');
    } finally {
      _isCameraLocked = false;
    }
  }

  Future<void> _startRecording() async {
    if (!_hasInitializedController ||
        _isCameraLocked ||
        !_canStartRecording ||
        !_hasGrantedCameraPermission) {
      return;
    }
    _recordingStopwatch = null;
    _recordingTimer?.cancel();
    _recordingTimer = null;

    try {
      _logCaptureRotationDiag('start_before');
      setState(() {
        _flowState = _CaptureFlowState.preparing;
        _flowError = null;
        _remainingTime = kTargetClipSecForDisplay;
        _hasRecordingActuallyStarted = false;
      });

      await _controller!.lockCaptureOrientation(DeviceOrientation.portraitUp);

      if (!_didPrepareForRecording) {
        try {
          await _controller!.prepareForVideoRecording();
        } catch (e) {
          debugPrint('[Capture] prepareForVideoRecording unsupported: $e');
        } finally {
          _didPrepareForRecording = true;
        }
      }

      await _controller!.startVideoRecording();
      _logCaptureRotationDiag('start_after');

      if (!mounted) return;

      setState(() {
        _flowState = _CaptureFlowState.recording;
        _hasRecordingActuallyStarted = true;
      });
      _startRecordingTimer();

      _logCaptureRotationDiag('start_invoked');
    } catch (e) {
      setState(() {
        _flowState = _CaptureFlowState.error;
        _flowError = '녹화를 시작하지 못했습니다.';
        _remainingTime = kTargetClipSecForDisplay;
        _hasRecordingActuallyStarted = false;
      });
      debugPrint('[Capture] Start recording error: $e');
    }
  }

  void _startRecordingTimer() {
    _recordingStopwatch = Stopwatch()..start();
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) {
      final elapsedMs = _recordingStopwatch?.elapsedMilliseconds ?? 0;
      final remainMs = _targetRecordingMilliseconds - elapsedMs;

      if (!mounted) {
        timer.cancel();
        return;
      }

      if (!_canStopRecording) {
        timer.cancel();
        return;
      }

      if (elapsedMs >= _targetRecordingMilliseconds) {
        setState(() => _remainingTime = 0);
        _stopRecording();
        timer.cancel();
      } else {
        final displayRemainMs = remainMs > 0 ? remainMs : 0;
        final countdown = ((((displayRemainMs - 1) ~/ 1000) + 1).clamp(
          0,
          kTargetClipSecForDisplay,
        ));
        setState(() => _remainingTime = countdown);
      }
    });
  }

  void _cancelRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _recordingStopwatch?.stop();
    _recordingStopwatch = null;
    _hasRecordingActuallyStarted = false;
  }

  Future<void> _stopRecording() async {
    if (!_hasGrantedCameraPermission) return;
    if (!_canStopRecording) return;
    setState(() {
      _flowState = _CaptureFlowState.stopping;
      _flowError = null;
    });

    _cancelRecordingTimer();
    try {
      debugPrint(
        '[Capture] stop_recording targetCaptureMs=$_targetRecordingMilliseconds '
        'targetSaveMs=$kTargetClipSaveMs targetUiSec=$kTargetClipSecForDisplay',
      );
      _logCaptureRotationDiag('stop_before');
      final video = await _controller!.stopVideoRecording();
      _logCaptureRotationDiag('stop_after');
      if (mounted) {
        setState(() {
          _flowState = _CaptureFlowState.saving;
          _hasRecordingActuallyStarted = false;
        });
      }
      await _controller!.setExposureMode(ExposureMode.auto);
      await videoManager.saveRecordedVideo(video);
      if (mounted) {
        setState(() {
          _flowState = _CaptureFlowState.idle;
          _remainingTime = kTargetClipSecForDisplay;
          _flowError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _flowState = _CaptureFlowState.error;
          _flowError = '녹화 저장에 실패했습니다.';
          _remainingTime = kTargetClipSecForDisplay;
          _hasRecordingActuallyStarted = false;
        });
      }
      debugPrint('[Capture] Stop recording error: $e');
    } finally {
      if (mounted) {
        setState(() {
          if (_flowState != _CaptureFlowState.error) {
            _flowState = _CaptureFlowState.idle;
          }
          _remainingTime = kTargetClipSecForDisplay;
          _hasRecordingActuallyStarted = false;
        });
      }
    }
  }

  Future<void> _handleFocus(TapDownDetails d, BoxConstraints c) async {
    if (!_hasInitializedController ||
        _isCameraLocked ||
        !_hasGrantedCameraPermission) {
      return;
    }

    final Offset localPosition = d.localPosition;
    final double x = localPosition.dx / c.maxWidth;
    final double y = localPosition.dy / c.maxHeight;
    await _controller!.setFocusPoint(Offset(x, y));
    await _controller!.setExposurePoint(Offset(x, y));
    setState(() {
      _tapPosition = localPosition;
      _showExposureSlider = true;
    });
    _focusAnimController.forward(from: 0.0);
    _startExposureTimer();
  }

  void _startExposureTimer() {
    _exposureTimer?.cancel();
    _exposureTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showExposureSlider = false);
      }
    });
  }

  Future<void> _setZoom(double value, {bool withHaptic = true}) async {
    if (!_hasInitializedController ||
        _isCameraLocked ||
        !_hasGrantedCameraPermission) {
      return;
    }

    final prevZoom = _currentZoom;
    final target = value.clamp(_minZoom, _maxZoom);
    final crossedOneBoundary =
        (prevZoom < 1.0 && target >= 1.0) || (prevZoom >= 1.0 && target < 1.0);

    if (crossedOneBoundary) {
      debugPrint(
        '[CaptureZoomDiag] boundary_cross prev=${prevZoom.toStringAsFixed(3)} '
        'target=${target.toStringAsFixed(3)} '
        'min=${_minZoom.toStringAsFixed(3)} '
        'max=${_maxZoom.toStringAsFixed(3)} '
        'lens=${_controller?.description.lensDirection}',
      );
    }

    try {
      await _controller!.setZoomLevel(target);
      setState(() => _currentZoom = target);

      final currentZone = _zoomZone(target);
      final shouldLogStep =
          _lastZoomDiagValue == null ||
          (target - (_lastZoomDiagValue ?? target)).abs() >= 0.15 ||
          currentZone != _lastZoomDiagZone;
      if (shouldLogStep) {
        debugPrint(
          '[CaptureZoomDiag] set_zoom '
          'prev=${prevZoom.toStringAsFixed(3)} '
          'target=${target.toStringAsFixed(3)} '
          'zone=$currentZone '
          'showSlider=$_showExtendedZoomSlider',
        );
        _lastZoomDiagValue = target;
        _lastZoomDiagZone = currentZone;
      }

      if (withHaptic) {
        hapticFeedback();
      }
    } catch (e) {
      debugPrint('[Capture] Set zoom error: $e');
    }
  }

  void _onPreviewScaleStart(ScaleStartDetails details) {
    if (!_hasInitializedController ||
        _isCameraLocked ||
        !_hasGrantedCameraPermission) {
      return;
    }
    _pinchStartZoom = _currentZoom;
  }

  void _onPreviewScaleUpdate(ScaleUpdateDetails details) {
    if (!_hasInitializedController ||
        _isCameraLocked ||
        !_hasGrantedCameraPermission) {
      return;
    }
    if (details.pointerCount < 2) {
      return;
    }

    final targetZoom = (_pinchStartZoom * details.scale).clamp(
      _minZoom,
      _maxZoom,
    );

    final currentZone = _zoomZone(targetZoom);
    if (currentZone != _lastZoomDiagZone) {
      debugPrint(
        '[CaptureZoomDiag] pinch_zone_change '
        'pinchStart=${_pinchStartZoom.toStringAsFixed(3)} '
        'scale=${details.scale.toStringAsFixed(3)} '
        'target=${targetZoom.toStringAsFixed(3)} '
        'zone=$currentZone',
      );
    }

    _setZoom(targetZoom, withHaptic: false);
  }

  void _onPreviewScaleEnd(ScaleEndDetails details) {
    if (!_hasInitializedController ||
        _isCameraLocked ||
        !_hasGrantedCameraPermission) {
      return;
    }
    _pinchStartZoom = _currentZoom;
  }

  Future<void> _onZoomPresetTap(double zoom) async {
    if (!_hasInitializedController || !_hasGrantedCameraPermission) return;

    setState(() {
      _showExtendedZoomSlider = (zoom - 3.0).abs() < 0.05;
    });

    await _setZoom(zoom);
  }

  double _highlightZoomPreset(double zoom) {
    if (zoom < 1.0) return 0.5;
    if (zoom < 3.0) return 1.0;
    return 3.0;
  }

  double _dynamicZoomLabelTargetPreset(double zoom) {
    if (zoom < 1.0) return 0.5;
    if (zoom < 3.0) return 1.0;
    return 3.0;
  }

  String _zoomZone(double zoom) {
    if (zoom < 1.0) return 'lt1';
    if (zoom < 3.0) return '1to3';
    return 'gte3';
  }

  String _formatZoomLabel(double value) {
    final oneDecimal = value.toStringAsFixed(1);
    if (oneDecimal.endsWith('.0')) {
      return oneDecimal.substring(0, oneDecimal.length - 2);
    }
    if (value < 1.0) {
      return oneDecimal.replaceFirst('0', '');
    }
    return oneDecimal;
  }

  String _zoomButtonLabel(double preset) {
    final targetPreset = _dynamicZoomLabelTargetPreset(_currentZoom);
    final value = (targetPreset - preset).abs() < 0.001 ? _currentZoom : preset;
    return _formatZoomLabel(value);
  }

  Future<void> _openCaptureSettings() async {
    if (!_hasInitializedController) return;

    final options = <_CaptureQualityMode>[
      _CaptureQualityMode.auto,
      _CaptureQualityMode.p1080,
      _CaptureQualityMode.p4k,
    ];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: true,
      builder: (context) {
        _CaptureQualityMode selectedMode = _selectedQualityMode;
        _PreviewAspectPreset selectedAspect = _selectedAspectPreset;
        var applyingPreset = false;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: const Color(0xFF111317),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Settings',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        if (applyingPreset)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.amber,
                            ),
                          ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white70,
                            size: 17,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Aspect',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const spacing = 8.0;
                        final itemWidth =
                            (constraints.maxWidth - spacing * 2) / 3;
                        return Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: _PreviewAspectPreset.values.map((aspect) {
                            final selected = selectedAspect == aspect;
                            return SizedBox(
                              width: itemWidth,
                              child: ChoiceChip(
                                label: Text(aspect.label),
                                selected: selected,
                                labelStyle: TextStyle(
                                  color: selected
                                      ? Colors.black
                                      : Colors.black87,
                                  fontWeight: FontWeight.w700,
                                ),
                                selectedColor: Colors.amber,
                                backgroundColor: const Color(0xFFF1F1F1),
                                onSelected: (_) {
                                  if (selectedAspect == aspect) return;
                                  setModalState(() => selectedAspect = aspect);
                                  setState(
                                    () => _selectedAspectPreset = aspect,
                                  );
                                  hapticFeedback();
                                },
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Quality',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const spacing = 8.0;
                        final itemWidth =
                            (constraints.maxWidth - spacing * 2) / 3;
                        return Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: options.map((preset) {
                            final selected = selectedMode == preset;
                            final enabled =
                                preset != _CaptureQualityMode.p4k ||
                                _supports4kCapture;
                            return SizedBox(
                              width: itemWidth,
                              child: ChoiceChip(
                                label: Text(preset.label),
                                selected: selected,
                                labelStyle: TextStyle(
                                  color: !enabled
                                      ? Colors.black45
                                      : selected
                                      ? Colors.black
                                      : Colors.black87,
                                  fontWeight: FontWeight.w700,
                                ),
                                selectedColor: Colors.amber,
                                backgroundColor: const Color(0xFFF1F1F1),
                                onSelected: enabled
                                    ? (_) async {
                                  if (applyingPreset ||
                                      selectedMode == preset) {
                                    return;
                                  }
                                  setModalState(() {
                                    selectedMode = preset;
                                    applyingPreset = true;
                                  });
                                  await _applyCaptureQualityMode(preset);
                                  if (!mounted) return;
                                  setModalState(() {
                                    selectedMode = _selectedQualityMode;
                                    applyingPreset = false;
                                  });
                                  hapticFeedback();
                                }
                                    : null,
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _applyCaptureQualityMode(_CaptureQualityMode mode) async {
    if (!_hasGrantedCameraPermission) {
      setState(() {
        _flowError = '권한 허용 전에는 카메라 설정을 변경할 수 없습니다.';
      });
      return;
    }

    if (mode == _selectedQualityMode || _isInitializingCamera) return;
    if (mode == _CaptureQualityMode.p4k && !_supports4kCapture) {
      setState(() {
        _flowError = '이 기기에서는 4K 촬영을 지원하지 않습니다. 1080p로 촬영됩니다.';
      });
      return;
    }
    final previousMode = _selectedQualityMode;
    setState(() {
      _selectedQualityMode = mode;
      _flowError = null;
    });
    await _initCameraAsync();
    if (!_hasInitializedController && mounted) {
      setState(() => _selectedQualityMode = previousMode);
      await _initCameraAsync();
    }
  }

  @override
  void dispose() {
    _cancelRecordingTimer();
    _exposureTimer?.cancel();
    _focusAnimController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canRequestPermission =
        !_hasGrantedCameraPermission && !_isPermissionBlockedPermanently;
    final canTriggerCapture =
        _hasGrantedCameraPermission &&
        _hasInitializedController &&
        !_isCheckingCameraPermission &&
        !_isInitializingCamera &&
        !_isCameraLocked &&
        (_canStopRecording || _canStartRecording);

    if (!_hasInitializedController) {
    return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: _cameraError != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        _cameraError!,
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed:
                          _hasGrantedCameraPermission && !_isInitializingCamera
                          ? _initCamera
                          : null,
                      child: const Text('Retry'),
                    ),
                    const SizedBox(height: 6),
                    ElevatedButton(
                      onPressed:
                          canRequestPermission &&
                              !_isCheckingCameraPermission &&
                              !_isInitializingCamera
                          ? _requestCameraPermissionFromUi
                          : null,
                      child: const Text('권한 다시 요청'),
                    ),
                    const SizedBox(height: 6),
                    ElevatedButton(
                      onPressed:
                          !_hasGrantedCameraPermission &&
                              !_isCheckingCameraPermission
                          ? _openCameraSystemSettings
                          : null,
                      child: const Text('앱 설정 열기'),
                    ),
                    if (_isInitializingCamera) ...[
                      const SizedBox(height: 12),
                      const CircularProgressIndicator(color: Colors.white),
                    ],
                  ],
                )
              : const CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (!_didReportPreviewReady) {
      _didReportPreviewReady = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        logFirstCameraPreviewStage('before_preview_widget_show');
        logFirstCameraPreviewReady();
      });
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              LayoutBuilder(
                builder: (context, _) {
                  final cameraPortraitAspect =
                      _lockedPreviewAspect ??
                      _toPortraitAspect(_controller!.value.aspectRatio);
                  final targetAspect = _selectedAspectPreset.aspectRatio;
                  const baseHeight = 1000.0;
                  final baseWidth = baseHeight * cameraPortraitAspect;

                  return Center(
                    child: AspectRatio(
                      aspectRatio: targetAspect,
                      child: LayoutBuilder(
                        builder: (context, previewConstraints) {
                          return Stack(
                            children: [
                              ClipRect(
                                child: FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: baseWidth,
                                    height: baseHeight,
                                    child: CameraPreview(_controller!),
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapDown: (d) =>
                                      _handleFocus(d, previewConstraints),
                                  onScaleStart: _onPreviewScaleStart,
                                  onScaleUpdate: _onPreviewScaleUpdate,
                                  onScaleEnd: _onPreviewScaleEnd,
                                ),
                              ),
                              if (_tapPosition != null &&
                                  _showExposureSlider) ...[
                                Positioned(
                                  left: _tapPosition!.dx - 35,
                                  top: _tapPosition!.dy - 35,
                                  child: AnimatedBuilder(
                                    animation: _focusAnimController,
                                    builder: (context, child) => Container(
                                      width: 70,
                                      height: 70,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.yellow,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: _tapPosition!.dx + 45,
                                  top: _tapPosition!.dy - 60,
                                  child: SizedBox(
                                    height: 120,
                                    child: RotatedBox(
                                      quarterTurns: 3,
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 2,
                                          thumbShape:
                                              const RoundSliderThumbShape(
                                                enabledThumbRadius: 6,
                                              ),
                                          overlayShape:
                                              const RoundSliderOverlayShape(
                                                overlayRadius: 14,
                                              ),
                                          activeTrackColor: Colors.yellow,
                                          inactiveTrackColor: Colors.white30,
                                          thumbColor: Colors.yellow,
                                        ),
                                        child: Slider(
                                          value: _exposureOffset,
                                          min: _minExposure,
                                          max: _maxExposure,
                                          onChanged: (v) async {
                                            setState(() => _exposureOffset = v);
                                            await _controller!
                                                .setExposureOffset(v);
                                            _startExposureTimer();
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                  );
                },
              ),

              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _buildAlbumDropdown(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _buildGlassIconButton(
                            icon: _flashMode == FlashMode.torch
                                ? Icons.flash_on
                                : Icons.flash_off,
                            iconColor: _flashMode == FlashMode.torch
                                ? Colors.amber
                                : Colors.white,
                            onPressed: _toggleFlash,
                          ),
                          const SizedBox(width: 10),
                          _buildGlassIconButton(
                            icon: Icons.settings,
                            onPressed: _openCaptureSettings,
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (!_isBusyRecordingFlow)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withAlpha(120),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildZoomButton(
                                    0.5,
                                    isSelected:
                                        (_highlightZoomPreset(_currentZoom) -
                                                0.5)
                                            .abs() <
                                        0.001,
                                  ),
                                  const SizedBox(width: 4),
                                  _buildZoomButton(
                                    1.0,
                                    isSelected:
                                        (_highlightZoomPreset(_currentZoom) -
                                                1.0)
                                            .abs() <
                                        0.001,
                                  ),
                                  const SizedBox(width: 4),
                                  _buildZoomButton(
                                    3.0,
                                    isSelected:
                                        (_highlightZoomPreset(_currentZoom) -
                                                3.0)
                                            .abs() <
                                        0.001,
                                  ),
                                ],
                              ),
                            ),
                            if (_showExtendedZoomSlider) ...[
                              const SizedBox(width: 8),
                              _buildExtendedZoomSlider(),
                            ],
                          ],
                        ),
                      ),
                    if (_isBusyRecordingFlow)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withAlpha(204),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: _flowState == _CaptureFlowState.preparing
                              ? const Text(
                                  'REC 준비중',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Courier',
                                  ),
                                )
                              : _hasRecordingActuallyStarted
                              ? Text(
                                  "00:0$_remainingTime",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Courier',
                                  ),
                                )
                              : const Text(
                                  'REC',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Courier',
                                  ),
                                ),
                        ),
                      ),
                    if (_flowError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _flowError!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 30),
                      child: SizedBox(
                        width: double.infinity,
                        height: 100,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            GestureDetector(
                              onTap: canTriggerCapture
                                  ? () {
                                      hapticFeedback();
                                      if (_canStopRecording) {
                                        _stopRecording();
                                      } else {
                                        _startRecording();
                                      }
                                    }
                                  : null,
                              child: Opacity(
                                opacity: canTriggerCapture ? 1 : 0.45,
                                child: ShutterRing(
                                  isRecording: _isBusyRecordingFlow,
                                  key: widget.recordButtonKey,
                                ),
                              ),
                            ),
                            Positioned(
                              right: 32,
                              child: _buildGlassIconButton(
                                icon: Icons.flip_camera_ios_rounded,
                                size: 43,
                                iconSize: 21,
                                onPressed: _toggleCamera,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildZoomButton(double zoom, {bool isSelected = false}) {
    return GestureDetector(
      onTap: !_hasInitializedController ? null : () => _onZoomPresetTap(zoom),
      child: Container(
        width: 38,
        height: 28,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Text(
          _zoomButtonLabel(zoom),
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white70,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildExtendedZoomSlider() {
    final sliderMin = 3.0;
    final sliderMax = _maxZoom < sliderMin ? sliderMin : _maxZoom;
    final sliderValue = _currentZoom.clamp(sliderMin, sliderMax);

    return Container(
      width: 124,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(120),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          const Icon(Icons.zoom_in, color: Colors.white70, size: 13),
          const SizedBox(width: 4),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white30,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: sliderValue,
                min: sliderMin,
                max: sliderMax,
                onChanged: sliderMax <= sliderMin
                    ? null
                    : (v) {
                        _setZoom(v, withHaptic: false);
                      },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color iconColor = Colors.white,
    double size = 31,
    double iconSize = 15,
  }) {
    return Material(
      color: Colors.black.withAlpha(70),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: iconColor, size: iconSize),
        ),
      ),
    );
  }

  Widget _buildAlbumDropdown() {
    final currentAlbum =
        videoManager.clipAlbums.contains(videoManager.currentAlbum)
        ? videoManager.currentAlbum
        : (videoManager.clipAlbums.isNotEmpty
              ? videoManager.clipAlbums.first
              : 'Albums');

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(90),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wb_sunny_outlined, color: Colors.white70, size: 14),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: currentAlbum,
              dropdownColor: Colors.black.withAlpha(204),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              icon: const Icon(
                Icons.keyboard_arrow_down,
                color: Colors.white70,
                size: 13,
              ),
              onChanged: (v) {
                if (v == null) return;
                setState(() => videoManager.currentAlbum = v);
                hapticFeedback();
              },
              items: videoManager.clipAlbums
                  .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// New Shutter Ring Widget
class ShutterRing extends StatefulWidget {
  final bool isRecording;

  const ShutterRing({super.key, required this.isRecording});

  @override
  State<ShutterRing> createState() => _ShutterRingState();
}

class _ShutterRingState extends State<ShutterRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 0.68,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(covariant ShutterRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording != oldWidget.isRecording) {
      if (widget.isRecording) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withAlpha(220),
                  width: 6,
                ),
              ),
            ),
            Container(
              width: 72 * _scaleAnim.value,
              height: 72 * _scaleAnim.value,
              decoration: BoxDecoration(
                color: const Color(0xFFF24242),
                borderRadius: BorderRadius.circular(
                  widget.isRecording ? 10 : 36,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
