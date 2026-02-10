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
import 'screens/paywall_screen.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/capture_screen.dart';
import 'screens/library_screen.dart';
import 'screens/vlog_screen.dart';
import 'managers/video_manager.dart';
import 'screens/video_edit_screen.dart';
import 'screens/clip_extractor_screen.dart'; // ✅ 추가
import 'widgets/video_widgets.dart';
import 'utils/haptics.dart';

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

  final ImagePicker _picker = ImagePicker();

  // 튜토리얼용 GlobalKey
  final GlobalKey keyRecordButton = GlobalKey();
  final GlobalKey keyLibraryTab = GlobalKey();
  final GlobalKey keyAlbumGridItem = GlobalKey();
  final GlobalKey keyFirstClip = GlobalKey();
  final GlobalKey keyActionsArea = GlobalKey();
  final GlobalKey keyPickMedia = GlobalKey();

  bool _isConverting = false;
  bool _notificationPermissionRequested = false;

  @override
  void initState() {
    super.initState();
    _refreshData();
    _initFirebaseMessaging();
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
    super.dispose();
  }

  late VideoManager videoManager;

  @override
  Widget build(BuildContext context) {
    videoManager = Provider.of<VideoManager>(context);
    
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
                _buildVlogTab(),
                const ProfileScreen(),
              ],
            ),
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
          type: BottomNavigationBarType.fixed,
          currentIndex: _selectedIndex,
          selectedItemColor: Colors.blueAccent,
          unselectedItemColor: Colors.black54,
          onTap: (i) { setState(() { _selectedIndex = i; if (i == 0 && videoManager.currentAlbum == "휴지통") videoManager.currentAlbum = "일상"; if (i == 1) _refreshData(); }); },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: "촬영"),
            BottomNavigationBarItem(icon: Icon(Icons.folder), label: "라이브러리"),
            BottomNavigationBarItem(icon: Icon(Icons.video_library), label: "Vlog"),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: "프로필"),
          ],
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
        // Fluttertoast.showToast(msg: "저장 완료"); // 안쪽에서 토스트 띄움
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

  Future<void> _handleMerge(List<String> selectedPaths) async {
    if (videoManager.currentAlbum == "휴지통") {
      Fluttertoast.showToast(msg: "휴지통의 영상으로는 Vlog를 만들 수 없습니다.");
      return;
    }
    if (selectedPaths.length < 2) return;

    // Navigate to VideoEditScreen for editing & export
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoEditScreen(
          videoPaths: selectedPaths,
          targetAlbum: videoManager.currentAlbum,
        ),
      ),
    );

    if (result == true) {
      await _refreshData();
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
            videoPaths: [videoPath],
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

  /// ✅ 3. Vlog 탭 - VlogScreen으로 분리 완료
  Widget _buildVlogTab() {
    return VlogScreen(
      onRefresh: _refreshData,
      onEditRequest: _handleEditRequest,
    );
  }

  Widget _buildProfileTab() {
    return const ProfileScreen();
  }
}
