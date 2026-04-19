import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 💡 MethodChannel 사용을 위한 핵심 임포트
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:path/path.dart' as p;
import 'package:gal/gal.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;

import 'managers/user_status_manager.dart';
import 'services/iap_service.dart';
import 'services/auth_service.dart';
import 'services/cloud_service.dart';
import 'services/notification_settings_service.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/capture_screen.dart';
import 'screens/library_screen.dart';
import 'managers/video_manager.dart';
import 'models/import_state.dart';
import 'models/vlog_project.dart';
import 'screens/video_edit_screen.dart';
import 'screens/clip_extractor_screen.dart'; // ✅ 추가
import 'widgets/video_widgets.dart';
import 'utils/haptics.dart';
import 'utils/quality_policy.dart';

late List<CameraDescription> cameras;
final Stopwatch appLaunchStopwatch = Stopwatch();
bool _didLogFirstCameraPreviewReady = false;

const String kKakaoNativeAppKey = String.fromEnvironment(
  'KAKAO_NATIVE_APP_KEY',
  defaultValue: '',
);

const String kSocialAuthExchangeUrl = String.fromEnvironment(
  'SOCIAL_AUTH_EXCHANGE_URL',
  defaultValue: '',
);

enum ExternalMediaType { image, video }

class PendingImportItem {
  final String path;
  final ExternalMediaType mediaType;
  final int orderIndex;

  const PendingImportItem({
    required this.path,
    required this.mediaType,
    required this.orderIndex,
  });
}

class ImportQueueBuckets {
  final List<PendingImportItem> leadQueue;
  final List<PendingImportItem> backgroundQueue;

  const ImportQueueBuckets({
    required this.leadQueue,
    required this.backgroundQueue,
  });
}

enum ExportUiState { none, preparing, rendering, saving, done, error }

void logFirstCameraPreviewReady() {
  if (_didLogFirstCameraPreviewReady) return;
  _didLogFirstCameraPreviewReady = true;
  if (!appLaunchStopwatch.isRunning) return;
  appLaunchStopwatch.stop();
  debugPrint(
    '[Startup][TTFF] app_launch_to_camera_preview_ms=${appLaunchStopwatch.elapsedMilliseconds}',
  );
}

void logFirstCameraPreviewStage(String stage, {String? detail}) {
  if (!appLaunchStopwatch.isRunning) return;
  final suffix = (detail == null || detail.isEmpty) ? '' : ' $detail';
  debugPrint(
    '[Startup][TTFF][Stage] stage=$stage elapsed_ms=${appLaunchStopwatch.elapsedMilliseconds}$suffix',
  );
}

Future<void> _warmUpStartupServices() async {
  try {
    final userStatusManager = UserStatusManager();
    await userStatusManager.initialize();

    final downgraded = await userStatusManager
        .evaluateAndAutoDowngradeIfExpired(reason: 'startup_warmup');
    if (downgraded) {
      await AuthService().syncFreeTierToFirestore(
        reason: 'startup_warmup_auto_downgrade',
      );
    }
  } catch (e) {
    debugPrint('[Startup] UserStatusManager initialize failed: $e');
  }

  try {
    await IAPService().initialize();
  } catch (e) {
    debugPrint('[Startup] IAPService initialize failed: $e');
  }
}

Future<List<CameraDescription>> _loadAvailableCameras() async {
  try {
    return await availableCameras();
  } catch (e) {
    debugPrint('카메라를 찾을 수 없습니다: $e');
    return [];
  }
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[FCM] background message: ${message.messageId}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Kakao SDK 초기화 (키 누락 시 명시 로그)
  if (kKakaoNativeAppKey.isEmpty) {
    debugPrint(
      '[Main][Kakao] KAKAO_NATIVE_APP_KEY가 비어 있어 KakaoSdk.init을 건너뜁니다. '
      '실행 시 --dart-define=KAKAO_NATIVE_APP_KEY=... 값을 전달하세요.',
    );
  } else {
    kakao.KakaoSdk.init(nativeAppKey: kKakaoNativeAppKey);
    debugPrint(
      '[Main][Kakao] KakaoSdk.init 완료 (keyLength=${kKakaoNativeAppKey.length})',
    );
  }

  if (kSocialAuthExchangeUrl.isEmpty) {
    debugPrint(
      '[Main][AuthExchange] SOCIAL_AUTH_EXCHANGE_URL가 비어 있습니다. '
      '실행 시 --dart-define=SOCIAL_AUTH_EXCHANGE_URL=... 값을 전달하세요.',
    );
  } else {
    debugPrint(
      '[Main][AuthExchange] SOCIAL_AUTH_EXCHANGE_URL 확인 (length=${kSocialAuthExchangeUrl.length})',
    );
  }

  if (!appLaunchStopwatch.isRunning) {
    appLaunchStopwatch.start();
  }

  // 전역 Flutter/Platform 예외 로깅 (런타임 진단 강화)
  FlutterError.onError = (FlutterErrorDetails details) {
    final exception = details.exceptionAsString();
    final stack = details.stack?.toString() ?? 'no-stack';
    debugPrint('[GlobalFlutterError] $exception');
    if (exception.contains('ParentDataWidget')) {
      debugPrint('[GlobalFlutterError][ParentDataWidget] $exception');
    }
    debugPrint('[GlobalFlutterError][Stack]\n$stack');
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[GlobalPlatformError] $error');
    debugPrint('[GlobalPlatformError][Stack]\n$stack');
    return true;
  };

  final cameraFuture = _loadAvailableCameras();

  // Android 런타임/설정 정합성 로그 (google-services.json의 package_name와 대응 확인용)
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    debugPrint(
      '[Main] App runtime package info => name: ${packageInfo.appName}, '
      'package: ${packageInfo.packageName}, version: ${packageInfo.version}+${packageInfo.buildNumber}',
    );
  } catch (e, st) {
    debugPrint('[Main] PackageInfo 조회 실패: $e');
    debugPrint('[Main] PackageInfo Stack\n$st');
  }

  // Firebase 초기화
  try {
    await Firebase.initializeApp();
    print('[Main] Firebase 초기화 완료');
  } catch (e, st) {
    print('[Main] Firebase 초기화 실패: $e');
    print('[Main] Firebase init stack:\n$st');
  }
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Android 15+ edge-to-edge 기본 정책에 맞춰 시스템 UI 모드를 명시적으로 정렬
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  cameras = await cameraFuture;
  runApp(const MyApp());
  unawaited(_warmUpStartupServices());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VideoManager()),
        Provider(create: (_) => UserStatusManager()),
        Provider(create: (_) => IAPService()),
      ],
      child: MaterialApp(
        title: 'One Second Vlog 2.6.0 Native',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.light,
          scaffoldBackgroundColor: Colors.white,
          colorScheme: const ColorScheme.light(
            primary: Colors.black,
            secondary: Colors.blueAccent,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0,
            iconTheme: IconThemeData(color: Colors.black),
            titleTextStyle: TextStyle(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        home: const AuthGate(),
      ),
    );
  }
}

/// 인증 게이트
///
/// Firebase Auth 상태를 감지하여 로그인 여부에 따라 화면 분기:
/// - 로그인 안 됨: LoginScreen
/// - 로그인 완료: MainNavigationScreen
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[AuthGate] build start: firebaseApps=${Firebase.apps.length}');
    final authService = AuthService();

    return ValueListenableBuilder<bool>(
      valueListenable: authService.sessionBootstrapInProgress,
      builder: (context, isBootstrapping, _) =>
          ValueListenableBuilder<AuthMode>(
            valueListenable: authService.authMode,
            builder: (context, authMode, _) => StreamBuilder(
              initialData: authService.currentUser,
              stream: authService.authStateChanges,
              builder: (context, snapshot) {
                final isSignedIn = snapshot.hasData && snapshot.data != null;
                final isGuest = authMode == AuthMode.guest;

                // 로그인 상태 또는 게스트 모드면 메인 화면 진입
                if (isSignedIn || isGuest) {
                  // 로그인 직후 구독 동기화가 끝날 때까지 게이트에서 대기
                  if (isSignedIn && isBootstrapping) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }

                  // 인증됨/게스트면 메인 화면
                  return const MainNavigationScreen();
                }

                // 로그인 안 됨 + 게스트 아님 → 로그인 화면
                return const LoginScreen();
              },
            ),
          ),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});
  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // 💡 [핵심] 네이티브 엔진과 통신하는 직통 채널 개설
  static const platform = MethodChannel('com.dk.three_sec/video_engine');

  int _selectedIndex = 0;
  StreamSubscription<RemoteMessage>? _onMessageSubscription;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSubscription;
  final List<Map<String, dynamic>> _pendingNotificationRouteQueue =
      <Map<String, dynamic>>[];
  bool _isFlushingNotificationRouteQueue = false;
  VoidCallback? _sessionBootstrapListener;

  // 튜토리얼용 GlobalKey
  final GlobalKey keyRecordButton = GlobalKey();
  final GlobalKey keyLibraryTab = GlobalKey();
  final GlobalKey keyAlbumGridItem = GlobalKey();
  final GlobalKey keyFirstClip = GlobalKey();
  final GlobalKey keyActionsArea = GlobalKey();
  final GlobalKey keyPickMedia = GlobalKey();
  final GlobalKey keyCreateProject = GlobalKey();

  bool _isConverting = false;
  bool _isPreparingProject = false;
  ExportUiState _exportUiState = ExportUiState.none;
  String _exportUiStatusMessage = '';
  int _projectPreparingCurrent = 0;
  int _projectPreparingTotal = 0;
  Timer? _renderingProgressTimer;
  DateTime? _renderingProgressStartedAt;
  double _renderingVisualProgress = 0.0;
  int _lastRenderingProgressLogBucket = -1;
  int _importProgressCurrent = 0;
  int _importProgressTotal = 0;
  static const int _importLeadQueueCount = 3;
  static const Duration _importPreviewTimeout = Duration(seconds: 10);
  bool _didBindVideoManager = false;
  bool _didRequestTutorialCheck = false;
  bool _isTutorialFlowActive = false;
  bool _isWaitingForAlbumDetailTutorial = false;
  bool _didShowSelectClipTutorial = false;
  bool _isWaitingForCreateButtonTutorial = false;
  bool _didShowCreateButtonTutorial = false;
  bool _isTutorialCreateActionArmed = false;
  bool _didShowExternalImportTutorial = false;
  int _phase4RetryCount = 0;
  int _completionRetryCount = 0;
  late VideoManager videoManager;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initFirebaseMessaging();
    _sessionBootstrapListener = () {
      if (!mounted) return;
      _flushQueuedNotificationRoutes(reason: 'session_bootstrap_state_change');
    };
    AuthService().sessionBootstrapInProgress.addListener(
      _sessionBootstrapListener!,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didRequestTutorialCheck) return;
      _didRequestTutorialCheck = true;
      unawaited(_checkAndStartTutorial());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint(
      '[Main][Lifecycle] state=$state '
      'isPreparingProject=$_isPreparingProject '
      'isConverting=$_isConverting '
      'selectedIndex=$_selectedIndex '
      'tutorialActive=$_isTutorialFlowActive',
    );

    if (state == AppLifecycleState.resumed) {
      unawaited(_restoreCloudUploadQueueOnResume());
      unawaited(_flushQueuedNotificationRoutes(reason: 'app_resumed'));
    }
  }

  Future<void> _restoreCloudUploadQueueOnResume() async {
    try {
      await CloudService().restoreUploadQueueFromStore();
    } catch (e) {
      debugPrint('[Main][Lifecycle] Cloud upload queue restore failed: $e');
    }
  }

  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();

    if (_didBindVideoManager) {
      videoManager.recordMemoryPressureEvent();
    } else {
      VideoManager().recordMemoryPressureEvent();
    }

    debugPrint(
      '[Main][Diag][MemoryPressure] didHaveMemoryPressure event at '
      '${DateTime.now().toIso8601String()} '
      'sessionId=${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didBindVideoManager) return;
    videoManager = Provider.of<VideoManager>(context, listen: false);
    _didBindVideoManager = true;
    _refreshData();
    unawaited(_flushQueuedNotificationRoutes(reason: 'video_manager_bound'));
  }

  Future<void> _initFirebaseMessaging() async {
    if (kIsWeb) return;
    final notificationSettingsService = NotificationSettingsService.instance;

    _onMessageSubscription = FirebaseMessaging.onMessage.listen((message) {
      final title = message.notification?.title;
      if (title != null) {
        Fluttertoast.showToast(
          msg: title,
          backgroundColor: Colors.black87,
          textColor: Colors.white,
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
        );
      }
    });

    _onMessageOpenedAppSubscription = FirebaseMessaging.onMessageOpenedApp.listen((
      message,
    ) {
      final title = message.notification?.title ?? "알림을 열었습니다.";
      if (mounted) {
        Fluttertoast.showToast(
          msg: title,
          backgroundColor: Colors.black87,
          textColor: Colors.white,
        );
      }
      unawaited(
        _handleNotificationOpen(
          message,
          source: 'onMessageOpenedApp',
        ),
      );
    });

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      unawaited(
        _handleNotificationOpen(
          initialMessage,
          source: 'getInitialMessage',
        ),
      );
    }

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
    await notificationSettingsService.migrateCategorySettingsIfNeeded();
    await notificationSettingsService.ensureStartupSync();

    final shouldShowPrompt = await notificationSettingsService
        .shouldShowInitialPermissionPrompt();
    if (!shouldShowPrompt) return;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _requestNotificationPermissionDirectly(),
    );
  }

  bool _canHandleNotificationRouteNow() {
    if (!mounted) {
      return false;
    }
    final authService = AuthService();
    final isBootstrapping = authService.sessionBootstrapInProgress.value;
    final hasAuthSession = authService.isSignedIn || authService.isGuest;
    if (isBootstrapping || !hasAuthSession) {
      return false;
    }

    if (!_didBindVideoManager) {
      return false;
    }

    if (_isConverting || _isPreparingProject) {
      return false;
    }

    return true;
  }

  void _enqueueNotificationRoute(
    Map<String, dynamic> payload, {
    required String source,
    required String reason,
  }) {
    // [AndroidRelease][Checklist-2]
    // 동기화/초기화 미완료 상태 알림 라우팅은 즉시 실행하지 않고 큐잉하여 크래시를 방지한다.
    const maxQueueSize = 5;
    if (_pendingNotificationRouteQueue.length >= maxQueueSize) {
      _pendingNotificationRouteQueue.removeAt(0);
    }
    _pendingNotificationRouteQueue.add(Map<String, dynamic>.from(payload));
    debugPrint(
      '[Main][NotificationRoute] queued '
      'source=$source reason=$reason '
      'queueSize=${_pendingNotificationRouteQueue.length} payload=$payload',
    );
  }

  Future<void> _flushQueuedNotificationRoutes({required String reason}) async {
    if (_isFlushingNotificationRouteQueue) {
      return;
    }
    _isFlushingNotificationRouteQueue = true;
    try {
      while (_pendingNotificationRouteQueue.isNotEmpty) {
        if (!_canHandleNotificationRouteNow()) {
          debugPrint(
            '[Main][NotificationRoute] flush deferred '
            'reason=$reason queueSize=${_pendingNotificationRouteQueue.length}',
          );
          break;
        }
        final payload = _pendingNotificationRouteQueue.removeAt(0);
        await _applyNotificationRoute(
          payload,
          source: 'queue_flush:$reason',
        );
      }
    } catch (e, st) {
      debugPrint('[Main][NotificationRoute] flush exception: $e');
      debugPrint('[Main][NotificationRoute][Stack]\n$st');
    } finally {
      _isFlushingNotificationRouteQueue = false;
    }
  }

  Future<void> _handleNotificationOpen(
    RemoteMessage message, {
    required String source,
  }) async {
    final payload = Map<String, dynamic>.from(message.data);
    if (payload.isEmpty) {
      debugPrint('[Main][NotificationRoute] no payload. ignore source=$source');
      return;
    }

    if (!_canHandleNotificationRouteNow()) {
      _enqueueNotificationRoute(
        payload,
        source: source,
        reason: 'state_not_ready',
      );
      return;
    }

    await _applyNotificationRoute(payload, source: source);
  }

  Future<void> _applyNotificationRoute(
    Map<String, dynamic> payload, {
    required String source,
  }) async {
    try {
      // [AndroidRelease][Checklist-3]
      // payload 파싱 실패/잘못된 탭 값/인증 미완료 상태는 모두 안전 무시하고
      // 절대 throw하지 않도록 방어하여 알림 탭 진입 경로 크래시를 차단한다.
      final authService = AuthService();
      if (!(authService.isSignedIn || authService.isGuest)) {
        debugPrint(
          '[Main][NotificationRoute] ignored (no auth session) '
          'source=$source payload=$payload',
        );
        return;
      }

      final index = NotificationSettingsService.instance
          .resolveMainTabIndexFromPayload(payload);
      if (index == null || index < 0 || index > 2) {
        debugPrint(
          '[Main][NotificationRoute] ignored (invalid target tab) '
          'source=$source payload=$payload',
        );
        return;
      }

      if (!mounted) return;
      if (_selectedIndex != index) {
        setState(() {
          _selectedIndex = index;
          if (index == 0 && _didBindVideoManager && videoManager.currentAlbum == '휴지통') {
            videoManager.currentAlbum = '일상';
          }
        });
      }

      if (index == 1) {
        // 라이브러리 라우팅 시 비동기 초기화 레이스를 줄이기 위해 안전 리프레시.
        unawaited(_refreshData());
      }

      debugPrint(
        '[Main][NotificationRoute] applied '
        'source=$source targetIndex=$index payload=$payload',
      );
    } catch (e, st) {
      debugPrint('[Main][NotificationRoute] apply failed: $e');
      debugPrint('[Main][NotificationRoute][Stack]\n$st');
    }
  }

  Future<void> _requestNotificationPermissionDirectly() async {
    if (!mounted) return;

    final notificationSettingsService = NotificationSettingsService.instance;
    await notificationSettingsService.markInitialPermissionPrompted();

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    final success =
        settings.authorizationStatus == AuthorizationStatus.authorized;
    await notificationSettingsService.syncTopicSubscriptions(
      authorizationStatus: settings.authorizationStatus,
    );
    Fluttertoast.showToast(
      msg: success ? '알림을 활성화했습니다.' : '알림 권한이 허용되지 않았습니다.',
      backgroundColor: Colors.black87,
      textColor: Colors.white,
    );
  }

  Future<void> _checkAndStartTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = AuthService().uid ?? 'anonymous';
    final perUserKey = 'tutorial_completed_user_$uid';

    final bool completedPerUser = prefs.getBool(perUserKey) ?? false;
    final bool legacyCompleted = (prefs.getBool('isFirstRun') ?? true) == false;

    // 과거 단일 플래그(isFirstRun=false) 사용자 마이그레이션
    if (!completedPerUser && legacyCompleted) {
      await prefs.setBool(perUserKey, true);
      return;
    }

    if (!completedPerUser && mounted) {
      final ensured = await videoManager.ensureTutorialSampleClips(
        targetAlbum: '일상',
      );
      videoManager.currentAlbum = '일상';
      await videoManager.loadClipsFromCurrentAlbum();

      debugPrint(
        '[Main][Tutorial] sample_clips_ready count=${ensured.length} '
        'currentAlbum=${videoManager.currentAlbum}',
      );

      setState(() {
        _selectedIndex = 1;
        _isTutorialFlowActive = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showTutorialPhase1();
        }
      });
    }
  }

  // --- [튜토리얼 로직] ---

  void _showTutorialPhase1() {
    TutorialCoachMark(
      targets: [
        TargetFocus(
          identify: "step1_sample_ready",
          keyTarget: keyAlbumGridItem,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              builder: (context, controller) => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "튜토리얼을 시작합니다.",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    "일상 앨범에 들어가보세요.\n"
                    "영상을 만들 샘플 클립 2개를 넣어놓았습니다.",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          ],
          shape: ShapeLightFocus.RRect,
          radius: 20,
        ),
      ],
      colorShadow: Colors.black,
      opacityShadow: 0.8,
      onFinish: () {
        _isWaitingForAlbumDetailTutorial = true;
      },
      onSkip: () {
        _finishTutorial();
        return true;
      },
    ).show(context: context);
  }

  void _showTutorialPhase2() {
    print('[Tutorial][Diag] _showTutorialPhase2 start');
    if (_didShowSelectClipTutorial || !_isTutorialFlowActive) return;
    _didShowSelectClipTutorial = true;
    TutorialCoachMark(
      targets: [
        TargetFocus(
          identify: "step2_select_clips",
          keyTarget: keyFirstClip,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              builder: (context, controller) => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "클립 2개 이상 선택",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    "클립을 길게 눌러 2개 이상 선택하세요.",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          ],
          shape: ShapeLightFocus.RRect,
          radius: 20,
        ),
      ],
      colorShadow: Colors.black,
      opacityShadow: 0.8,
      onFinish: () {
        _isWaitingForCreateButtonTutorial = true;
      },
      onSkip: () {
        _finishTutorial();
        return true;
      },
    ).show(context: context);
  }

  void _showTutorialPhase3() {
    if (_didShowCreateButtonTutorial || !_isTutorialFlowActive) return;
    _didShowCreateButtonTutorial = true;
    _isTutorialCreateActionArmed = false;
    debugPrint(
      '[Tutorial][Diag] Phase3 show start '
      'isTutorialFlowActive=$_isTutorialFlowActive '
      'isWaitingForCreateButtonTutorial=$_isWaitingForCreateButtonTutorial '
      'currentAlbum=${videoManager.currentAlbum} '
      'selectedIndex=$_selectedIndex '
      'keyCreateProject=$keyCreateProject',
    );
    TutorialCoachMark(
      targets: [
        TargetFocus(
          identify: "step3_create_video",
          keyTarget: keyCreateProject,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              builder: (context, controller) => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "영상 만들기",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    "클립을 2개 이상 선택 후 \n"
                    "하단 \"영상 만들기\" 버튼을 누르면\n"
                    "나만의 영상 앨범을 만들 수 있어요.",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
      colorShadow: Colors.black,
      opacityShadow: 0.8,
      onFinish: () {
        debugPrint(
          '[Tutorial][Diag] Phase3 onFinish -> arm real create button tap',
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_isTutorialFlowActive) return;
          _isTutorialCreateActionArmed = true;
        });
      },
      onSkip: () {
        debugPrint('[Tutorial][Diag] Phase3 skipped');
        _finishTutorial();
        return true;
      },
    ).show(context: context);
  }

  void _showTutorialPhase4() {
    if (_didShowExternalImportTutorial || !_isTutorialFlowActive) return;
    final hasPickMediaTarget = _isCoachMarkTargetReady(keyPickMedia);
    debugPrint(
      '[Tutorial][Diag] Phase4 show attempt '
      'isTutorialFlowActive=$_isTutorialFlowActive '
      '_didShowExternalImportTutorial=$_didShowExternalImportTutorial '
      'selectedIndex=$_selectedIndex '
      'phase4RetryCount=$_phase4RetryCount '
      'targetReady=$hasPickMediaTarget '
      'targetState=${_describeKeyState(keyPickMedia)}',
    );
    if (!hasPickMediaTarget) {
      _phase4RetryCount += 1;
      const maxPhase4RetryCount = 30;
      if (_phase4RetryCount >= maxPhase4RetryCount) {
        debugPrint(
          '[Tutorial][Diag] Phase4 target not ready timeout '
          '($_phase4RetryCount/$maxPhase4RetryCount) -> completeTutorialWithoutExport',
        );
        _didShowExternalImportTutorial = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(_completeTutorialWithoutExport());
        });
        return;
      }
      debugPrint(
        '[Tutorial][Diag] Phase4 target not ready '
        '($_phase4RetryCount/$maxPhase4RetryCount) -> retry delayed',
      );
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (!mounted || !_isTutorialFlowActive) return;
        _showTutorialPhase4();
      });
      return;
    }

    _phase4RetryCount = 0;
    _didShowExternalImportTutorial = true;
    debugPrint(
      '[Tutorial][Diag] Phase4 show start '
      'isTutorialFlowActive=$_isTutorialFlowActive '
      'selectedIndex=$_selectedIndex '
      'targetState=${_describeKeyState(keyPickMedia)}',
    );
    TutorialCoachMark(
      targets: [
        TargetFocus(
          identify: "step4_import_external_image",
          keyTarget: keyPickMedia,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              builder: (context, controller) => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "외부 사진/영상 가져오기",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    "우측 상단의 + 아이콘으로 외부 사진/영상을 불러와\n"
                    "클립으로 변환할 수 있어요.\n",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
      colorShadow: Colors.black,
      opacityShadow: 0.8,
      onFinish: () {
        debugPrint(
          '[Tutorial][Diag] Phase4 onFinish -> completeTutorialWithoutExport',
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(_completeTutorialWithoutExport());
        });
      },
      onSkip: () {
        debugPrint('[Tutorial][Diag] Phase4 skipped');
        debugPrint(
          '[Tutorial][Diag] Phase4 skip -> _finishTutorial '
          'targetState=${_describeKeyState(keyPickMedia)}',
        );
        _finishTutorial();
        return true;
      },
    ).show(context: context);
  }

  bool _isCoachMarkTargetReady(GlobalKey key) {
    final targetContext = key.currentContext;
    if (targetContext == null) return false;
    final renderObject = targetContext.findRenderObject();
    if (renderObject is! RenderBox) return false;
    if (!renderObject.attached || !renderObject.hasSize) return false;
    return renderObject.size.width > 0 && renderObject.size.height > 0;
  }

  String _describeKeyState(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return 'no-context';
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox) return 'no-renderbox';
    return 'attached=${ro.attached},hasSize=${ro.hasSize},size=${ro.size}';
  }

  Future<void> _finishTutorial() async {
    print('[Tutorial][Diag] _finishTutorial start');
    debugPrint(
      '[Tutorial][Diag] _finishTutorial state before clear '
      '_isTutorialFlowActive=$_isTutorialFlowActive '
      '_didShowExternalImportTutorial=$_didShowExternalImportTutorial '
      'phase4RetryCount=$_phase4RetryCount '
      'selectedIndex=$_selectedIndex '
      'recordButton=${_describeKeyState(keyRecordButton)} '
      'pickMedia=${_describeKeyState(keyPickMedia)}',
    );
    final prefs = await SharedPreferences.getInstance();
    final uid = AuthService().uid ?? 'anonymous';
    await prefs.setBool('tutorial_completed_user_$uid', true);
    await prefs.setBool('isFirstRun', false); // legacy 호환
    if (mounted) {
      setState(() {
        _isTutorialFlowActive = false;
        _isWaitingForAlbumDetailTutorial = false;
        _didShowSelectClipTutorial = false;
        _isWaitingForCreateButtonTutorial = false;
        _didShowCreateButtonTutorial = false;
        _isTutorialCreateActionArmed = false;
        _didShowExternalImportTutorial = false;
        _phase4RetryCount = 0;
        _completionRetryCount = 0;
      });
    } else {
      _isTutorialFlowActive = false;
      _isWaitingForAlbumDetailTutorial = false;
      _didShowSelectClipTutorial = false;
      _isWaitingForCreateButtonTutorial = false;
      _didShowCreateButtonTutorial = false;
      _isTutorialCreateActionArmed = false;
      _didShowExternalImportTutorial = false;
      _phase4RetryCount = 0;
      _completionRetryCount = 0;
    }
  }

  void _showTutorialCompletionCoachMark() {
    debugPrint(
      '[Tutorial][Diag] showTutorialCompletionCoachMark called '
      'recordButton=${_describeKeyState(keyRecordButton)}',
    );
    TutorialCoachMark(
      targets: [
        TargetFocus(
          identify: "tutorial_complete",
          keyTarget: keyRecordButton,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              builder: (context, controller) => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "튜토리얼 완료!",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    "원세컨 브이로그로 1초 영상앨범을 간직해보세요!",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          ],
          shape: ShapeLightFocus.Circle,
        ),
      ],
      colorShadow: Colors.black,
      opacityShadow: 0.8,
      onSkip: () {
        debugPrint('[Tutorial][Diag] tutorial completion coachmark skipped');
        unawaited(_finishTutorial());
        return true;
      },
      onFinish: () {
        debugPrint('[Tutorial][Diag] tutorial completion coachmark finished');
        unawaited(_finishTutorial());
      },
    ).show(context: context);
  }

  void _showTutorialCompletionCoachMarkWithRetry() {
    if (!mounted || !_isTutorialFlowActive) return;
    final hasRecordTarget = _isCoachMarkTargetReady(keyRecordButton);
    if (!hasRecordTarget) {
      _completionRetryCount += 1;
      const maxCompletionRetryCount = 30;
      if (_completionRetryCount >= maxCompletionRetryCount) {
        debugPrint(
          '[Tutorial][Diag] completion target not ready timeout '
          '($_completionRetryCount/$maxCompletionRetryCount) -> finishTutorial',
        );
        unawaited(_finishTutorial());
        return;
      }
      debugPrint(
        '[Tutorial][Diag] completion target not ready '
        '($_completionRetryCount/$maxCompletionRetryCount) -> retry delayed',
      );
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (!mounted || !_isTutorialFlowActive) return;
        _showTutorialCompletionCoachMarkWithRetry();
      });
      return;
    }

    _completionRetryCount = 0;
    _showTutorialCompletionCoachMark();
  }

  Future<void> _completeTutorialAfterExport() async {
    print('[Tutorial][Diag] completeTutorialAfterExport start');
    debugPrint(
      '[Tutorial][Diag] completeTutorialAfterExport beforeSwitch '
      '_isTutorialFlowActive=$_isTutorialFlowActive '
      'selectedIndex=$_selectedIndex '
      'currentAlbum=${videoManager.currentAlbum} '
      'pickMedia=${_describeKeyState(keyPickMedia)}',
    );
    if (!mounted || !_isTutorialFlowActive) return;
    _phase4RetryCount = 0;
    setState(() {
      _selectedIndex = 1;
      if (videoManager.currentAlbum == '휴지통') {
        videoManager.currentAlbum = '일상';
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isTutorialFlowActive) return;
      _showTutorialPhase4();
    });
  }

  Future<void> _completeTutorialWithoutExport() async {
    debugPrint(
      '[Tutorial][Diag] completeTutorialWithoutExport start '
      'isTutorialFlowActive=$_isTutorialFlowActive '
      'selectedIndex=$_selectedIndex '
      'currentAlbum=${videoManager.currentAlbum} '
      'pickMedia=${_describeKeyState(keyPickMedia)}',
    );
    if (!mounted || !_isTutorialFlowActive) return;
    setState(() {
      _selectedIndex = 0;
      if (videoManager.currentAlbum == '휴지통') {
        videoManager.currentAlbum = '일상';
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showTutorialCompletionCoachMarkWithRetry();
    });
  }

  void _onAlbumDetailVisibilityChanged(bool visible) {
    if (!_isTutorialFlowActive) return;
    if (!_isWaitingForAlbumDetailTutorial) return;
    if (!visible) return;
    _isWaitingForAlbumDetailTutorial = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showTutorialPhase2();
    });
  }

  void _onCreateProjectButtonVisibilityChanged(bool visible) {
    debugPrint(
      '[Tutorial][Diag] onCreateProjectButtonVisibilityChanged '
      'visible=$visible '
      'isTutorialFlowActive=$_isTutorialFlowActive '
      'isWaitingForCreateButtonTutorial=$_isWaitingForCreateButtonTutorial '
      'selectedTab=$_selectedIndex',
    );
    if (!_isTutorialFlowActive) return;
    if (!_isWaitingForCreateButtonTutorial) return;
    if (!visible) return;
    _isWaitingForCreateButtonTutorial = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showTutorialPhase3();
    });
  }

  // --- [데이터 관리] ---

  Future<void> _refreshData() async {
    await videoManager.initAlbumSystem();
    await videoManager.loadVlogProjects();
    await CloudService().initializeQueueStore();
    await CloudService().restoreUploadQueueFromStore();
    // 자동 전체 백업 트리거 축소:
    // refresh 시점 자동 enqueue 비활성화 (수동 이동/명시적 백업만 허용)
    if (mounted) setState(() {});
    CloudService().checkUsageAndAlert(videoManager);
  }

  Future<void> _loadClipsFromCurrentAlbum() async {
    if (!mounted) return;
    setState(() {
      videoManager.recordedVideoPaths.clear();
    });
    await videoManager.loadClipsFromCurrentAlbum();
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _renderingProgressTimer?.cancel();
    _renderingProgressTimer = null;
    _onMessageSubscription?.cancel();
    _onMessageSubscription = null;
    _onMessageOpenedAppSubscription?.cancel();
    _onMessageOpenedAppSubscription = null;
    if (_sessionBootstrapListener != null) {
      AuthService().sessionBootstrapInProgress.removeListener(
        _sessionBootstrapListener!,
      );
      _sessionBootstrapListener = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        // 뒤로가기 처리는 각 Screen 내부에서 관리됨
      },
      child: Scaffold(
        body: Stack(
          children: [
            IndexedStack(
              index: _selectedIndex,
              children: [
                _buildCaptureTab(),
                _buildLibraryTab(),
                _buildProfileTab(),
              ],
            ),
            if (_isConverting && _didBindVideoManager)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: ValueListenableBuilder<ImportState>(
                    valueListenable: videoManager.importQueueStateNotifier,
                    builder: (context, importState, _) {
                      final total = importState.total;
                      final settled =
                          importState.completed +
                          importState.failed +
                          importState.skipped +
                          importState.canceled;
                      final ratio = total > 0 ? settled / total : null;
                      return Container(
                        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.72),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              importState.progressText(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: ratio,
                              minHeight: 4,
                              backgroundColor: Colors.white24,
                              color: Colors.lightBlueAccent,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            if (_isConverting ||
                _isPreparingProject ||
                _exportUiState != ExportUiState.none)
              Container(
                color: Colors.black.withOpacity(0.5),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 30,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ValueListenableBuilder<ImportState>(
                          valueListenable:
                              videoManager.importQueueStateNotifier,
                          builder: (context, importState, _) {
                            final importLabel = importState.total > 0
                                ? importState.progressText()
                                : (_importProgressTotal > 0
                                      ? '가져오기 처리 중... ($_importProgressCurrent/$_importProgressTotal)'
                                      : '영상 변환 중...');
                            final statusText = _buildExportUiLabel(importLabel);
                            final progressValue = _computeExportOverlayProgress(
                              importState,
                            );
                            final auxText = _buildExportAuxProgressText(
                              importState.total,
                            );
                            final percentText = _buildExportPercentText(
                              progressValue,
                            );
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        statusText,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    if (percentText != null)
                                      Text(
                                        percentText,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                  ],
                                ),
                                if (auxText != null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 4,
                                      bottom: 8,
                                    ),
                                    child: Text(
                                      auxText,
                                      style: const TextStyle(
                                        color: Colors.black54,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 14),
                                LinearProgressIndicator(
                                  value: progressValue,
                                  minHeight: 4,
                                  backgroundColor: Colors.white24,
                                  color: Colors.lightBlueAccent,
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: _buildBenchmarkBottomNav(),
      ),
    );
  }

  String _buildExportUiLabel(String fallbackImportLabel) {
    final String phaseLabel = _exportUiStatusMessage.isNotEmpty
        ? _exportUiStatusMessage
        : switch (_exportUiState) {
            ExportUiState.preparing => '프로젝트 준비 중',
            ExportUiState.rendering => '내보내기 렌더링 중',
            ExportUiState.saving => '갤러리 저장 중',
            ExportUiState.done => '내보내기 완료',
            ExportUiState.error => '내보내기 실패',
            ExportUiState.none => _isPreparingProject ? '프로젝트 준비 중' : '영상 변환 중',
          };

    if (_exportUiState == ExportUiState.none &&
        !_isPreparingProject &&
        _importProgressTotal <= 0) {
      return fallbackImportLabel;
    }

    if (_projectPreparingTotal > 0 &&
        _exportUiState == ExportUiState.preparing &&
        (_isPreparingProject || _projectPreparingCurrent > 0)) {
      return '내보내기 준비중...';
    }

    return phaseLabel;
  }

  double? _computeExportOverlayProgress(ImportState importState) {
    if (_exportUiState == ExportUiState.done) return 1.0;
    if (_exportUiState == ExportUiState.error) return 0.0;

    switch (_exportUiState) {
      case ExportUiState.preparing:
        if (_projectPreparingTotal > 0) {
          return (_projectPreparingCurrent / _projectPreparingTotal).clamp(
            0.0,
            1.0,
          );
        }
        return 0.0;
      case ExportUiState.rendering:
        return _renderingVisualProgress.clamp(0.0, 1.0);
      case ExportUiState.saving:
        return 1.0;
      case ExportUiState.done:
        return 1.0;
      case ExportUiState.error:
        return 0.0;
      case ExportUiState.none:
        break;
    }

    if (_isConverting) {
      return importState.total > 0
          ? (importState.completed +
                    importState.failed +
                    importState.skipped +
                    importState.canceled) /
                importState.total
          : null;
    }

    if (_isPreparingProject) {
      if (_projectPreparingTotal > 0) {
        return (_projectPreparingCurrent / _projectPreparingTotal).clamp(
          0.0,
          1.0,
        );
      }
      return 0.25;
    }

    return null;
  }

  String? _buildExportPercentText(double? progressValue) {
    if (progressValue == null) return null;
    if (_exportUiState == ExportUiState.preparing) return null;
    final int percent = (progressValue.clamp(0.0, 1.0) * 100).round();
    return '$percent%';
  }

  String? _buildExportAuxProgressText(int importTotal) {
    if (_projectPreparingTotal > 0 &&
        (_isPreparingProject || _exportUiState == ExportUiState.preparing)) {
      final int current = _projectPreparingCurrent.clamp(
        0,
        _projectPreparingTotal,
      );
      return '$current/$_projectPreparingTotal';
    }

    if (_isConverting && importTotal > 0) {
      return _importProgressTotal > 0
          ? '가져오기 처리 중 ($_importProgressCurrent/$_importProgressTotal)'
          : null;
    }

    return null;
  }

  void _setExportUiState(ExportUiState state, [String? message]) {
    if (!mounted) return;
    debugPrint(
      '[Main][ExportUI][State] '
      'from=${_exportUiState.name} to=${state.name} '
      'message=${message ?? ''} '
      'preparing=$_isPreparingProject '
      'prepareCount=$_projectPreparingCurrent/$_projectPreparingTotal',
    );
    setState(() {
      _exportUiState = state;
      _exportUiStatusMessage = message ?? '';
      if (state == ExportUiState.rendering) {
        _renderingVisualProgress = 0.0;
      }
    });

    if (state == ExportUiState.rendering) {
      _startRenderingProgressTicker();
    } else {
      _stopRenderingProgressTicker(
        forceDone: state == ExportUiState.done || state == ExportUiState.saving,
      );
    }
  }

  int _estimateRenderingDurationMs() {
    final int clipCount = _projectPreparingTotal > 0
        ? _projectPreparingTotal
        : 8;
    final int estimated = 6000 + (clipCount * 450);
    return estimated.clamp(8000, 60000);
  }

  void _startRenderingProgressTicker() {
    _renderingProgressTimer?.cancel();
    _renderingProgressStartedAt = DateTime.now();
    _lastRenderingProgressLogBucket = -1;

    _renderingProgressTimer = Timer.periodic(
      const Duration(milliseconds: 180),
      (timer) {
        if (!mounted || _exportUiState != ExportUiState.rendering) {
          timer.cancel();
          return;
        }

        final startedAt = _renderingProgressStartedAt;
        if (startedAt == null) return;
        final int elapsedMs = DateTime.now()
            .difference(startedAt)
            .inMilliseconds;
        final int estimatedMs = _estimateRenderingDurationMs();
        final double linear = (elapsedMs / estimatedMs).clamp(0.0, 1.0);
        final double eased = 1 - (1 - linear) * (1 - linear) * (1 - linear);
        final double visual = (eased * 0.97).clamp(0.0, 0.97);
        final int bucket = (visual * 100 ~/ 10) * 10;

        if (!mounted) return;
        setState(() {
          if (visual > _renderingVisualProgress) {
            _renderingVisualProgress = visual;
          }
        });

        if (bucket != _lastRenderingProgressLogBucket) {
          _lastRenderingProgressLogBucket = bucket;
          debugPrint(
            '[Main][ExportUI][RenderingProgressTick] '
            'elapsedMs=$elapsedMs estimatedMs=$estimatedMs '
            'visual=${_renderingVisualProgress.toStringAsFixed(3)} '
            'percent=${(_renderingVisualProgress * 100).round()}',
          );
        }
      },
    );
  }

  void _stopRenderingProgressTicker({bool forceDone = false}) {
    _renderingProgressTimer?.cancel();
    _renderingProgressTimer = null;
    _renderingProgressStartedAt = null;
    _lastRenderingProgressLogBucket = -1;
    if (forceDone && mounted) {
      setState(() {
        _renderingVisualProgress = 1.0;
      });
    }
  }

  void _clearExportUiState() {
    if (!mounted) return;
    setState(() {
      _exportUiState = ExportUiState.none;
      _exportUiStatusMessage = '';
      _isPreparingProject = false;
      _projectPreparingCurrent = 0;
      _projectPreparingTotal = 0;
    });
  }

  Future<void> _showResultPreview(String resultPath) async {
    if (!mounted || resultPath.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: Colors.black,
      builder: (sheetContext) {
        return SizedBox(
          height: MediaQuery.of(context).size.height,
          child: _resultPreviewPage(
            resultPath: resultPath,
            onClose: () => Navigator.pop(sheetContext),
            onShare: () => _shareExportResult(resultPath),
            onOpenGallery: () {
              debugPrint(
                '[Main][ResultPreview][GalleryTap] '
                'resultPath=$resultPath '
                'exists=${File(resultPath).existsSync()} '
                'mounted=$mounted',
              );
              _openExportedVideoInGallery(resultPath);
            },
            onRetry: () => Navigator.pop(sheetContext),
          ),
        );
      },
    );
  }

  Widget _resultPreviewPage({
    required String resultPath,
    required VoidCallback onClose,
    VoidCallback? onShare,
    VoidCallback? onOpenGallery,
    VoidCallback? onRetry,
    VoidCallback? onEdit,
  }) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ResultPreviewWidget(
          videoPath: resultPath,
          onClose: onClose,
          onShare: onShare,
          onOpenGallery: onOpenGallery,
          onRetry: onRetry,
          onEdit: onEdit,
        ),
      ),
    );
  }

  Future<void> _shareExportResult(String resultPath) async {
    if (resultPath.isEmpty || !mounted) return;

    final String fileName = p.basename(resultPath);
    final message = '결과 영상: $fileName\n$resultPath';
    await Share.share(message);
  }

  Future<void> _openExportedVideoInGallery(String resultPath) async {
    final uri = Uri.file(resultPath);
    debugPrint(
      '[Main][ResultPreview][OpenGallery] start '
      'platform=${Platform.operatingSystem} '
      'uri=$uri '
      'pathExists=${File(resultPath).existsSync()}',
    );

    try {
      final bool canOpen = await canLaunchUrl(uri);
      debugPrint(
        '[Main][ResultPreview][OpenGallery] canLaunchUrl=$canOpen uriScheme=${uri.scheme}',
      );

      final bool opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      debugPrint('[Main][ResultPreview][OpenGallery] launchUrl_opened=$opened');

      if (!opened && mounted) {
        Fluttertoast.showToast(msg: '갤러리를 열 수 없습니다.');
      }
    } catch (e, st) {
      debugPrint('[Main][ResultPreview][OpenGallery] exception=$e');
      debugPrint('[Main][ResultPreview][OpenGallery][Stack]\n$st');
      if (mounted) {
        Fluttertoast.showToast(msg: '갤러리를 열 수 없습니다.');
      }
    }
  }

  Widget _buildBenchmarkBottomNav() {
    final items = const [
      (icon: Icons.photo_camera, label: 'Camera'),
      (icon: Icons.folder, label: 'Library'),
      (icon: Icons.person, label: 'Profile'),
    ];

    return Container(
      key: keyLibraryTab,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC).withAlpha(246),
        border: const Border(top: BorderSide(color: Color(0xFFE5EAF1))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final selected = _selectedIndex == index;
              final color = selected
                  ? const Color(0xFF3B82F6)
                  : const Color(0xFF98A2B3);
              return Expanded(
                child: InkWell(
                  onTap: () {
                    if (index == 2) {
                      final profileTapManager = UserStatusManager();
                      debugPrint(
                        '[Main][ProfileTab][Diag] before_select '
                        'selectedIndex=$_selectedIndex '
                        'tier=${profileTapManager.currentTier} '
                        'productId=${profileTapManager.productId} '
                        'nextTier=${profileTapManager.nextTier} '
                        'effectiveAt=${profileTapManager.nextTierEffectiveAt}',
                      );
                    }

                    setState(() {
                      _selectedIndex = index;
                      if (index == 0 && videoManager.currentAlbum == '휴지통') {
                        videoManager.currentAlbum = '일상';
                      }
                      if (index == 1) {
                        _refreshData();
                      }
                    });

                    if (index == 2) {
                      final profileTapAfterManager = UserStatusManager();
                      debugPrint(
                        '[Main][ProfileTab][Diag] after_select '
                        'selectedIndex=$_selectedIndex '
                        'tier=${profileTapAfterManager.currentTier} '
                        'productId=${profileTapAfterManager.productId}',
                      );
                    }
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [Icon(item.icon, size: 31, color: color)],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1,
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // --- [외부 미디어 가져오기] ---

  Future<void> _pickMedia() async {
    await _pickMediaBatch();
  }

  ImportQueueBuckets _buildImportQueueBuckets(
    List<PendingImportItem> pendingQueue,
  ) {
    if (pendingQueue.isEmpty) {
      return const ImportQueueBuckets(leadQueue: [], backgroundQueue: []);
    }

    final leadCount = pendingQueue.length < _importLeadQueueCount
        ? pendingQueue.length
        : _importLeadQueueCount;
    return ImportQueueBuckets(
      leadQueue: pendingQueue.take(leadCount).toList(growable: false),
      backgroundQueue: pendingQueue.skip(leadCount).toList(growable: false),
    );
  }

  Future<void> _preloadImportItem(
    PendingImportItem item,
    String? itemId,
    Set<String> preloadFailedItemIds,
  ) async {
    if (itemId == null) return;
    if (videoManager.importCancelRequested) {
      videoManager.markItemCanceled(
        itemId,
        error: 'cancel_requested_before_preload',
      );
      return;
    }

    videoManager.markItemPreloading(itemId);
    await Future<void>.delayed(Duration.zero);

    if (item.mediaType == ExternalMediaType.image) {
      final currentStatus = videoManager.importQueueState.items[itemId]?.status;
      if (currentStatus == ImportItemStatus.preloading ||
          currentStatus == ImportItemStatus.queued) {
        videoManager.markItemLoaded(itemId);
      }
      return;
    }

    try {
      final preview = await videoManager.prepareImportPreview(
        item.path,
        timeout: _importPreviewTimeout,
      );
      final currentStatus = videoManager.importQueueState.items[itemId]?.status;
      if (currentStatus == ImportItemStatus.preloading ||
          currentStatus == ImportItemStatus.queued ||
          currentStatus == ImportItemStatus.loaded) {
        videoManager.markItemLoaded(
          itemId,
          durationMs: preview.durationMs,
          thumbnailPath: preview.thumbnailPath,
        );
      }
    } on TimeoutException {
      preloadFailedItemIds.add(itemId);
      videoManager.markItemFailed(itemId, error: 'preload_timeout_10s');
    } catch (e) {
      preloadFailedItemIds.add(itemId);
      videoManager.markItemFailed(itemId, error: 'preload_failed:$e');
    }
  }

  Future<void> _runBackgroundPreloadQueue(
    List<PendingImportItem> queue,
    Map<int, String> itemIdByOrderIndex,
    Set<String> preloadFailedItemIds,
  ) async {
    if (queue.isEmpty) return;

    int cursor = 0;
    final workerCount =
        queue.length < VideoManager.importWorkerDefaultConcurrency
        ? queue.length
        : VideoManager.importWorkerDefaultConcurrency;

    final workers = List.generate(workerCount, (_) async {
      while (true) {
        if (videoManager.importCancelRequested) return;
        if (cursor >= queue.length) return;
        final idx = cursor;
        cursor += 1;

        final item = queue[idx];
        final itemId = itemIdByOrderIndex[item.orderIndex];
        await _preloadImportItem(item, itemId, preloadFailedItemIds);
        await Future<void>.delayed(Duration.zero);
      }
    });

    await Future.wait(workers);
  }

  ExternalMediaType _detectExternalMediaType(String path) {
    final String lowerPath = path.toLowerCase();
    final bool isVideo =
        lowerPath.endsWith('.mp4') ||
        lowerPath.endsWith('.mov') ||
        lowerPath.endsWith('.avi') ||
        lowerPath.endsWith('.m4v');
    return isVideo ? ExternalMediaType.video : ExternalMediaType.image;
  }

  List<PendingImportItem> _buildPendingImportItems(List<String> selectedItems) {
    final List<PendingImportItem> pendingItems =
        selectedItems
            .asMap()
            .entries
            .map(
              (entry) => PendingImportItem(
                path: entry.value,
                mediaType: _detectExternalMediaType(entry.value),
                orderIndex: entry.key,
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    for (final item in pendingItems) {
      debugPrint(
        '[ExternalImport][Phase2] queue_item '
        'orderIndex=${item.orderIndex} '
        'name=${p.basename(item.path)} '
        'type=${item.mediaType.name}',
      );
    }

    return pendingItems;
  }

  List<ImportItemState> _buildImportQueueStates(
    List<PendingImportItem> pendingQueue,
  ) {
    final now = DateTime.now();
    return pendingQueue
        .map(
          (item) => ImportItemState.queued(
            id: 'import_${item.orderIndex}_${item.path.hashCode}_${now.microsecondsSinceEpoch}',
            path: item.path,
            filename: p.basename(item.path),
            index: item.orderIndex,
            now: now,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _pickMediaBatch() async {
    if (_isConverting) {
      debugPrint(
        '[ExternalImport][Phase3] ignored: conversion already in progress',
      );
      return;
    }

    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'heic',
        'heif',
        'mp4',
        'mov',
        'avi',
        'm4v',
      ],
    );

    if (result == null) {
      return;
    }

    final List<String> selectedItems = result.files
        .map((file) => file.path)
        .whereType<String>()
        .where((path) => path.isNotEmpty)
        .toList(growable: false);

    if (selectedItems.isEmpty) {
      return;
    }

    debugPrint(
      '[ExternalImport][Phase1] selectedCount=${selectedItems.length} '
      'album=${videoManager.currentAlbum}',
    );

    final List<PendingImportItem> pendingQueue = _buildPendingImportItems(
      selectedItems,
    );
    if (pendingQueue.isEmpty) {
      return;
    }

    final importQueueItems = _buildImportQueueStates(pendingQueue);
    final itemIdByOrderIndex = <int, String>{
      for (final item in importQueueItems) item.index: item.id,
    };
    videoManager.initializeImportQueue(importQueueItems);

    if (mounted) {
      setState(() {
        _isConverting = true;
        _importProgressCurrent = 0;
        _importProgressTotal = pendingQueue.length;
      });
    }

    int imageSuccessCount = 0;
    int videoSuccessCount = 0;
    int failedCount = 0;
    int cancelledCount = 0;
    final preloadFailedItemIds = <String>{};
    final buckets = _buildImportQueueBuckets(pendingQueue);
    Future<void>? backgroundPreloadFuture;

    try {
      for (final leadItem in buckets.leadQueue) {
        final leadItemId = itemIdByOrderIndex[leadItem.orderIndex];
        await _preloadImportItem(leadItem, leadItemId, preloadFailedItemIds);
      }
      backgroundPreloadFuture = _runBackgroundPreloadQueue(
        buckets.backgroundQueue,
        itemIdByOrderIndex,
        preloadFailedItemIds,
      );

      final int totalCount = pendingQueue.length;
      for (int i = 0; i < totalCount; i++) {
        await Future<void>.delayed(Duration.zero);
        final PendingImportItem item = pendingQueue[i];
        final int current = i + 1;
        final itemId = itemIdByOrderIndex[item.orderIndex];

        if (i > 0) {
          final prevPath = pendingQueue[i - 1].path;
          videoManager.releaseImportPreparationResourcesForPath(prevPath);
        }

        if (videoManager.importCancelRequested) {
          if (itemId != null) {
            videoManager.markItemCanceled(itemId, error: 'cancel_requested');
          }
          cancelledCount += 1;
          continue;
        }

        if (mounted) {
          setState(() {
            _importProgressCurrent = current;
          });
        }

        if (itemId != null) {
          if (preloadFailedItemIds.contains(itemId)) {
            videoManager.markItemSkipped(
              itemId,
              error: 'preload_failed_skipped',
            );
            failedCount += 1;
            continue;
          }
          videoManager.markItemProcessing(itemId);
        }

        debugPrint(
          '[ExternalImport][Phase3] process_item '
          'progress=$current/$totalCount '
          'orderIndex=${item.orderIndex} '
          'name=${p.basename(item.path)} '
          'type=${item.mediaType.name}',
        );

        try {
          if (item.mediaType == ExternalMediaType.image) {
            await videoManager.convertPhotoToVideo(
              item.path,
              videoManager.currentAlbum,
            );
            imageSuccessCount += 1;
            if (itemId != null) {
              videoManager.markItemCompleted(itemId);
            }
          } else {
            if (!mounted) {
              debugPrint(
                '[ExternalImport][Phase3] skip_video_disposed '
                'orderIndex=${item.orderIndex} '
                'name=${p.basename(item.path)}',
              );
              cancelledCount += 1;
              if (itemId != null) {
                videoManager.markItemCanceled(
                  itemId,
                  error: 'context_disposed',
                );
              }
              continue;
            }

            final extracted = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ClipExtractorScreen(
                  videoFile: File(item.path),
                  targetAlbum: videoManager.currentAlbum,
                ),
              ),
            );

            if (extracted == true) {
              videoSuccessCount += 1;
              if (itemId != null) {
                videoManager.markItemCompleted(itemId);
              }
            } else {
              cancelledCount += 1;
              if (itemId != null) {
                videoManager.markItemCanceled(itemId, error: 'user_canceled');
              }
            }

            debugPrint(
              '[ExternalImport][Phase3] video_result '
              'orderIndex=${item.orderIndex} '
              'name=${p.basename(item.path)} '
              'result=$extracted',
            );
          }
        } catch (e) {
          debugPrint(
            '[ExternalImport][Phase3] item_failed '
            'orderIndex=${item.orderIndex} '
            'name=${p.basename(item.path)} '
            'type=${item.mediaType.name} '
            'error=$e',
          );
          failedCount += 1;
          if (itemId != null) {
            videoManager.markItemFailed(itemId, error: '$e');
          }
        }
      }

      await backgroundPreloadFuture;
      videoManager.releaseImportPreparationResourcesForPaths(
        pendingQueue.map((e) => e.path),
      );

      await _loadClipsFromCurrentAlbum();

      Fluttertoast.showToast(
        msg:
            '가져오기 완료 '
            '(이미지 $imageSuccessCount개, 영상 $videoSuccessCount개, '
            '실패 $failedCount개, 취소 $cancelledCount개)',
      );
    } finally {
      if (backgroundPreloadFuture != null) {
        unawaited(backgroundPreloadFuture.catchError((_) => null));
      }
      videoManager.releaseImportPreparationResourcesForPaths(
        pendingQueue.map((e) => e.path),
      );
      if (mounted) {
        setState(() {
          _isConverting = false;
          _importProgressCurrent = 0;
          _importProgressTotal = 0;
        });
      }
    }
  }

  // --- [Project 병합: Native Engine 적용] ---

  Future<void> _handleMerge(List<String> selectedPaths) async {
    final String mergeSessionId =
        'merge_${DateTime.now().millisecondsSinceEpoch}';
    final DateTime mergeStartedAt = DateTime.now();
    final int startedAtMs = mergeStartedAt.millisecondsSinceEpoch;
    final String startedAtIso = mergeStartedAt.toIso8601String();
    bool mergeSucceeded = false;
    String? mergeFailureType;
    String? mergeFailureMessage;
    String videoQualitySelection = 'unknown';
    String audioQualitySelection = 'unknown';
    void _logMergeSessionEnd(String reason) {
      final int sessionDurationMs =
          DateTime.now().millisecondsSinceEpoch - startedAtMs;
      final int? memoryPressureElapsed =
          videoManager.millisSinceLastMemoryPressure;
      debugPrint(
        '[Main][Diag][MergeFlow][SessionEnd] sessionId=$mergeSessionId '
        'reason=$reason durationMs=$sessionDurationMs success=$mergeSucceeded '
        'videoQuality=$videoQualitySelection audioQuality=$audioQualitySelection '
        'exceptionType=$mergeFailureType exceptionMessage=$mergeFailureMessage '
        'memoryPressureRecent=${videoManager.hasRecentMemoryPressure} '
        'memoryPressureElapsedMs=$memoryPressureElapsed '
        'memoryPressureEventCount=${videoManager.memoryPressureEventCount}',
      );
    }

    final int selectedClipCount = selectedPaths.length;
    final bool memoryPressureAtStart = videoManager.hasRecentMemoryPressure;
    final int memoryPressureEventCountAtStart =
        videoManager.memoryPressureEventCount;

    debugPrint(
      '[Main][Diag][MergeFlow][SessionStart] '
      'sessionId=$mergeSessionId startedAt=$startedAtIso '
      'selectedCount=$selectedClipCount '
      'isTutorialFlowActive=$_isTutorialFlowActive '
      'currentAlbum=${videoManager.currentAlbum} '
      'selectedIndex=$_selectedIndex '
      'memoryPressureRecent=$memoryPressureAtStart '
      'memoryPressureEventCount=$memoryPressureEventCountAtStart ',
    );
    debugPrint(
      '[Main][Diag][MergeFlow] start selectedIndex=$_selectedIndex '
      'currentAlbum=${videoManager.currentAlbum} '
      'selectedCount=$selectedClipCount',
    );

    bool completedTutorialThisFlow = false;
    late VlogProject project;
    DateTime? projectReadyAt;
    int projectDurationMs = 0;

    if (videoManager.currentAlbum == "휴지통") {
      Fluttertoast.showToast(msg: "휴지통의 영상으로는 Project를 만들 수 없습니다.");
      debugPrint('[Tutorial][Diag] MergeFlow blocked: currentAlbum is 휴지통');
      debugPrint(
        '[Main][Diag][MergeFlow][SessionEnd] sessionId=$mergeSessionId '
        'success=false reason=invalid_album',
      );
      _logMergeSessionEnd('blocked_invalid_album');
      return;
    }
    if (selectedPaths.length < 2) {
      debugPrint(
        '[Tutorial][Diag] MergeFlow blocked: selectedPaths.length < 2 '
        'count=${selectedPaths.length}',
      );
      debugPrint(
        '[Main][Diag][MergeFlow][SessionEnd] sessionId=$mergeSessionId '
        'success=false reason=insufficient_clips',
      );
      _logMergeSessionEnd('blocked_insufficient_clips');
      return;
    }

    if (_isTutorialFlowActive && !_isTutorialCreateActionArmed) {
      debugPrint(
        '[Tutorial][Diag] MergeFlow blocked: phase3 coach mark dismiss tap (not armed yet)',
      );
      _logMergeSessionEnd('blocked_tutorial_not_armed');
      return;
    }
    if (_isTutorialFlowActive) {
      _isTutorialCreateActionArmed = false;
    }

    if (mounted) {
      setState(() {
        _isPreparingProject = true;
        _projectPreparingTotal = selectedPaths.length;
        _projectPreparingCurrent = 0;
      });
      _setExportUiState(ExportUiState.preparing, '프로젝트 준비 중...');
    }
    try {
      final userStatusManager = UserStatusManager();
      videoQualitySelection = userStatusManager.isStandardOrAbove()
          ? 'project_default'
          : kQuality720p;
      audioQualitySelection = userStatusManager.isStandardOrAbove()
          ? 'default_mix'
          : 'default_clip_only';

      debugPrint(
        '[Tutorial][Diag] MergeFlow calling createProject '
        'sessionId=$mergeSessionId paths=${selectedPaths.join(',')}',
      );
      // Create a project
      project = await videoManager.createProject(
        selectedPaths,
        onClipPrepared: (current, total, path) {
          if (!mounted) return;
          setState(() {
            _projectPreparingCurrent = current;
            _projectPreparingTotal = total;
          });
          debugPrint(
            '[Main][ExportUI][PrepareProgress] '
            'current=$current total=$total path=$path sessionId=$mergeSessionId',
          );
        },
      );
      if (mounted) {
        setState(() {
          _projectPreparingCurrent = selectedPaths.length;
        });
        _setExportUiState(ExportUiState.preparing, '프로젝트 준비 완료');
      }
      projectReadyAt = DateTime.now();
      projectDurationMs = project.clips.fold<int>(0, (sum, clip) {
        final playbackMs =
            clip.endTime.inMilliseconds - clip.startTime.inMilliseconds;
        if (playbackMs > 0) return sum + playbackMs;
        if (clip.originalDuration > Duration.zero) {
          return sum + clip.originalDuration.inMilliseconds;
        }
        if (clip.endTime > Duration.zero)
          return sum + clip.endTime.inMilliseconds;
        return sum;
      });
      final int zeroDurationClipCount = project.clips
          .where(
            (clip) =>
                clip.originalDuration <= Duration.zero &&
                (clip.endTime == Duration.zero ||
                    clip.startTime == clip.endTime),
          )
          .length;

      debugPrint(
        '[Tutorial][Diag] MergeFlow createProject snapshot sessionId=$mergeSessionId '
        'projectId=${project.id} clipCount=${project.clips.length} '
        'projectDurationMs=$projectDurationMs zeroDurationClipCount=$zeroDurationClipCount '
        'firstClip=${project.clips.isNotEmpty ? project.clips.first.path : "none"}',
      );

      audioQualitySelection = project.bgmPath?.isNotEmpty == true
          ? 'bgm_mix'
          : 'clip_only';

      debugPrint(
        '[Tutorial][Diag] MergeFlow createProject done sessionId=$mergeSessionId '
        'projectId=${project.id} clipCount=${project.clips.length} '
        'videoQuality=$videoQualitySelection audioQuality=$audioQualitySelection',
      );
    } catch (e) {
      mergeFailureType = e.runtimeType.toString();
      mergeFailureMessage = e.toString();
      debugPrint(
        '[Tutorial][Diag] MergeFlow createProject error sessionId=$mergeSessionId '
        'type=$mergeFailureType message=$mergeFailureMessage',
      );
      if (mounted) {
        Fluttertoast.showToast(msg: '프로젝트 준비 중 오류가 발생했습니다: $e');
        _setExportUiState(ExportUiState.error, '프로젝트 준비 중 오류가 발생했습니다');
      }
      _logMergeSessionEnd('create_project_failed');
      _clearExportUiState();
      return;
    } finally {
      if (mounted) {
        setState(() => _isPreparingProject = false);
      }
    }

    final userStatusManager = UserStatusManager();

    // Free: 편집 미지원 → 720p 빠른 Export
    if (!userStatusManager.isStandardOrAbove()) {
      debugPrint(
        '[Tutorial][Diag] MergeFlow freeTier export path userTier=${userStatusManager.currentTier} '
        'sessionId=$mergeSessionId videoQuality=$videoQualitySelection '
        'audioQuality=$audioQualitySelection',
      );
      // Fluttertoast.showToast(msg: '편집은 Standard부터 지원합니다. 720p로 바로 내보냅니다.');

      final audioConfig = <String, double>{
        for (final clip in project.clips) clip.path: 1.0,
      };

      final int freeBranchExportStartMs = DateTime.now().millisecondsSinceEpoch;
      final int audioConfigMissingCount = project.clips
          .where((clip) => !audioConfig.containsKey(clip.path))
          .length;
      final int zeroVolumeCount = audioConfig.values
          .where((v) => v <= 0)
          .length;

      debugPrint(
        '[Tutorial][Diag] MergeFlow free_export_preflight sessionId=$mergeSessionId '
        'clipCount=${project.clips.length} audioConfigCount=${audioConfig.length} '
        'missingAudioConfigCount=$audioConfigMissingCount zeroOrNegativeVolumeCount=$zeroVolumeCount '
        'projectDurationMs=${projectDurationMs}',
      );

      _setExportUiState(ExportUiState.rendering, '내보내기 렌더링 중...');
      final resultPath = await videoManager.exportVlog(
        clips: project.clips,
        audioConfig: audioConfig,
        bgmPath: project.bgmPath,
        bgmVolume: project.bgmVolume,
        quality: kQuality720p,
        userTier: kUserTierFree,
        mergeSessionId: mergeSessionId,
        debugTag: 'MergeFlow_free',
      );
      final int freeBranchExportElapsedMs =
          DateTime.now().millisecondsSinceEpoch - freeBranchExportStartMs;

      debugPrint(
        '[Tutorial][Diag] MergeFlow free_export_completed_after_platform '
        'sessionId=$mergeSessionId resultPath=$resultPath '
        'elapsedMs=$freeBranchExportElapsedMs '
        'projectReadyToExportMs=${projectReadyAt.millisecondsSinceEpoch - startedAtMs}',
      );

      if (resultPath != null) {
        _setExportUiState(ExportUiState.saving, '갤러리 저장 중...');
        Fluttertoast.showToast(msg: '720p 내보내기 완료');
        mergeSucceeded = true;
        _setExportUiState(ExportUiState.done, '내보내기 완료');
        debugPrint(
          '[Tutorial][Diag] MergeFlow export resultPath=$resultPath '
          'sessionId=$mergeSessionId',
        );
        await _showResultPreview(resultPath);
        await _refreshData();
        if (_isTutorialFlowActive) {
          await _completeTutorialAfterExport();
          completedTutorialThisFlow = true;
        }
      } else {
        Fluttertoast.showToast(msg: '내보내기에 실패했습니다. 다시 시도해주세요.');
        mergeFailureType = 'ExportResultNull';
        mergeFailureMessage = 'resultPath is null';
        _setExportUiState(ExportUiState.error, '내보내기 실패');
        await Future.delayed(const Duration(milliseconds: 700));
      }

      _logMergeSessionEnd(
        resultPath != null
            ? 'free_export_completed'
            : 'free_export_platform_returned_null',
      );
      _clearExportUiState();
      return;
    }

    // Navigate to VideoEditScreen for editing & export
    debugPrint(
      '[Main][Diag][MergeFlow] before_push_edit selectedIndex=$_selectedIndex '
      'projectId=${project.id} clipCount=${project.clips.length} '
      'sessionId=$mergeSessionId',
    );
    final dynamic result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            VideoEditScreen(project: project, mergeSessionId: mergeSessionId),
      ),
    );

    debugPrint(
      '[Main][Diag][MergeFlow] after_pop_edit selectedIndex=$_selectedIndex '
      'result=$result projectId=${project.id} sessionId=$mergeSessionId',
    );

    if (result is String && result.isNotEmpty) {
      mergeSucceeded = true;
      _setExportUiState(ExportUiState.saving, '갤러리 저장 중...');
      _setExportUiState(ExportUiState.done, '내보내기 완료');
      if (_isTutorialFlowActive) {
        await _completeTutorialAfterExport();
        completedTutorialThisFlow = true;
      }
      if (mounted && !completedTutorialThisFlow) {
        setState(() {
          // Library 다중선택 -> 프로젝트 생성 -> 편집 종료(X) 흐름에서는
          // 프로젝트 목록으로 복귀시키는 UX가 자연스럽다.
          _selectedIndex = 1;
        });
      }
      await _refreshData();
      await _showResultPreview(result);
      _clearExportUiState();
    } else if (result == true) {
      mergeSucceeded = true;
      if (_isTutorialFlowActive) {
        await _completeTutorialAfterExport();
        completedTutorialThisFlow = true;
      }
      if (mounted && !completedTutorialThisFlow) {
        setState(() {
          // Library 다중선택 -> 프로젝트 생성 -> 편집 종료(X) 흐름에서는
          // 프로젝트 목록으로 복귀시키는 UX가 자연스럽다.
          _selectedIndex = 1;
        });
      }
      await _refreshData();
      _clearExportUiState();
    } else {
      mergeSucceeded = false;
      mergeFailureType = result == null
          ? 'EditResultNotTrue'
          : 'EditResultInvalid';
      mergeFailureMessage = 'result=$result';
      if (result == null) {
        debugPrint(
          '[Tutorial][Diag] MergeFlow edit_result_null_after_create_project '
          'sessionId=$mergeSessionId projectReadyAt=${projectReadyAt.toIso8601String()}',
        );
      }
      debugPrint(
        '[Tutorial][Diag] MergeFlow edit result!=true: result=$result'
        ' sessionId=$mergeSessionId',
      );
      _setExportUiState(ExportUiState.error, '내보내기 실패');
      await Future.delayed(const Duration(milliseconds: 700));
      _clearExportUiState();
    }

    _logMergeSessionEnd('edit_export_completed');
  }

  // --- [UI 탭 빌더] ---

  Widget _buildCaptureTab() {
    return CaptureScreen(recordButtonKey: keyRecordButton);
  }

  Widget _buildLibraryTab() {
    return LibraryScreen(
      keyPickMedia: keyPickMedia,
      keyAlbumGridItem: keyAlbumGridItem,
      keyFirstClip: keyFirstClip,
      keyCreateProject: keyCreateProject,
      onRefreshData: _refreshData,
      onMerge: (paths) => _handleMerge(paths), // ✅ 직접 경로 전달
      onPickMedia: (album) => _pickMedia(),
      onAlbumDetailVisibilityChanged: _onAlbumDetailVisibilityChanged,
      onCreateProjectButtonVisibilityChanged:
          _onCreateProjectButtonVisibilityChanged,
      isActive: _selectedIndex == 1,
    );
  }

  // --- [편집 요청 핸들러] ---

  /// 편집 요청 처리 (구매 트리거 포함)
  Future<void> _handleEditRequest(String videoPath) async {
    final userStatusManager = UserStatusManager();

    // Free: 편집 미지원 → 720p 빠른 Export
    if (!userStatusManager.isStandardOrAbove()) {
      // Fluttertoast.showToast(msg: '편집은 Standard부터 지원합니다. 720p로 바로 내보냅니다.');

      final project = await videoManager.createProject([videoPath]);
      final audioConfig = <String, double>{
        for (final clip in project.clips) clip.path: 1.0,
      };

      final mergeSessionId = 'edit_${DateTime.now().millisecondsSinceEpoch}';
      final resultPath = await videoManager.exportVlog(
        clips: project.clips,
        audioConfig: audioConfig,
        bgmPath: project.bgmPath,
        bgmVolume: project.bgmVolume,
        quality: kQuality720p,
        userTier: kUserTierFree,
        mergeSessionId: mergeSessionId,
        debugTag: 'Main_free_edit_request',
      );

      if (resultPath != null) {
        Fluttertoast.showToast(msg: '720p 내보내기 완료');
        await _refreshData();
      } else {
        Fluttertoast.showToast(msg: '내보내기에 실패했습니다. 다시 시도해주세요.');
      }
      return;
    }

    // Standard 이상 → VideoEditScreen으로 이동
    if (mounted) {
      // Create a temporary project for single clip editing
      // Note: In real app, we might want to create a proper project or use a specific "Edit Single" mode.
      // Here we wrap it in a project.
      final project = await videoManager.createProject([videoPath]);

      final String mergeSessionId =
          'edit_${DateTime.now().millisecondsSinceEpoch}';
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              VideoEditScreen(project: project, mergeSessionId: mergeSessionId),
        ),
      );

      if (result == true) {
        Fluttertoast.showToast(msg: "편집 완료");
        await _refreshData();
      }
    }
  }

  Widget _buildProfileTab() {
    return const ProfileScreen();
  }
}
