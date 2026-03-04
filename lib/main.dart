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

import 'managers/user_status_manager.dart';
import 'services/iap_service.dart';
import 'services/auth_service.dart';
import 'services/cloud_service.dart';
import 'services/notification_settings_service.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/capture_screen.dart';
import 'screens/library_screen.dart';
import 'screens/project_screen.dart';
import 'managers/video_manager.dart';
import 'models/vlog_project.dart';
import 'screens/video_edit_screen.dart';
import 'screens/clip_extractor_screen.dart'; // ✅ 추가
import 'widgets/video_widgets.dart';
import 'utils/haptics.dart';

late List<CameraDescription> cameras;
final Stopwatch appLaunchStopwatch = Stopwatch();
bool _didLogFirstCameraPreviewReady = false;

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

    final downgraded = await userStatusManager.evaluateAndAutoDowngradeIfExpired(
      reason: 'startup_warmup',
    );
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
            titleTextStyle: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
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
                body: Center(
                  child: CircularProgressIndicator(),
                ),
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

  bool _isConverting = false;
  bool _isPreparingProject = false;
  bool _didBindVideoManager = false;
  late VideoManager videoManager;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initFirebaseMessaging();
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
        Fluttertoast.showToast(msg: title, backgroundColor: Colors.black87, textColor: Colors.white);
      }
    });

    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
    await notificationSettingsService.migrateCategorySettingsIfNeeded();
    await notificationSettingsService.ensureStartupSync();

    final shouldShowPrompt =
        await notificationSettingsService.shouldShowInitialPermissionPrompt();
    if (!shouldShowPrompt) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _showNotificationPermissionDialog());
  }

  Future<void> _showNotificationPermissionDialog() async {
    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('3s 알림 받기'),
        content: const Text('새로운 클립, 브이로그 상태, 특별 혜택을 놓치지 않도록 푸시 알림을 허용해주세요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('다음에'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            child: const Text('알림 허용'),
          ),
        ],
      ),
    );

    final notificationSettingsService = NotificationSettingsService.instance;
    await notificationSettingsService.markInitialPermissionPrompted();

    if (result == true) {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      final success = settings.authorizationStatus == AuthorizationStatus.authorized;
      await notificationSettingsService.syncTopicSubscriptions(
        authorizationStatus: settings.authorizationStatus,
      );
      Fluttertoast.showToast(
        msg: success ? '알림을 활성화했습니다.' : '알림 권한이 허용되지 않았습니다.',
        backgroundColor: Colors.black87,
        textColor: Colors.white,
      );
    } else {
      Fluttertoast.showToast(
        msg: '알림은 설정에서 언제든 활성화할 수 있습니다.',
        backgroundColor: Colors.black87,
        textColor: Colors.white,
      );
    }
  }

  Future<void> _checkAndStartTutorial() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool isFirstRun = prefs.getBool('isFirstRun') ?? true;
    if (isFirstRun && mounted) {
      setState(() => _selectedIndex = 0);
      _showTutorialPhase1();
    }
  }

  // --- [튜토리얼 로직] ---

  void _showTutorialPhase1() {
    TutorialCoachMark(
      targets: [
        TargetFocus(
          identify: "step1_record",
          keyTarget: keyRecordButton,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              builder: (context, controller) => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("3초 촬영", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
                  SizedBox(height: 10),
                  Text("버튼을 눌러 나만의 3초 영상을 기록하세요.", style: TextStyle(color: Colors.white, fontSize: 16)),
                ],
              ),
            )
          ],
          shape: ShapeLightFocus.Circle,
        ),
      ],
      colorShadow: Colors.black,
      opacityShadow: 0.8,
      onFinish: () {
        setState(() => _selectedIndex = 1);
        Future.delayed(const Duration(milliseconds: 600), _showTutorialPhase2);
      },
      onSkip: () { _finishTutorial(); return true; },
    ).show(context: context);
  }

  void _showTutorialPhase2() {
    TutorialCoachMark(
      targets: [
        TargetFocus(
          identify: "step2_album",
          keyTarget: keyAlbumGridItem,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              builder: (context, controller) => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("앨범 진입", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
                  SizedBox(height: 10),
                  Text("'일상' 앨범을 눌러 상세 화면으로 이동합니다.", style: TextStyle(color: Colors.white, fontSize: 16)),
                ],
              ),
            )
          ],
          shape: ShapeLightFocus.RRect,
          radius: 20,
        ),
      ],
      colorShadow: Colors.black,
      opacityShadow: 0.8,
      onFinish: () async {
        setState(() {
          videoManager.currentAlbum = '일상';
        });
        await _loadClipsFromCurrentAlbum();
        Future.delayed(const Duration(milliseconds: 600), _showTutorialPhase3);
      },
      onSkip: () { _finishTutorial(); return true; },
    ).show(context: context);
  }

  void _showTutorialPhase3() {
    TutorialCoachMark(
      targets: [
        TargetFocus(
          identify: "step3_clip",
          keyTarget: keyFirstClip,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              builder: (context, controller) => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("롱 프레스 선택", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
                  SizedBox(height: 10),
                  Text("클립을 '꾹' 누르면 선택 모드가 시작됩니다.\n2개 이상 선택하여 Project를 만들어보세요!", style: TextStyle(color: Colors.white, fontSize: 16)),
                ],
              ),
            )
          ],
        ),
      ],
      colorShadow: Colors.black,
      opacityShadow: 0.8,
      onFinish: () => _showTutorialPhase4(),
      onSkip: () { _finishTutorial(); return true; },
    ).show(context: context);
  }
  
  void _showTutorialPhase4() {
    TutorialCoachMark(
      targets: [
        TargetFocus(
          identify: "step4_pick",
          keyTarget: keyPickMedia,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              builder: (context, controller) => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("외부 파일 가져오기", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
                  SizedBox(height: 10),
                  Text("갤러리의 사진이나 영상을 가져와 3초 영상으로 변환할 수 있습니다.", style: TextStyle(color: Colors.white, fontSize: 16)),
                ],
              ),
            )
          ],
          shape: ShapeLightFocus.Circle,
        ),
      ],
      colorShadow: Colors.black,
      opacityShadow: 0.8,
      onFinish: () => _finishTutorial(),
      onSkip: () { _finishTutorial(); return true; },
    ).show(context: context);
  }

  Future<void> _finishTutorial() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isFirstRun', false);
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
                _buildProjectTab(),
                const ProfileScreen(),
              ],
            ),
            if (_isConverting || _isPreparingProject)
              Container(
                color: Colors.black.withOpacity(0.5),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const LinearProgressIndicator(color: Colors.blueAccent),
                        const SizedBox(height: 20),
                        Text(
                          _isPreparingProject ? '프로젝트 준비 중...' : '영상 변환 중...',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
    final userStatusManager = UserStatusManager();
    final canAccessProject = userStatusManager.isStandardOrAbove();
    debugPrint(
      '[Main][TierGate][Build] cachedCanAccessProject=$canAccessProject '
      'tier=${userStatusManager.currentTier} productId=${userStatusManager.productId}',
    );

    final items = const [
      (icon: Icons.photo_camera, label: 'Camera'),
      (icon: Icons.folder, label: 'Library'),
      (icon: Icons.play_circle, label: 'Project'),
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
                    bool canAccessProjectNow = canAccessProject;
                    if (index == 2) {
                      final liveManager = UserStatusManager();
                      final liveCanAccess = liveManager.isStandardOrAbove();
                      canAccessProjectNow = liveCanAccess;
                      debugPrint(
                        '[Main][TierGate][Tap] cachedCanAccessProject=$canAccessProject '
                        'liveCanAccessProject=$liveCanAccess '
                        'tier=${liveManager.currentTier} productId=${liveManager.productId}',
                      );
                    }

                    if (index == 2 && !canAccessProjectNow) {
                      Fluttertoast.showToast(
                        msg: 'Project는 Standard부터 이용 가능합니다.',
                      );
                      return;
                    }

                    if (index == 3) {
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

                    if (index == 3) {
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
                        children: [
                          Icon(
                            item.icon,
                            size: 31,
                            color: color,
                          ),
                          if (index == 2 && !canAccessProject)
                            Positioned(
                              right: -6,
                              top: -5,
                              child: Container(
                                width: 13,
                                height: 13,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF4CF00),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.star,
                                  color: Colors.white,
                                  size: 8,
                                ),
                              ),
                            ),
                        ],
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

    final isVideo = media.path.toLowerCase().endsWith('.mp4') || 
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
        await videoManager.convertPhotoToVideo(media.path, videoManager.currentAlbum);
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
      '[Main][Diag][MergeFlow] start selectedIndex=$_selectedIndex '
      'currentAlbum=${videoManager.currentAlbum} selectedCount=${selectedPaths.length}',
    );

    if (videoManager.currentAlbum == "휴지통") {
      Fluttertoast.showToast(msg: "휴지통의 영상으로는 Project를 만들 수 없습니다.");
      return;
    }
    if (selectedPaths.length < 2) return;

    VlogProject project;
    if (mounted) {
      setState(() => _isPreparingProject = true);
    }
    try {
      // Create a project
      project = await videoManager.createProject(selectedPaths);
    } catch (e) {
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
      Fluttertoast.showToast(
        msg: '편집은 Standard부터 지원합니다. 720p로 바로 내보냅니다.',
      );

      final audioConfig = <String, double>{
        for (final clip in project.clips) clip.path: 1.0,
      };

      final resultPath = await videoManager.exportVlog(
        clips: project.clips,
        audioConfig: audioConfig,
        bgmPath: project.bgmPath,
        bgmVolume: project.bgmVolume,
        quality: '720p',
        userTier: 'free',
      );

      if (resultPath != null) {
        Fluttertoast.showToast(msg: '720p 내보내기 완료');
        await _refreshData();
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
        builder: (context) => VideoEditScreen(
          project: project,
        ),
      ),
    );

    debugPrint(
      '[Main][Diag][MergeFlow] after_pop_edit selectedIndex=$_selectedIndex '
      'result=$result projectId=${project.id}',
    );

    if (result == true) {
      if (mounted) {
        setState(() {
          // Library 다중선택 -> 프로젝트 생성 -> 편집 종료(X) 흐름에서는
          // 프로젝트 목록으로 복귀시키는 UX가 자연스럽다.
          _selectedIndex = 2;
        });
      }

      await _refreshData();
      debugPrint(
        '[Main][Diag][MergeFlow] refreshed_after_result_true selectedIndex=$_selectedIndex '
        'projectId=${project.id}',
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
      keyFirstClip: keyFirstClip,
      onRefreshData: _refreshData,
      onMerge: (paths) => _handleMerge(paths),  // ✅ 직접 경로 전달
      onPickMedia: (album) => _pickMedia(),
    );
  }

  // --- [편집 요청 핸들러] ---

  /// 편집 요청 처리 (구매 트리거 포함)
  Future<void> _handleEditRequest(String videoPath) async {
    final userStatusManager = UserStatusManager();

    // Free: 편집 미지원 → 720p 빠른 Export
    if (!userStatusManager.isStandardOrAbove()) {
      Fluttertoast.showToast(
        msg: '편집은 Standard부터 지원합니다. 720p로 바로 내보냅니다.',
      );

      final project = await videoManager.createProject([videoPath]);
      final audioConfig = <String, double>{
        for (final clip in project.clips) clip.path: 1.0,
      };

      final resultPath = await videoManager.exportVlog(
        clips: project.clips,
        audioConfig: audioConfig,
        bgmPath: project.bgmPath,
        bgmVolume: project.bgmVolume,
        quality: '720p',
        userTier: 'free',
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
          builder: (context) => VideoEditScreen(
            project: project,
          ),
        ),
      );

      if (result == true) {
        Fluttertoast.showToast(msg: "편집 완료");
        await _refreshData();
      }
    }
  }

  /// ✅ 3. Project 탭 - ProjectScreen으로 분리 완료
  Widget _buildProjectTab() {
    return ProjectScreen(
      onRefresh: _refreshData,
    );
  }

  Widget _buildProfileTab() {
    return const ProfileScreen();
  }
}
