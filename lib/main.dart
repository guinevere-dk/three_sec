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
import 'package:image_picker/image_picker.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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

void logFirstCameraPreviewReady() {
  if (_didLogFirstCameraPreviewReady) return;
  _didLogFirstCameraPreviewReady = true;
  if (!appLaunchStopwatch.isRunning) return;
  appLaunchStopwatch.stop();
  debugPrint(
    '[Startup][TTFF] app_launch_to_camera_preview_ms=${appLaunchStopwatch.elapsedMilliseconds}',
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

  // Firebase 초기화
  try {
    await Firebase.initializeApp();
    print('[Main] Firebase 초기화 완료');
  } catch (e) {
    print('[Main] Firebase 초기화 실패: $e');
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
        title: '3s 2.6.0 Native',
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
      builder: (context, isBootstrapping, _) => StreamBuilder(
        initialData: authService.currentUser,
        stream: authService.authStateChanges,
        builder: (context, snapshot) {
          // 로그인 상태 확인
          if (snapshot.hasData && snapshot.data != null) {
            // 로그인 직후 구독 동기화가 끝날 때까지 게이트에서 대기
            if (isBootstrapping) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            // 로그인 완료 + 세션 부트스트랩 완료 → 메인 화면
            return const MainNavigationScreen();
          } else {
            // 로그인 안 됨 → 로그인 화면
            return const LoginScreen();
          }
        },
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

  final ImagePicker _picker = ImagePicker();

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didRequestTutorialCheck) return;
      _didRequestTutorialCheck = true;
      unawaited(_checkAndStartTutorial());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 자동 전체 백업 트리거 축소:
    // 앱 resume 시점의 일괄 enqueue는 사용자가 선택한 일부 클립 업로드와 충돌할 수 있어 비활성화.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didBindVideoManager) return;
    videoManager = Provider.of<VideoManager>(context, listen: false);
    _didBindVideoManager = true;
    _refreshData();
  }

  Future<void> _initFirebaseMessaging() async {
    if (kIsWeb) return;
    final notificationSettingsService = NotificationSettingsService.instance;

    FirebaseMessaging.onMessage.listen((message) {
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

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final title = message.notification?.title ?? "알림을 열었습니다.";
      if (mounted) {
        Fluttertoast.showToast(
          msg: title,
          backgroundColor: Colors.black87,
          textColor: Colors.white,
        );
      }
    });

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
                    "3s로 나만의 영상앨범을 간직해보세요!",
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
    // 자동 전체 백업 트리거 축소:
    // refresh 시점 자동 enqueue 비활성화 (수동 이동/명시적 백업만 허용)
    if (mounted) setState(() {});
    CloudService().checkUsageAndAlert(videoManager);
  }

  Future<void> _loadClipsFromCurrentAlbum() async {
    setState(() {
      videoManager.recordedVideoPaths.clear();
    });
    await videoManager.loadClipsFromCurrentAlbum();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
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
            if (_isConverting || _isPreparingProject)
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
                        const LinearProgressIndicator(color: Colors.blueAccent),
                        const SizedBox(height: 20),
                        Text(
                          _isPreparingProject ? '프로젝트 준비 중...' : '영상 변환 중...',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
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
    final XFile? media = await _picker.pickMedia();
    if (media == null) return;

    final isVideo =
        media.path.toLowerCase().endsWith('.mp4') ||
        media.path.toLowerCase().endsWith('.mov') ||
        media.path.toLowerCase().endsWith('.avi');

    if (isVideo) {
      // ✅ 수정: 긴 영상은 ClipExtractorScreen으로 이동 (구간 추출)
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ClipExtractorScreen(
            videoFile: File(media.path),
            targetAlbum: videoManager.currentAlbum,
          ),
        ),
      );

      if (result == true) {
        await _loadClipsFromCurrentAlbum();
        // 자동 전체 백업 트리거 축소:
        // import 직후 자동 enqueue 비활성화
        // Fluttertoast.showToast(msg: "저장 완료"); // 안쪽에서 토스트 띄움
      }
    } else {
      setState(() => _isConverting = true);
      try {
        await videoManager.convertPhotoToVideo(
          media.path,
          videoManager.currentAlbum,
        );
        Fluttertoast.showToast(msg: "변환 완료");
        await _loadClipsFromCurrentAlbum();
        // 자동 전체 백업 트리거 축소:
        // import 직후 자동 enqueue 비활성화
      } catch (e) {
        Fluttertoast.showToast(msg: "변환 실패: $e");
      } finally {
        if (mounted) setState(() => _isConverting = false);
      }
    }
  }

  // --- [Project 병합: Native Engine 적용] ---

  Future<void> _handleMerge(List<String> selectedPaths) async {
    debugPrint(
      '[Tutorial][Diag] MergeFlow start '
      'selectedCount=${selectedPaths.length} '
      'isTutorialFlowActive=$_isTutorialFlowActive '
      'currentAlbum=${videoManager.currentAlbum} '
      'selectedIndex=$_selectedIndex',
    );
    bool completedTutorialThisFlow = false;
    debugPrint(
      '[Main][Diag][MergeFlow] start selectedIndex=$_selectedIndex '
      'currentAlbum=${videoManager.currentAlbum} selectedCount=${selectedPaths.length}',
    );

    if (videoManager.currentAlbum == "휴지통") {
      Fluttertoast.showToast(msg: "휴지통의 영상으로는 Project를 만들 수 없습니다.");
      debugPrint('[Tutorial][Diag] MergeFlow blocked: currentAlbum is 휴지통');
      return;
    }
    if (selectedPaths.length < 2) {
      debugPrint(
        '[Tutorial][Diag] MergeFlow blocked: selectedPaths.length < 2 '
        'count=${selectedPaths.length}',
      );
      return;
    }

    if (_isTutorialFlowActive && !_isTutorialCreateActionArmed) {
      debugPrint(
        '[Tutorial][Diag] MergeFlow blocked: phase3 coach mark dismiss tap (not armed yet)',
      );
      return;
    }
    if (_isTutorialFlowActive) {
      _isTutorialCreateActionArmed = false;
    }

    VlogProject project;
    if (mounted) {
      setState(() => _isPreparingProject = true);
    }
    try {
      debugPrint(
        '[Tutorial][Diag] MergeFlow calling createProject paths=${selectedPaths.join(',')}',
      );
      // Create a project
      project = await videoManager.createProject(selectedPaths);
      debugPrint(
        '[Tutorial][Diag] MergeFlow createProject done projectId=${project.id} '
        'clipCount=${project.clips.length}',
      );
    } catch (e) {
      debugPrint('[Tutorial][Diag] MergeFlow createProject error: $e');
      if (mounted) {
        Fluttertoast.showToast(msg: '프로젝트 준비 중 오류가 발생했습니다: $e');
      }
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
        '[Tutorial][Diag] MergeFlow freeTier export path userTier=${userStatusManager.currentTier}',
      );
      // Fluttertoast.showToast(msg: '편집은 Standard부터 지원합니다. 720p로 바로 내보냅니다.');

      final audioConfig = <String, double>{
        for (final clip in project.clips) clip.path: 1.0,
      };

      final resultPath = await videoManager.exportVlog(
        clips: project.clips,
        audioConfig: audioConfig,
        bgmPath: project.bgmPath,
        bgmVolume: project.bgmVolume,
        quality: kQuality720p,
        userTier: kUserTierFree,
      );

      if (resultPath != null) {
        Fluttertoast.showToast(msg: '720p 내보내기 완료');
        debugPrint('[Tutorial][Diag] MergeFlow export resultPath=$resultPath');
        await _refreshData();
        if (_isTutorialFlowActive) {
          await _completeTutorialAfterExport();
          completedTutorialThisFlow = true;
        }
      } else {
        Fluttertoast.showToast(msg: '내보내기에 실패했습니다. 다시 시도해주세요.');
      }
      return;
    }

    // Navigate to VideoEditScreen for editing & export
    debugPrint(
      '[Main][Diag][MergeFlow] before_push_edit selectedIndex=$_selectedIndex '
      'projectId=${project.id} clipCount=${project.clips.length}',
    );
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoEditScreen(project: project),
      ),
    );

    debugPrint(
      '[Main][Diag][MergeFlow] after_pop_edit selectedIndex=$_selectedIndex '
      'result=$result projectId=${project.id}',
    );

    if (result == true) {
      debugPrint('[Tutorial][Diag] MergeFlow edit result=true');
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
      debugPrint('[Tutorial][Diag] MergeFlow refresh done on edit success');
      debugPrint(
        '[Main][Diag][MergeFlow] refreshed_after_result_true selectedIndex=$_selectedIndex '
        'projectId=${project.id}',
      );
    } else {
      debugPrint(
        '[Tutorial][Diag] MergeFlow edit result!=true: result=$result',
      );
    }
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

      final resultPath = await videoManager.exportVlog(
        clips: project.clips,
        audioConfig: audioConfig,
        bgmPath: project.bgmPath,
        bgmVolume: project.bgmVolume,
        quality: kQuality720p,
        userTier: kUserTierFree,
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

      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoEditScreen(project: project),
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
