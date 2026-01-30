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

import 'managers/user_status_manager.dart';
import 'services/iap_service.dart';
import 'services/auth_service.dart';
import 'services/cloud_service.dart';
import 'screens/paywall_screen.dart';
import 'screens/login_screen.dart';
import 'managers/video_manager.dart';

// 💡 외부 편집 화면 파일 임포트
import 'screens/video_edit_screen.dart';

late List<CameraDescription> cameras;

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[FCM] background message: ${message.messageId}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Firebase 초기화
  try {
    await Firebase.initializeApp();
    print('[Main] Firebase 초기화 완료');
  } catch (e) {
    print('[Main] Firebase 초기화 실패: $e');
  }
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint("카메라를 찾을 수 없습니다: $e");
    cameras = [];
  }
  await UserStatusManager().initialize();
  await IAPService().initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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

    return StreamBuilder(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        // 로딩 중
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // 로그인 상태 확인
        if (snapshot.hasData && snapshot.data != null) {
          // 로그인 완료 → 메인 화면
          return const MainNavigationScreen();
        } else {
          // 로그인 안 됨 → 로그인 화면
          return const LoginScreen();
        }
      },
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});
  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with TickerProviderStateMixin {
  
  // 💡 [핵심] 네이티브 엔진과 통신하는 직통 채널 개설
  static const platform = MethodChannel('com.dk.three_sec/video_engine');

  int _selectedIndex = 0;
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  late TabController _libraryTabController;
  int _libraryTabIndex = 0;

  final ImagePicker _picker = ImagePicker();

  // 튜토리얼용 GlobalKey
  final GlobalKey keyRecordButton = GlobalKey();
  final GlobalKey keyLibraryTab = GlobalKey();
  final GlobalKey keyAlbumGridItem = GlobalKey();
  final GlobalKey keyFirstClip = GlobalKey();
  final GlobalKey keyActionsArea = GlobalKey();
  final GlobalKey keyPickMedia = GlobalKey();

  bool _isConverting = false;
  bool _isRecording = false;
  int _remainingTime = 3;
  Timer? _recordingTimer;
  Offset? _tapPosition;
  late AnimationController _focusAnimController;
  bool _notificationPermissionRequested = false;

  double _exposureOffset = 0.0;
  double _minExposure = 0.0;
  double _maxExposure = 0.0;
  bool _showExposureSlider = false;
  Timer? _exposureTimer;

  bool _isInAlbumDetail = false;
  bool _isClipSelectionMode = false;
  bool _isAlbumSelectionMode = false;
  bool _isDragAdding = true;
  int? _lastProcessedIndex;
  
  // 그리드 줌 설정
  int _gridColumnCount = 3;
  bool _isZoomingLocked = false;
  
  // 사이드바 설정
  bool _isSidebarOpen = true; 
  final double _narrowSidebarWidth = 80.0;

  String? _previewingPath;

  final GlobalKey _clipGridKey = GlobalKey(debugLabel: 'clipGrid');
  final GlobalKey _albumGridKey = GlobalKey(debugLabel: 'albumGrid');

  List<String> _selectedClipPaths = [];
  Set<String> _selectedAlbumNames = {};
  int _cameraIndex = 0;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _focusAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _libraryTabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!mounted || _libraryTabController.indexIsChanging) return;
        setState(() => _libraryTabIndex = _libraryTabController.index);
      });
    _refreshData();
    _initFirebaseMessaging();
  }

  void _initCamera() {
    if (cameras.isEmpty) return;
    _controller = CameraController(
      cameras[_cameraIndex], 
      ResolutionPreset.high, 
      enableAudio: true,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.jpeg : ImageFormatGroup.bgra8888,
    );

    _initializeControllerFuture = _controller.initialize().then((_) async {
      await _controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      _minExposure = await _controller.getMinExposureOffset();
      _maxExposure = await _controller.getMaxExposureOffset();
      
      if (mounted) {
        setState(() {});
        Future.delayed(const Duration(milliseconds: 500), _checkAndStartTutorial);
      }
    }).catchError((e) {
      debugPrint("카메라 초기화 실패: $e");
    });
  }

  Future<void> _initFirebaseMessaging() async {
    if (kIsWeb) return;
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
    final prefs = await SharedPreferences.getInstance();
    final asked = prefs.getBool('notification_permission_requested') ?? false;
    if (asked) return;
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

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notification_permission_requested', true);

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
          _isInAlbumDetail = true;
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
                  Text("클립을 '꾹' 누르면 선택 모드가 시작됩니다.\n2개 이상 선택하여 Vlog를 만들어보세요!", style: TextStyle(color: Colors.white, fontSize: 16)),
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
    if (_isInAlbumDetail) await _loadClipsFromCurrentAlbum();
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
    _recordingTimer?.cancel();
    _exposureTimer?.cancel();
    _controller.dispose();
    _focusAnimController.dispose();
    _libraryTabController.dispose();
    super.dispose();
  }

  void hapticFeedback() => HapticFeedback.lightImpact();

  Future<void> _toggleCamera() async {
    if (cameras.length < 2) return;
    _cameraIndex = (_cameraIndex == 0) ? 1 : 0;
    await _controller.dispose();
    setState(() {
      _initCamera();
      _exposureOffset = 0.0;
    });
    hapticFeedback();
  }

  // --- [외부 미디어 가져오기] ---

  Future<void> _pickMedia() async {
    final XFile? media = await _picker.pickMedia();
    if (media == null) return;

    final isVideo = media.path.toLowerCase().endsWith('.mp4') || 
                    media.path.toLowerCase().endsWith('.mov') || 
                    media.path.toLowerCase().endsWith('.avi');

    if (isVideo) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoEditScreen(
            videoFile: File(media.path),
            targetAlbum: videoManager.currentAlbum,
          ),
        ),
      );

      if (result == true) {
        await _loadClipsFromCurrentAlbum();
        Fluttertoast.showToast(msg: "저장 완료");
      }
    } else {
      setState(() => _isConverting = true);
      try {
        await videoManager.convertPhotoToVideo(media.path, videoManager.currentAlbum);
        Fluttertoast.showToast(msg: "변환 완료");
        await _loadClipsFromCurrentAlbum();
      } catch (e) {
        Fluttertoast.showToast(msg: "변환 실패: $e");
      } finally {
        if (mounted) setState(() => _isConverting = false);
      }
    }
  }

  // --- [Vlog 병합: Native Engine 적용] ---

  Future<void> _handleMerge() async {
    if (videoManager.currentAlbum == "휴지통") {
      Fluttertoast.showToast(msg: "휴지통의 영상으로는 Vlog를 만들 수 없습니다.");
      return;
    }
    if (_selectedClipPaths.length < 2) return;

    final userStatusManager = UserStatusManager();
    final currentTier = userStatusManager.currentTier;
    
    // 고화질(1080p) 병합 시 프리미엄 체크
    if (!userStatusManager.isStandardOrAbove()) {
      bool? goPaywall = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Premium 기능'),
          content: const Text('고화질(1080p) 저장과 워터마크 제거는 Premium 전용 기능입니다. 지금 확인해보시겠어요?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('나중에')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Premium 보기')),
          ],
        ),
      );

      if (goPaywall == true) {
        if (mounted) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const PaywallScreen()));
        }
        return;
      }
      
      // 결제 안 하고 진행하면 저화질로 강제 변경하거나 워터마크 강제 포함 (현재는 로직상 워터마크만 강제)
    }

    final bool forceWatermark = currentTier == UserTier.free;
    final String watermarkText = forceWatermark ? 'Made with 3s' : '';

    // 1. 심플한 로딩 다이얼로그 (불필요한 텍스트 제거)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Center(
          child: Container(
            width: 220,
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 45, height: 45,
                  child: CircularProgressIndicator(strokeWidth: 5, color: Colors.blueAccent),
                ),
                const SizedBox(height: 24),
                const Text("Vlog 생성 중", 
                  style: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.w700, decoration: TextDecoration.none)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final String outputPath = p.join(docDir.path, 'exports', "vlog_${DateTime.now().millisecondsSinceEpoch}.mp4");
      
      final exportDir = Directory(p.join(docDir.path, 'exports'));
      if (!await exportDir.exists()) await exportDir.create(recursive: true);

      // 💡 네이티브 병합 호출 (4K + 자막 + GPU 필터 + 오디오 믹싱)
      final String result = await platform.invokeMethod('mergeVideos', {
        'paths': _selectedClipPaths,
        'outputPath': outputPath,
        'forceWatermark': forceWatermark,
        'quality': userStatusManager.currentTier == UserTier.premium ? '4K' : '1080p',
        'userTier': userStatusManager.currentTier.toString().split('.').last,
        
        // 📝 자막 파라미터 (멀티 오버레이)
        'subtitles': [
          // 예시: 중앙 상단 제목
          // {
          //   'text': '내 첫 번째 Vlog',
          //   'x': 0.0,    // -1.0 (왼쪽) ~ 1.0 (오른쪽), 0.0 = 중앙
          //   'y': -0.8,   // -1.0 (상단) ~ 1.0 (하단), -0.8 = 상단
          //   'size': 1.5, // 1.0 = 기본 크기
          //   'color': '#FFFFFF',
          // },
        ],
        
        // 🎨 비디오 이펙트 (Premium 전용)
        'videoEffects': {
          // 'contrast': 1.2,      // 대비 (0.0~2.0, 1.0=기본)
          // 'saturation': 1.3,    // 채도 (0.0~2.0, 1.0=기본, 0.0=흑백)
          // 'grayscale': false,   // 흑백 필터
        },
        
        // 🎵 오디오 믹싱 파라미터 (선택적)
        // 'bgmPath': '/path/to/bgm.mp3',
        // 'forceMuteOriginal': false,
        // 'enableNoiseSuppression': true,
        // 'bgmVolume': 0.5,
      });

      // 💡 [중요] 여기서 딱 한 번만 팝하여 로딩창을 닫습니다.
      if (mounted) Navigator.pop(context);

      if (result == "SUCCESS") {
        final savedPath = await videoManager.saveMergedProject(outputPath);
        await Gal.putVideo(savedPath);
        await File(outputPath).delete().catchError((_) {});

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ResultPreviewWidget(
                videoPath: savedPath,
                onShare: () => Share.shareXFiles([XFile(savedPath)], text: 'Made with 3S Vlog'),
                onEdit: () => _handleEditRequest(savedPath),
              ),
            ),
          );

          await _refreshData();
          setState(() {
            _isClipSelectionMode = false;
            _selectedClipPaths.clear();
          });
        }
      } else {
        throw Exception("Native Error: $result");
      }

    } catch (e) {
      if (mounted) Navigator.pop(context); // 에러 발생 시에도 로딩창은 닫아야 함
      Fluttertoast.showToast(msg: "오류 발생: $e");
    }
  }

  // --- [편집 요청 핸들러] ---

  /// 편집 요청 처리 (구매 트리거 포함)
  Future<void> _handleEditRequest(String videoPath) async {
    final userStatusManager = UserStatusManager();
    
    // Standard 등급 이상만 편집 가능
    if (!userStatusManager.isStandardOrAbove()) {
      // Free 유저 → 구매 유도 팝업
      final bool? goPaywall = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('편집 기능 잠금'),
          content: const Text(
            '편집 기능은 Standard 등급부터 사용 가능합니다.\n\n'
            '지금 업그레이드하고 더 멋진 Vlog를 만들어보세요!',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('나중에'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
              ),
              child: const Text('업그레이드'),
            ),
          ],
        ),
      );

      if (goPaywall == true && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const PaywallScreen()),
        );
      }
      return;
    }

    // Standard 이상 → VideoEditScreen으로 이동
    if (mounted) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoEditScreen(
            videoFile: File(videoPath),
            targetAlbum: videoManager.currentAlbum,
          ),
        ),
      );

      if (result == true) {
        Fluttertoast.showToast(msg: "편집 완료");
        await _refreshData();
      }
    }
  }

  // --- [액션 핸들러] ---

  Future<void> _handleClipBatchDelete() async {
    bool isTrash = videoManager.currentAlbum == "휴지통";
    if (isTrash) {
      bool? ok = await _showConfirmDialog("영구 삭제", "선택한 클립을 모두 삭제할까요?");
      if (ok != true) return;
      for (var path in _selectedClipPaths) await File(path).delete();
    } else {
      await videoManager.deleteClipsBatch(_selectedClipPaths);
    }
    await _loadClipsFromCurrentAlbum();
    setState(() { _isClipSelectionMode = false; _selectedClipPaths.clear(); });
    hapticFeedback();
  }

  Future<void> _handleRestore(String path) async { await videoManager.restoreClip(path); await _loadClipsFromCurrentAlbum(); hapticFeedback(); }

  Future<void> _handleSafeSingleDelete(String path) async {
    bool isTrash = videoManager.currentAlbum == "휴지통";
    if (isTrash) {
      bool? ok = await _showConfirmDialog("영구 삭제", "복구할 수 없습니다. 삭제할까요?");
      if (ok != true) return;
      await File(path).delete();
    } else { await videoManager.moveToTrash(path); }
    await _loadClipsFromCurrentAlbum();
    setState(() => _previewingPath = null);
    hapticFeedback();
  }

  Future<void> _handleAlbumBatchDelete() async {
    bool? ok = await _showConfirmDialog("앨범 삭제", "앨범은 삭제되고 클립은 휴지통으로 이동합니다.");
    if (ok == true) { await videoManager.deleteAlbums(_selectedAlbumNames); setState(() { _isAlbumSelectionMode = false; _selectedAlbumNames.clear(); }); await videoManager.initAlbumSystem(); if (mounted) setState(() {}); }
  }

  Future<void> _handleMoveOrCopy(bool isMove) async {
    final snapshot = List<String>.from(_selectedClipPaths);
    
    final String? result = await showDialog<String>(
      context: context, 
      builder: (c) => AlertDialog(
        title: Text(isMove ? "이동" : "복사"), 
        content: Column(
          mainAxisSize: MainAxisSize.min, 
          children: [
            ListTile(
              leading: const Icon(Icons.add_circle, color: Colors.blueAccent), 
              title: const Text("새 앨범 만들기"), 
              onTap: () => Navigator.pop(c, "NEW")
            ), 
            const Divider(), 
            ...videoManager.albums
                .where((a) => a != videoManager.currentAlbum && a != "휴지통" && a != "Vlog")
                .map((a) => ListTile(title: Text(a), onTap: () => Navigator.pop(c, a)))
          ]
        )
      )
    );

    if (result == null) return;

    String targetAlbum = result;

    if (result == "NEW") {
      String? name = await _showCreateAlbumDialog();
      if (name == null || name.trim().isEmpty) return;
      targetAlbum = name.trim();
      await videoManager.createNewAlbum(targetAlbum);
    }

    await videoManager.executeTransfer(targetAlbum, isMove, snapshot);
    await _loadClipsFromCurrentAlbum();

    setState(() {
      _isClipSelectionMode = false; 
      _selectedClipPaths.clear();    
    });

    Fluttertoast.showToast(msg: isMove ? "이동 완료" : "복사 완료");
    hapticFeedback(); 
  }

  // --- [인터랙션 로직: 드래그 & 줌] ---

  void _startDragSelection(Offset position, bool isClip) {
    final rb = (isClip ? _clipGridKey : _albumGridKey).currentContext?.findRenderObject() as RenderBox?;
    if (rb == null) return;
    final lp = rb.globalToLocal(position);
    final double size = rb.size.width / _gridColumnCount;
    final int idx = ((lp.dy / size).floor() * _gridColumnCount) + (lp.dx / size).floor();
    final int max = isClip ? videoManager.recordedVideoPaths.length : videoManager.albums.length;
    if (idx >= 0 && idx < max) {
      final String item = isClip ? videoManager.recordedVideoPaths[idx] : videoManager.albums[idx];
      _lastProcessedIndex = idx;
      _isDragAdding = isClip ? !_selectedClipPaths.contains(item) : !_selectedAlbumNames.contains(item);
      setState(() {
        if (isClip) { if (_isDragAdding) _selectedClipPaths.add(item); else _selectedClipPaths.remove(item); }
        else { if (item != "일상" && item != "휴지통") { if (_isDragAdding) _selectedAlbumNames.add(item); else _selectedAlbumNames.remove(item); } }
      });
      HapticFeedback.selectionClick();
    }
  }

  void _handleScaleUpdate(ScaleUpdateDetails d, bool isClip) {
    if (d.pointerCount > 1) {
      if (_isZoomingLocked) return;
      double sensitivity = 0.07; 
      double scaleDiff = d.scale - 1.0; 

      if (scaleDiff.abs() > sensitivity) {
        setState(() {
          if (scaleDiff > 0) { 
            if (_gridColumnCount == 5) _gridColumnCount = 3;
            else if (_gridColumnCount == 3) _gridColumnCount = 2;
          } else {
            if (_gridColumnCount == 2) _gridColumnCount = 3;
            else if (_gridColumnCount == 3) _gridColumnCount = 5;
          }
          _isZoomingLocked = true;
          HapticFeedback.mediumImpact(); 
        });
      }
    } else {
      final active = isClip ? _isClipSelectionMode : _isAlbumSelectionMode;
      if (!active) return;
      final rb = (isClip ? _clipGridKey : _albumGridKey).currentContext?.findRenderObject() as RenderBox?;
      if (rb == null) return;
      final lp = rb.globalToLocal(d.focalPoint);
      final double size = rb.size.width / _gridColumnCount;
      final int idx = ((lp.dy / size).floor() * _gridColumnCount) + (lp.dx / size).floor();
      final int max = isClip ? videoManager.recordedVideoPaths.length : videoManager.albums.length;
      if (idx >= 0 && idx < max && idx != _lastProcessedIndex) {
        _lastProcessedIndex = idx;
        final String item = isClip ? videoManager.recordedVideoPaths[idx] : videoManager.albums[idx];
        setState(() {
          if (isClip) { if (_isDragAdding) _selectedClipPaths.add(item); else _selectedClipPaths.remove(item); }
          else { if (item != "일상" && item != "휴지통") { if (_isDragAdding) _selectedAlbumNames.add(item); else _selectedAlbumNames.remove(item); } }
        });
        HapticFeedback.selectionClick();
      }
    }
  }

  Future<void> _handleFocus(TapDownDetails d, BoxConstraints c) async {
    if (d.localPosition.dy > c.maxHeight - 150) return;
    setState(() { _tapPosition = d.localPosition; _showExposureSlider = true; });
    _focusAnimController.forward(from: 0.0);
    try {
      final point = Offset(d.localPosition.dx / c.maxWidth, d.localPosition.dy / c.maxHeight);
      await _controller.setFocusPoint(point); await _controller.setExposurePoint(point);
    } catch (_) {}
    _startExposureTimer();
  }

  void _startExposureTimer() {
    _exposureTimer?.cancel();
    _exposureTimer = Timer(const Duration(seconds: 2), () { if (mounted) setState(() { _showExposureSlider = false; _tapPosition = null; }); });
  }

  Future<void> _startRecording() async {
    try {
      await _controller.setExposureMode(ExposureMode.locked);
      await _controller.startVideoRecording();
      setState(() { _isRecording = true; _remainingTime = 3; });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_remainingTime > 1 && mounted) setState(() => _remainingTime--); else if (mounted) { _stopRecording(); timer.cancel(); }
      });
    } catch (e) {
      debugPrint("녹화 시작 실패: $e");
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    _recordingTimer?.cancel();
    try {
      final video = await _controller.stopVideoRecording();
      await _controller.setExposureMode(ExposureMode.auto);
      await videoManager.saveRecordedVideo(video);
    } catch (e) {
      debugPrint("녹화 종료 실패: $e");
    } finally {
      if (mounted) setState(() { _isRecording = false; _remainingTime = 3; });
    }
  }

  // --- [UI 빌더] ---

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (_previewingPath != null) setState(() => _previewingPath = null);
        else if (_isClipSelectionMode) setState(() { _isClipSelectionMode = false; _selectedClipPaths.clear(); });
        else if (_isAlbumSelectionMode) setState(() { _isAlbumSelectionMode = false; _selectedAlbumNames.clear(); });
        else if (_isInAlbumDetail) setState(() => _isInAlbumDetail = false);
      },
      child: Scaffold(
        body: Stack(
          children: [
            IndexedStack(index: _selectedIndex, children: [_buildCaptureTab(), _buildLibraryMain()]),
            if (_isConverting) 
              Container(
                color: Colors.black.withOpacity(0.5),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        LinearProgressIndicator(color: Colors.blueAccent),
                        SizedBox(height: 20),
                        Text("영상 변환 중...", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          key: keyLibraryTab,
          currentIndex: _selectedIndex,
          onTap: (i) { setState(() { _selectedIndex = i; if (i == 0 && videoManager.currentAlbum == "휴지통") videoManager.currentAlbum = "일상"; if (i == 1) _refreshData(); }); },
          items: const [BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: "촬영"), BottomNavigationBarItem(icon: Icon(Icons.photo_library), label: "라이브러리")],
        ),
      ),
    );
  }

  Widget _buildCaptureTab() {
    if (!_controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        onTapDown: (d) => _handleFocus(d, constraints),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxWidth * _controller.value.aspectRatio,
                  child: CameraPreview(_controller),
                ),
              ),
            ),
            if (_tapPosition != null) Positioned(left: _tapPosition!.dx - 35, top: _tapPosition!.dy - 35, child: AnimatedBuilder(animation: _focusAnimController, builder: (context, child) => Container(width: 70, height: 70, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.yellow, width: 2))))),
            if (_showExposureSlider && _tapPosition != null)
              Positioned(left: _tapPosition!.dx + 45, top: _tapPosition!.dy - 60, child: SizedBox(height: 120, child: RotatedBox(quarterTurns: 3, child: SliderTheme(data: SliderTheme.of(context).copyWith(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6), overlayShape: const RoundSliderOverlayShape(overlayRadius: 14), activeTrackColor: Colors.yellow, inactiveTrackColor: Colors.white30, thumbColor: Colors.yellow), child: Slider(value: _exposureOffset, min: _minExposure, max: _maxExposure, onChanged: (v) async { setState(() => _exposureOffset = v); await _controller.setExposureOffset(v); _startExposureTimer(); }))))),
            Positioned(top: 55, left: 20, child: _buildAlbumDropdown()),
            Positioned(
              bottom: 70, left: 0, right: 0,
              child: Column(
                children: [
                  if (_isRecording) _buildRecordingTimer(),
                  SizedBox(
                    width: constraints.maxWidth,
                    height: 85,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        GestureDetector(
                          onTap: () {
                            hapticFeedback(); 
                            _isRecording ? _stopRecording() : _startRecording();
                          },
                          child: _buildRecordButton(),
                        ),
                        if (!_isRecording && cameras.length > 1)
                          Positioned(
                            right: constraints.maxWidth * 0.15,
                            child: IconButton(
                              icon: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 32),
                              onPressed: _toggleCamera,
                            ),
                          )
                      ],
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryMain() {
    if (_isInAlbumDetail) return _buildDetailView();

    final bool isClipTab = _libraryTabIndex == 0;
    final selectableAlbums = videoManager.albums.where((a) => a != "일상" && a != "휴지통" && a != "Vlog").toList();
    final bool isAll = _selectedAlbumNames.length == selectableAlbums.length && _selectedAlbumNames.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: isClipTab
            ? (_isAlbumSelectionMode
                ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() { _isAlbumSelectionMode = false; _selectedAlbumNames.clear(); }))
                : null)
            : null,
        title: Text(isClipTab ? (_isAlbumSelectionMode ? "${_selectedAlbumNames.length}개 선택" : "앨범") : "브이로그"),
        actions: isClipTab
            ? [
                if (!_isAlbumSelectionMode)
                  IconButton(
                    icon: const Icon(Icons.stars, color: Colors.amber),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PaywallScreen())),
                  ),
                if (_isAlbumSelectionMode)
                  IconButton(
                    icon: Icon(isAll ? Icons.check_box : Icons.check_box_outline_blank),
                    onPressed: () => _toggleSelectAll(false),
                  )
                else
                  IconButton(icon: const Icon(Icons.add, size: 28), onPressed: _showCreateAlbumMain),
              ]
            : [],
        bottom: TabBar(
          controller: _libraryTabController,
          indicatorColor: Colors.blueAccent,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black54,
          unselectedLabelStyle: const TextStyle(fontSize: 14),
          tabs: const [
            Tab(text: "클립"),
            Tab(text: "브이로그"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _libraryTabController,
        children: [
          _buildClipTabContent(),
          _buildVlogTabContent(),
        ],
      ),
      floatingActionButton: isClipTab && _isAlbumSelectionMode && _selectedAlbumNames.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _handleAlbumBatchDelete,
              backgroundColor: Colors.redAccent,
              icon: const Icon(Icons.delete),
              label: const Text("삭제"),
            )
          : null,
    );
  }

  Widget _buildDetailView() {
    const double headerHeight = 60.0;
    return Row(
      children: [
        AnimatedContainer(duration: const Duration(milliseconds: 250), width: _isSidebarOpen ? _narrowSidebarWidth : 0, color: const Color(0xFFFBFBFC), child: _buildNarrowSidebar(headerHeight)),
        Expanded(
          child: Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.white, elevation: 0, scrolledUnderElevation: 0, toolbarHeight: headerHeight,
              leading: _isClipSelectionMode 
                  ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() { _isClipSelectionMode = false; _selectedClipPaths.clear(); })) 
                  : IconButton(icon: const Icon(Icons.menu_open), onPressed: () => setState(() => _isSidebarOpen = !_isSidebarOpen)),
              title: Text(_isClipSelectionMode ? "${_selectedClipPaths.length}개 선택" : "${videoManager.currentAlbum} (${videoManager.recordedVideoPaths.length})"),
              actions: [
                if (!_isClipSelectionMode)
                  IconButton(
                    icon: const Icon(Icons.stars, color: Colors.amber), 
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PaywallScreen()))
                  ),
                if (_isClipSelectionMode)
                  (videoManager.currentAlbum == "휴지통" || videoManager.currentAlbum == "Vlog"
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(right: 12.0),
                          child: ElevatedButton.icon(
                            onPressed: _selectedClipPaths.length >= 2 ? _handleMerge : null,
                            icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                            label: const Text('Vlog 생성',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueAccent,
                                disabledBackgroundColor: Colors.grey[300],
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                elevation: 0),
                          ),
                        ))
                else ...[
                  if (videoManager.currentAlbum != "Vlog" && videoManager.currentAlbum != "휴지통")
                    IconButton(
                      key: keyPickMedia, 
                      icon: const Icon(Icons.add_photo_alternate_outlined), 
                      onPressed: _pickMedia
                    ),
                ]
              ],
            ),
            body: Column(
              children: [
                const Divider(height: 1, thickness: 1, color: Colors.black12),
                Expanded(
                  child: GestureDetector(
                    onScaleStart: (d) { _isZoomingLocked = false; if (_isClipSelectionMode && d.pointerCount == 1) _startDragSelection(d.focalPoint, true); },
                    onScaleUpdate: (d) => _handleScaleUpdate(d, true),
                    child: Stack(
                      children: [
                        if (videoManager.recordedVideoPaths.isEmpty)
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  key: keyFirstClip,
                                  width: 100, height: 100,
                                  decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)),
                                  child: const Icon(Icons.movie_creation, color: Colors.grey, size: 40),
                                ),
                                const SizedBox(height: 16),
                                const Text("영상이 없습니다.\n촬영하거나 가져와보세요!", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))
                              ],
                            ),
                          )
                        else
                          GridView.builder(
                            key: _clipGridKey, padding: const EdgeInsets.all(2),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: _gridColumnCount, crossAxisSpacing: 2, mainAxisSpacing: 2),
                            itemCount: videoManager.recordedVideoPaths.length,
                            itemBuilder: (context, index) {
                              final path = videoManager.recordedVideoPaths[index];
                              final isS = _selectedClipPaths.contains(path);
                              final int selectIdx = _selectedClipPaths.indexOf(path);
                              final bool isFirst = index == 0;

                              return GestureDetector(
                                onLongPress: () { setState(() { _isClipSelectionMode = true; _lastProcessedIndex = index; _isDragAdding = !isS; if (_isDragAdding) _selectedClipPaths.add(path); else _selectedClipPaths.remove(path); }); hapticFeedback(); },
                                onTap: () { if (_isClipSelectionMode) setState(() { if (isS) _selectedClipPaths.remove(path); else _selectedClipPaths.add(path); }); else setState(() => _previewingPath = path); },
                                child: Container(
                                  key: isFirst ? keyFirstClip : null,
                                  child: Stack(fit: StackFit.expand, children: [
                                    _buildThumbnailWidget(path),
                                    if (videoManager.favorites.contains(path)) Positioned(bottom: 4, left: 4, child: const Icon(Icons.favorite, color: Colors.white, size: 16)),
                                    if (isS) Container(color: Colors.white54),
                                    if (_isClipSelectionMode && isS) Positioned(bottom: 6, right: 6, child: Container(width: 24, height: 24, decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle), alignment: Alignment.center, child: Text('${selectIdx + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))))
                                    else if (_isClipSelectionMode) const Positioned(bottom: 4, right: 4, child: Icon(Icons.radio_button_unchecked, color: Colors.white70, size: 24)),
                                  ]),
                                ),
                              );
                            },
                          ),
                        if (_previewingPath != null) VideoPreviewWidget(filePath: _previewingPath!, favorites: videoManager.favorites, isTrashMode: videoManager.currentAlbum == "휴지통", onToggleFav: (p) => setState(() { if (videoManager.favorites.contains(p)) videoManager.favorites.remove(p); else videoManager.favorites.add(p); }), onRestore: (p) => _handleRestore(p), onDelete: (p) => _handleSafeSingleDelete(p), onClose: () => setState(() => _previewingPath = null)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            floatingActionButton: (_isClipSelectionMode && _selectedClipPaths.isNotEmpty) ? _buildExtendedActionPanel() : null,
            floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
          ),
        ),
      ],
    );
  }

  Widget _buildClipTabContent() {
    return GestureDetector(
      onScaleStart: (d) {
        _isZoomingLocked = false;
        if (_isAlbumSelectionMode && d.pointerCount == 1) _startDragSelection(d.focalPoint, false);
      },
      onScaleUpdate: (d) => _handleScaleUpdate(d, false),
      child: Stack(
        children: [
          if (videoManager.recordedVideoPaths.isEmpty)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    key: keyFirstClip,
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.movie_creation, color: Colors.grey, size: 40),
                  ),
                  const SizedBox(height: 16),
                  const Text("영상이 없습니다.\n촬영하거나 가져와보세요!", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))
                ],
              ),
            )
          else
            GridView.builder(
              key: _clipGridKey,
              padding: const EdgeInsets.all(2),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _gridColumnCount,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
              ),
              itemCount: videoManager.recordedVideoPaths.length,
              itemBuilder: (context, index) {
                final path = videoManager.recordedVideoPaths[index];
                final isSelected = _selectedClipPaths.contains(path);
                final selectIndex = _selectedClipPaths.indexOf(path);
                final bool isFirst = index == 0;

                return GestureDetector(
                  onLongPress: () {
                    setState(() {
                      _isClipSelectionMode = true;
                      _lastProcessedIndex = index;
                      _isDragAdding = !isSelected;
                      if (_isDragAdding) _selectedClipPaths.add(path);
                      else _selectedClipPaths.remove(path);
                    });
                    hapticFeedback();
                  },
                  onTap: () {
                    if (_isClipSelectionMode) {
                      setState(() {
                        isSelected ? _selectedClipPaths.remove(path) : _selectedClipPaths.add(path);
                      });
                    } else {
                      setState(() => _previewingPath = path);
                    }
                  },
                  child: Container(
                    key: isFirst ? keyFirstClip : null,
                    child: Stack(fit: StackFit.expand, children: [
                      _buildThumbnailWidget(path),
                      if (videoManager.favorites.contains(path))
                        Positioned(bottom: 4, left: 4, child: const Icon(Icons.favorite, color: Colors.white, size: 16)),
                        if (videoManager.isClipCloudSynced(path))
                          Positioned(top: 6, right: 6, child: Icon(Icons.cloud_done, color: Colors.white.withOpacity(0.9), size: 20)),
                      if (isSelected) Container(color: Colors.white54),
                      if (_isClipSelectionMode && isSelected)
                        Positioned(
                          bottom: 6,
                          right: 6,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle),
                            alignment: Alignment.center,
                            child: Text('${selectIndex + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        )
                      else if (_isClipSelectionMode)
                        const Positioned(bottom: 4, right: 4, child: Icon(Icons.radio_button_unchecked, color: Colors.white70, size: 24)),
                    ]),
                  ),
                );
              },
            ),
          if (_previewingPath != null)
            VideoPreviewWidget(
              filePath: _previewingPath!,
              favorites: videoManager.favorites,
              isTrashMode: videoManager.currentAlbum == "휴지통",
              onToggleFav: (p) => setState(() {
                if (videoManager.favorites.contains(p))
                  videoManager.favorites.remove(p);
                else
                  videoManager.favorites.add(p);
              }),
              onRestore: (p) => _handleRestore(p),
              onDelete: (p) => _handleSafeSingleDelete(p),
              onClose: () => setState(() => _previewingPath = null),
            ),
        ],
      ),
    );
  }

  Widget _buildVlogTabContent() {
    final projects = videoManager.vlogProjectPaths;
    if (projects.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.stars, size: 60, color: Colors.grey),
            SizedBox(height: 12),
            Text("브이로그가 아직 없습니다.", style: TextStyle(color: Colors.grey, fontSize: 16)),
            SizedBox(height: 4),
            Text("클립을 선택해 하나의 스토리로 완성해보세요.", style: TextStyle(color: Colors.grey, fontSize: 14)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: GridView.builder(
        key: const ValueKey("vlog_grid"),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _gridColumnCount,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: projects.length,
        itemBuilder: (context, index) {
          final path = projects[index];
          return GestureDetector(
            onTap: () => _openVlogPreview(path),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildThumbnailWidget(path),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Icon(Icons.cloud_done, color: Colors.white.withOpacity(0.9), size: 22),
                      ),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                        stops: [0.5, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    bottom: 12,
                    right: 12,
                    child: Text(
                      "브이로그 ${index + 1}",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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

  void _openVlogPreview(String path) {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ResultPreviewWidget(
          videoPath: path,
          onShare: () => Share.shareXFiles([XFile(path)], text: 'Made with 3S Vlog'),
          onEdit: () => _handleEditRequest(path),
        ),
      ),
    );
  }

  Widget _buildExtendedActionPanel() {
    bool isTrash = videoManager.currentAlbum == "휴지통";
    bool isVlog = videoManager.currentAlbum == "Vlog";
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(blurRadius: 25, color: Colors.black.withOpacity(0.1), offset: const Offset(0, 5))]
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: isTrash
            ? [
                _buildSimpleAction(Icons.settings_backup_restore, Colors.blueAccent, () async {
                  for (var p in _selectedClipPaths) await videoManager.restoreClip(p);
                  await _loadClipsFromCurrentAlbum();
                  setState(() => _isClipSelectionMode = false);
                  hapticFeedback();
                }),
                _buildSimpleAction(Icons.delete_forever, Colors.redAccent, _handleClipBatchDelete),
              ]
            : [
                _buildSimpleAction(Icons.favorite, Colors.pinkAccent, () {
                  videoManager.toggleFavoritesBatch(_selectedClipPaths);
                  setState(() { _isClipSelectionMode = false; _selectedClipPaths.clear(); });
                  hapticFeedback();
                }),
                if (!isVlog) ...[
                  _buildSimpleAction(Icons.drive_file_move, Colors.blue, () => _handleMoveOrCopy(true)),
                  _buildSimpleAction(Icons.content_copy, Colors.teal, () => _handleMoveOrCopy(false)),
                ],
                _buildSimpleAction(Icons.delete, Colors.redAccent, _handleClipBatchDelete),
              ],
      ),
    );
  }

  Widget _buildSimpleAction(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Icon(icon, color: color, size: 28),
      ),
    );
  }

  void _toggleSelectAll(bool isClip) { setState(() { if (isClip) { if (_selectedClipPaths.length == videoManager.recordedVideoPaths.length) _selectedClipPaths.clear(); else _selectedClipPaths = List.from(videoManager.recordedVideoPaths); } else { final selectable = videoManager.albums.where((a) => a != "일상" && a != "휴지통").toList(); if (_selectedAlbumNames.length == selectable.length) _selectedAlbumNames.clear(); else _selectedAlbumNames = Set.from(selectable); } }); hapticFeedback(); }
  void _showCreateAlbumMain() async { String? name = await _showCreateAlbumDialog(); if (name != null && name.trim().isNotEmpty) { if (videoManager.albums.contains(name.trim())) return; await videoManager.createNewAlbum(name.trim()); _refreshData(); } }
  Future<String?> _showCreateAlbumDialog() async { String input = ""; return showDialog<String>(context: context, builder: (c) => AlertDialog(title: const Text("새 앨범"), content: TextField(onChanged: (v) => input = v, autofocus: true, maxLength: 12), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("취소")), TextButton(onPressed: () => Navigator.pop(c, input), child: const Text("확정"))])); }
  Widget _buildAlbumDropdown() { return ClipRRect(borderRadius: BorderRadius.circular(20), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: Container(height: 42, padding: const EdgeInsets.symmetric(horizontal: 14), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)), child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: videoManager.albums.contains(videoManager.currentAlbum) && videoManager.currentAlbum != "휴지통" ? videoManager.currentAlbum : "일상", icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white), dropdownColor: Colors.black.withOpacity(0.8), onChanged: (v) { setState(() => videoManager.currentAlbum = v!); hapticFeedback(); }, items: videoManager.albums.where((a) => a != "휴지통").map((a) => DropdownMenuItem(value: a, child: Text(a, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)))).toList()))))); }
  Widget _buildRecordingTimer() { return Container(margin: const EdgeInsets.only(bottom: 20), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)), child: Text('0:0$_remainingTime', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))); }
  Widget _buildRecordButton() { return Stack(alignment: Alignment.center, children: [Container(key: keyRecordButton, height: 85, width: 85, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4))), AnimatedContainer(duration: const Duration(milliseconds: 200), height: _isRecording ? 35 : 70, width: _isRecording ? 35 : 70, decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(_isRecording ? 8 : 40)))]); }
  
  Widget _buildNarrowSidebar(double headerHeight) { 
    return SafeArea(
      child: Column(children: [
        SizedBox(height: headerHeight, child: Center(child: IconButton(icon: const Icon(Icons.grid_view_rounded, size: 22), onPressed: () => setState(() => _isInAlbumDetail = false)))), 
        const Divider(height: 1, thickness: 1, color: Colors.black12), 
        Expanded(
          child: ListView.builder(
            itemCount: videoManager.albums.length, 
            itemBuilder: (context, index) { 
              final name = videoManager.albums[index]; 
              bool isS = videoManager.currentAlbum == name; 
              return GestureDetector(
                onTap: () async { 
                  if (videoManager.currentAlbum == name) return; 
                  
                  // 💡 [핵심] 폴더 이동 시 다중 선택 모드를 강제로 해제하여 데이터 오염 방지
                  if (_isClipSelectionMode) {
                    setState(() {
                      _isClipSelectionMode = false;
                      _selectedClipPaths.clear();
                    });
                  }
                  setState(() { videoManager.recordedVideoPaths = []; });
                  videoManager.currentAlbum = name;
                  await videoManager.loadClipsFromCurrentAlbum(); 
                  if (mounted) { hapticFeedback(); setState(() {}); }
                }, 
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8), 
                  child: Column(children: [
                    Icon(name == "휴지통" ? Icons.delete_outline : Icons.folder_rounded, 
                    color: isS ? Colors.blueAccent : Colors.black26, size: 26), 
                    const SizedBox(height: 2), 
                    Text(name, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, 
                    style: const TextStyle(fontSize: 9))
                  ])
                )
              ); 
            }
          )
        ), 
      ])
    ); 
  }
  Widget _buildAlbumThumbnail(String name) { return FutureBuilder<String?>(future: videoManager.getFirstClipPath(name), builder: (c, s) => s.hasData && s.data != null ? _buildThumbnailWidget(s.data!) : Container(color: Colors.grey[100], child: const Center(child: Icon(Icons.folder_open, color: Colors.black12, size: 40)))); }
  Widget _buildThumbnailWidget(String p) { return FutureBuilder<Uint8List?>(future: videoManager.getThumbnail(p), builder: (c, s) => s.hasData ? Image.memory(s.data!, fit: BoxFit.cover) : Container(color: Colors.grey[100])); }
  Future<bool?> _showConfirmDialog(String title, String content) { return showDialog<bool>(context: context, builder: (c) => AlertDialog(title: Text(title), content: Text(content), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("취소")), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("확인", style: TextStyle(color: Colors.red)))])); }
}

class VideoPreviewWidget extends StatefulWidget {
  final String filePath; final Set<String> favorites; final bool isTrashMode;
  final Function(String) onToggleFav; final Function(String) onRestore; final Function(String) onDelete; final VoidCallback onClose;
  const VideoPreviewWidget({super.key, required this.filePath, required this.favorites, required this.isTrashMode, required this.onToggleFav, required this.onRestore, required this.onDelete, required this.onClose});
  @override State<VideoPreviewWidget> createState() => _VideoPreviewWidgetState();
}

class _VideoPreviewWidgetState extends State<VideoPreviewWidget> {
  late VideoPlayerController _vController;
  @override void initState() { super.initState(); _vController = VideoPlayerController.file(File(widget.filePath))..initialize().then((_) { if (mounted) setState(() {}); _vController.setLooping(true); _vController.play(); }); }
  @override void dispose() { _vController.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final isFav = widget.favorites.contains(widget.filePath);
    return GestureDetector(
      onTap: widget.onClose, 
      child: Positioned.fill(
        child: Container(
          color: Colors.black,
          child: Stack(
            children: [
              Center(
                child: _vController.value.isInitialized 
                    ? AspectRatio(aspectRatio: _vController.value.aspectRatio, child: VideoPlayer(_vController)) 
                    : const CircularProgressIndicator()
              ),
              Positioned(top: 40, left: 20, child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 30), onPressed: widget.onClose)),
              Positioned(
                bottom: 50, left: 0, right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: Icon(
                        widget.isTrashMode ? Icons.settings_backup_restore : (isFav ? Icons.favorite : Icons.favorite_border),
                        color: (isFav && !widget.isTrashMode) ? Colors.red : Colors.white, size: 30
                      ),
                      onPressed: () {
                        if (widget.isTrashMode) widget.onRestore(widget.filePath);
                        else { widget.onToggleFav(widget.filePath); setState(() {}); }
                      }
                    ),
                    IconButton(icon: const Icon(Icons.delete_outline, color: Colors.white, size: 30), onPressed: () => widget.onDelete(widget.filePath))
                  ]
                )
              )
            ]
          )
        )
      ),
    );
  }
}

class ResultPreviewWidget extends StatefulWidget {
  final String videoPath;
  final VoidCallback onShare;
  final VoidCallback onEdit;

  const ResultPreviewWidget({
    super.key, 
    required this.videoPath, 
    required this.onShare, 
    required this.onEdit
  });

  @override
  State<ResultPreviewWidget> createState() => _ResultPreviewWidgetState();
}

class _ResultPreviewWidgetState extends State<ResultPreviewWidget> {
  late VideoPlayerController _controller;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          _controller.play();
          _controller.setLooping(true);
        }
      });
    _controller.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${d.inMinutes}:${twoDigits(d.inSeconds.remainder(60))}";
  }

  @override
  Widget build(BuildContext context) {
    final duration = _controller.value.duration;
    final position = _controller.value.position;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: () => setState(() => _showControls = !_showControls),
              child: Center(
                child: _controller.value.isInitialized
                    ? AspectRatio(aspectRatio: _controller.value.aspectRatio, child: VideoPlayer(_controller))
                    : const CircularProgressIndicator(color: Colors.white24),
              ),
            ),
            if (_showControls) ...[
              Positioned(
                top: 20, right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.transparent, Colors.black87], begin: Alignment.topCenter, end: Alignment.bottomCenter)
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(_formatDuration(position), style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Expanded(
                            child: Slider(
                              value: position.inMilliseconds.toDouble().clamp(0, duration.inMilliseconds.toDouble()),
                              min: 0.0,
                              max: duration.inMilliseconds.toDouble(),
                              activeColor: Colors.redAccent,
                              onChanged: (v) => _controller.seekTo(Duration(milliseconds: v.toInt())),
                            ),
                          ),
                          Text(_formatDuration(duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildPremiumActionButton(Icons.share_rounded, "공유", widget.onShare),
                          _buildPremiumActionButton(Icons.auto_awesome, "편집", widget.onEdit),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 💡 [Ver 2.8.6] 세련된 화이트 액션 버튼 위젯
  Widget _buildPremiumActionButton(IconData icon, String label, VoidCallback onTap) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          onPressed: onTap,
          backgroundColor: Colors.white, // 💡 화이트 배경
          elevation: 0,
          child: Icon(icon, color: Colors.black87), // 💡 블랙 아이콘
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}