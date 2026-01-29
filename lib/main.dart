import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:path/path.dart' as p;
import 'package:video_thumbnail/video_thumbnail.dart' as thum;
import 'package:gal/gal.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
// 💡 FFmpeg: New Min GPL 버전 사용 (안정성 확보)
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 💡 외부 편집 화면 파일 임포트
import 'screens/video_edit_screen.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '3s 2.0.0',
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
      home: const MainNavigationScreen(),
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
  int _selectedIndex = 0;
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;

  final VideoManager videoManager = VideoManager();
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
  
  // 그리드 줌 설정 (2-3-5 단계)
  int _gridColumnCount = 3;
  bool _isZoomingLocked = false;
  double _lastScale = 1.0;
  
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
    _refreshData();
  }

  void _initCamera() {
    // 💡 수정: ResolutionPreset.max로 해상도를 높여 왜곡을 최소화합니다.
    _controller = CameraController(
      cameras[_cameraIndex], 
      ResolutionPreset.max, 
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    _initializeControllerFuture = _controller.initialize().then((_) async {
      
      // 💡 수리: 패키지 버전 호환성 문제로 인해 안정화 모드 주석 처리
      /* try {
        await _controller.setVideoStabilizationMode(VideoStabilizationMode.auto);
      } catch (e) {
        debugPrint("이 기기 혹은 버전에서는 소프트웨어 안정화를 지원하지 않습니다: $e");
      }
      */
      
      // 💡 추가: 캡처 방향을 portraitUp으로 고정하여 프리뷰 뒤틀림 방지
      await _controller.lockCaptureOrientation(DeviceOrientation.portraitUp);

      // 기존 노출 설정 유지
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
  // 💡 Phase 4 추가: 외부 미디어 가져오기 안내
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
      onFinish: () => _finishTutorial(), // 모든 튜토리얼 완료 후 저장 호출
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
    if (_isInAlbumDetail) await _loadClipsFromCurrentAlbum();
    if (mounted) setState(() {});
  }

  Future<void> _loadClipsFromCurrentAlbum() async {
    // 💡 동기화 핵심: 호출 즉시 리스트 비우고 화면 갱신 -> 로딩 -> 다시 갱신
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

  // --- [Vlog 병합] ---

  Future<void> _handleMerge() async {
    if (_selectedClipPaths.length < 2) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => BackdropFilter(
        // 💡 주변을 은은하게 블러 처리하여 세련미를 더합니다.
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Center(
          child: Container(
            width: 220, // 화면을 꽉 채우지 않는 적당한 사이즈
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9), // 살짝 투명한 화이트 카드
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  spreadRadius: 5,
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 💡 앱 메인 색상인 blueAccent를 사용한 두꺼운 인디케이터
                const SizedBox(
                  width: 45,
                  height: 45,
                  child: CircularProgressIndicator(
                    strokeWidth: 5,
                    color: Colors.blueAccent,
                    backgroundColor: Color(0xFFE0E0E0),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  "Vlog 생성 중",
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    decoration: TextDecoration.none, // 기본 텍스트 밑줄 제거
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "고화질로 렌더링하고 있어요",
                  style: TextStyle(
                    color: Colors.black45,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final String outputPath = p.join(docDir.path, 'exports', "vlog_${DateTime.now().millisecondsSinceEpoch}.mp4");
      
      // 출력 디렉토리 생성
      final exportDir = Directory(p.join(docDir.path, 'exports'));
      if (!await exportDir.exists()) await exportDir.create(recursive: true);

      // 💡 FFmpeg 병합 커맨드 생성
      // 1. 모든 클립을 표준 포맷(hflip/transpose 대응)으로 정렬하여 concat 합니다.
      StringBuffer inputs = StringBuffer();
      StringBuffer filters = StringBuffer();
      
      // [수정 위치: main.dart 내 _handleMerge 함수 중간 루프]

      for (int i = 0; i < _selectedClipPaths.length; i++) {
        inputs.write("-i \"${_selectedClipPaths[i]}\" ");
        
        // PM 지시 사항: v$i - 1080x1920 스케일링 + 30fps 고정 + 가로세로비 유지(pad)
        filters.write("[$i:v]fps=30,scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2,setsar=1[v$i]; ");
        
        // a$i: 오디오 샘플링 레이트(44100Hz) 및 스테레오 채널 통일
        filters.write("[$i:a]aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=stereo[a$i]; ");
      }

      for (int i = 0; i < _selectedClipPaths.length; i++) {
        filters.write("[v$i][a$i]");
      }
      filters.write("concat=n=${_selectedClipPaths.length}:v=1:a=1[outv][outa]");

      final String ffmpegCommand = "${inputs.toString()}-filter_complex \"${filters.toString()}\" -map \"[outv]\" -map \"[outa]\" -c:v libx264 -preset superfast -crf 20 -c:a aac -b:a 192k \"$outputPath\"";

      await FFmpegKit.execute(ffmpegCommand).then((session) async {
        final returnCode = await session.getReturnCode();
        if (mounted) Navigator.pop(context); // 로딩 닫기

        if (ReturnCode.isSuccess(returnCode)) {
          // 갤러리 저장 및 공유 로직 (기존 유지)
          bool hasAccess = await Gal.hasAccess();
          if (!hasAccess) hasAccess = await Gal.requestAccess();
          if (hasAccess) {
            await Gal.putVideo(outputPath);
            Fluttertoast.showToast(msg: "갤러리에 저장되었습니다!");
          }
          await Share.shareXFiles([XFile(outputPath)], text: '3s Vlog');
        } else {
          final logs = await session.getAllLogsAsString();
          debugPrint("FFmpeg Merge Error: $logs");
          Fluttertoast.showToast(msg: "영상 병합 실패");
        }
      });

      setState(() {
        _isClipSelectionMode = false;
        _selectedClipPaths.clear();
      });
    } catch (e) {
      if (mounted) Navigator.pop(context);
      Fluttertoast.showToast(msg: "오류 발생: $e");
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
    
    // 1. 이동/복사 대상 앨범 선택 다이얼로그 호출
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
                .where((a) => a != videoManager.currentAlbum && a != "휴지통")
                .map((a) => ListTile(title: Text(a), onTap: () => Navigator.pop(c, a)))
          ]
        )
      )
    );

    if (result == null) return;

    String targetAlbum = result;

    // 2. 새 앨범 생성 처리
    if (result == "NEW") {
      String? name = await _showCreateAlbumDialog();
      if (name == null || name.trim().isEmpty) return;
      targetAlbum = name.trim();
      await videoManager.createNewAlbum(targetAlbum);
    }

    // 3. PM 지시 사항: 파일 작업 실행 및 상태 초기화
    await videoManager.executeTransfer(targetAlbum, isMove, snapshot);
    await _loadClipsFromCurrentAlbum();

    // 4. 핵심: 다중 선택 모드 해제 및 리스트 초기화
    setState(() {
      _isClipSelectionMode = false; // 선택 모드 해제
      _selectedClipPaths.clear();    // 선택 리스트 비우기
    });

    // 5. 알림 및 햅틱 피드백 강화
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
      // 💡 민감도(Sensitivity)를 0.15에서 0.07로 하향 조정 (더 예민하게 반응)
      double sensitivity = 0.07; 
      double scaleDiff = d.scale - 1.0; // 1.0(기준점)에서의 차이 계산

      if (scaleDiff.abs() > sensitivity) {
        setState(() {
          if (scaleDiff > 0) { 
            // 🔍 Zoom In (손가락 벌림 -> 그리드 커짐 -> 컬럼 수 감소)
            if (_gridColumnCount == 5) _gridColumnCount = 3;
            else if (_gridColumnCount == 3) _gridColumnCount = 2;
          } else {
            // 🔍 Zoom Out (손가락 오므림 -> 그리드 작아짐 -> 컬럼 수 증가)
            if (_gridColumnCount == 2) _gridColumnCount = 3;
            else if (_gridColumnCount == 3) _gridColumnCount = 5;
          }
          
          // 💡 한 번의 제스처에 한 단계만 넘어가도록 잠금 및 햅틱 피드백
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
    await _controller.startVideoRecording();
    setState(() { _isRecording = true; _remainingTime = 3; });
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingTime > 1 && mounted) setState(() => _remainingTime--); else if (mounted) { _stopRecording(); timer.cancel(); }
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    _recordingTimer?.cancel();
    final video = await _controller.stopVideoRecording();
    await videoManager.saveRecordedVideo(video);
    if (mounted) setState(() { _isRecording = false; _remainingTime = 3; });
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
    return FutureBuilder<void>(
      future: _initializeControllerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              onTapDown: (d) => _handleFocus(d, constraints),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRect(
                    child: FittedBox(
                      fit: BoxFit.cover, // 화면에 꽉 차게 맞추되, 비율을 유지하며 중앙을 크롭합니다.
                      child: SizedBox(
                        width: constraints.maxWidth,
                        // 해상도 비율에 맞춰 높이를 계산하여 늘어남 방지
                        height: constraints.maxWidth * _controller.value.aspectRatio,
                        child: CameraPreview(_controller),
                      ),
                    ),
                  ),
                  if (_tapPosition != null) Positioned(left: _tapPosition!.dx - 35, top: _tapPosition!.dy - 35, child: AnimatedBuilder(animation: _focusAnimController, builder: (context, child) => Container(width: 70, height: 70, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.yellow, width: 2))))),
                  if (_showExposureSlider && _tapPosition != null)
                    Positioned(left: _tapPosition!.dx + 45, top: _tapPosition!.dy - 60, child: SizedBox(height: 120, child: RotatedBox(quarterTurns: 3, child: SliderTheme(data: SliderTheme.of(context).copyWith(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6), overlayShape: const RoundSliderOverlayShape(overlayRadius: 14), activeTrackColor: Colors.yellow, inactiveTrackColor: Colors.white30, thumbColor: Colors.yellow), child: Slider(value: _exposureOffset, min: _minExposure, max: _maxExposure, onChanged: (v) async { setState(() => _exposureOffset = v); await _controller.setExposureOffset(v); _startExposureTimer(); }))))),
                  Positioned(top: 55, left: 20, child: _buildAlbumDropdown()),
                  Positioned(bottom: 70, left: 0, right: 0, child: Column(children: [if (_isRecording) _buildRecordingTimer(), SizedBox(width: constraints.maxWidth, height: 85, child: Stack(alignment: Alignment.center, children: [GestureDetector(onTap: _isRecording ? _stopRecording : _startRecording, child: _buildRecordButton()), if (!_isRecording) Positioned(right: constraints.maxWidth * 0.15, child: IconButton(icon: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 32), onPressed: _toggleCamera))]))])),
                ],
              ),
            ),
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  Widget _buildLibraryMain() { if (_isInAlbumDetail) return _buildDetailView(); return _buildAlbumGridView(); }

  // 💡 상세 화면 (Clip List)
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
                if (_isClipSelectionMode) 
                  Padding(padding: const EdgeInsets.only(right: 12.0), child: ElevatedButton.icon(onPressed: _selectedClipPaths.length >= 2 ? _handleMerge : null, icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 16), label: const Text('Vlog 생성', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)), style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, disabledBackgroundColor: Colors.grey[300], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), elevation: 0)))
                else ...[
                  IconButton(
                    key: keyPickMedia,
                    icon: const Icon(Icons.add_photo_alternate_outlined), 
                    onPressed: _pickMedia
                  ),
                  // 텍스트 버튼 영구 제거
                ]
              ],
            ),
            body: Column(
              children: [
                const Divider(height: 1, thickness: 1, color: Colors.black12),
                Expanded(
                  child: GestureDetector(
                    // 핀치 줌 제스처
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
                              final isFav = videoManager.favorites.contains(path);
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

  // 💡 앨범 목록 (Album List)
  Widget _buildAlbumGridView() {
    bool isAll = _selectedAlbumNames.length == videoManager.albums.where((a) => a != "일상" && a != "휴지통").length && _selectedAlbumNames.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: _isAlbumSelectionMode 
            ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() { _isAlbumSelectionMode = false; _selectedAlbumNames.clear(); })) 
            : null,
        title: Text(_isAlbumSelectionMode ? "${_selectedAlbumNames.length}개 선택" : "앨범"),
        actions: [
          if (_isAlbumSelectionMode)
            IconButton(icon: Icon(isAll ? Icons.check_box : Icons.check_box_outline_blank), onPressed: () => _toggleSelectAll(false))
          else
            IconButton(icon: const Icon(Icons.add, size: 28), onPressed: _showCreateAlbumMain),
        ],
      ),
      body: GestureDetector(
        onScaleStart: (d) { _isZoomingLocked = false; if (_isAlbumSelectionMode && d.pointerCount == 1) _startDragSelection(d.focalPoint, false); },
        onScaleUpdate: (d) => _handleScaleUpdate(d, false),
        child: GridView.builder(
          key: _albumGridKey, padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: _gridColumnCount, crossAxisSpacing: 16, mainAxisSpacing: 16),
          itemCount: videoManager.albums.length,
          itemBuilder: (context, index) {
            final name = videoManager.albums[index]; final isS = _selectedAlbumNames.contains(name); final isP = name == "일상" || name == "휴지통";
            final bool isTarget = name == "일상";
            
            return GestureDetector(
              onLongPress: () { if (!isP) { setState(() { _isAlbumSelectionMode = true; _lastProcessedIndex = index; _isDragAdding = !isS; _selectedAlbumNames.add(name); }); hapticFeedback(); } },
              onTap: () async {
                if (_isAlbumSelectionMode) {
                  if (!isP) setState(() => isS ? _selectedAlbumNames.remove(name) : _selectedAlbumNames.add(name));
                } else {
                  // 💡 버그 수정: 앨범 진입 시 데이터 선행 로드
                  videoManager.currentAlbum = name; 
                  setState(() => videoManager.recordedVideoPaths.clear()); 
                  await videoManager.loadClipsFromCurrentAlbum(); 
                  if (mounted) setState(() => _isInAlbumDetail = true);
                }
              },
              // _buildAlbumGridView 내 GridView.builder -> itemBuilder 부분
              child: Hero(
                tag: 'album_art_$name', // Hero 애니메이션 고유 태그
                child: Container(
                  // 1. 마스터 가이드 디자인 적용: 곡률 20dp + 미세 외곽선 + 그림자
                  decoration: BoxDecoration(
                    color: name == "휴지통" ? const Color(0xFFF2F2F7) : Colors.grey[200], 
                    borderRadius: BorderRadius.circular(20), 
                    border: Border.all(color: Colors.black.withOpacity(0.05), width: 0.5), // 미세 외곽선
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  // 2. 내부 콘텐츠의 곡률을 부모 Container와 일치시킴
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // 썸네일 또는 휴지통 아이콘
                        name == "휴지통" 
                            ? const Center(child: Icon(Icons.delete_outline, size: 40, color: Colors.black26)) 
                            : _buildAlbumThumbnail(name),
                        
                        if (isS) Container(color: Colors.white60), // 선택 모드 오버레이
                        
                        // 하단 가독성 그라데이션
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black54],
                              stops: [0.6, 1.0],
                            ),
                          ),
                        ),
                        
                        // 앨범명 및 클립 수
                        Positioned(
                          bottom: 12, left: 12, right: 12, 
                          child: FutureBuilder<int>(
                            key: ValueKey("count_$name"), 
                            future: videoManager.getClipCount(name), 
                            builder: (context, snapshot) => Text(
                              "$name (${snapshot.data ?? 0})", 
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14), 
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        
                        // 선택 체크박스
                        if (_isAlbumSelectionMode && !isP) 
                          Positioned(
                            top: 10, right: 10, 
                            child: Icon(isS ? Icons.check_circle : Icons.radio_button_unchecked, 
                            color: isS ? Colors.blueAccent : Colors.white70, size: 24),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: (_isAlbumSelectionMode && _selectedAlbumNames.isNotEmpty) ? FloatingActionButton.extended(onPressed: _handleAlbumBatchDelete, backgroundColor: Colors.redAccent, label: const Text("삭제"), icon: const Icon(Icons.delete)) : null,
    );
  }

  Widget _buildExtendedActionPanel() {
    bool isTrash = videoManager.currentAlbum == "휴지통";
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20), padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(blurRadius: 15, color: Colors.black12)]),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: isTrash
            ? [IconButton(icon: const Icon(Icons.settings_backup_restore, color: Colors.blueAccent), onPressed: () async { for (var p in _selectedClipPaths) await videoManager.restoreClip(p); await videoManager.loadClipsFromCurrentAlbum(); setState(() => _isClipSelectionMode = false); hapticFeedback(); }), IconButton(icon: const Icon(Icons.delete_forever, color: Colors.redAccent), onPressed: _handleClipBatchDelete)]
            : [IconButton(icon: const Icon(Icons.favorite, color: Colors.pink), onPressed: () { videoManager.toggleFavoritesBatch(_selectedClipPaths); setState(() { _isClipSelectionMode = false; _selectedClipPaths.clear(); }); hapticFeedback(); }), IconButton(icon: const Icon(Icons.drive_file_move, color: Colors.blue), onPressed: () => _handleMoveOrCopy(true)), IconButton(icon: const Icon(Icons.content_copy, color: Colors.blue), onPressed: () => _handleMoveOrCopy(false)), IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: _handleClipBatchDelete)],
      ),
    );
  }

  void _toggleSelectAll(bool isClip) { setState(() { if (isClip) { if (_selectedClipPaths.length == videoManager.recordedVideoPaths.length) _selectedClipPaths.clear(); else _selectedClipPaths = List.from(videoManager.recordedVideoPaths); } else { final selectable = videoManager.albums.where((a) => a != "일상" && a != "휴지통").toList(); if (_selectedAlbumNames.length == selectable.length) _selectedAlbumNames.clear(); else _selectedAlbumNames = Set.from(selectable); } }); hapticFeedback(); }
  void _showCreateAlbumMain() async { String? name = await _showCreateAlbumDialog(); if (name != null && name.trim().isNotEmpty) { if (videoManager.albums.contains(name.trim())) return; await videoManager.createNewAlbum(name.trim()); _refreshData(); } }
  Future<String?> _showCreateAlbumDialog() async { String input = ""; return showDialog<String>(context: context, builder: (c) => AlertDialog(title: const Text("새 앨범"), content: TextField(onChanged: (v) => input = v, autofocus: true, maxLength: 12), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("취소")), TextButton(onPressed: () => Navigator.pop(c, input), child: const Text("확정"))])); }
  Widget _buildAlbumDropdown() { return ClipRRect(borderRadius: BorderRadius.circular(20), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: Container(height: 42, padding: const EdgeInsets.symmetric(horizontal: 14), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)), child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: videoManager.albums.contains(videoManager.currentAlbum) && videoManager.currentAlbum != "휴지통" ? videoManager.currentAlbum : "일상", icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white), dropdownColor: Colors.black.withOpacity(0.8), onChanged: (v) { setState(() => videoManager.currentAlbum = v!); hapticFeedback(); }, items: videoManager.albums.where((a) => a != "휴지통").map((a) => DropdownMenuItem(value: a, child: Text(a, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)))).toList()))))); }
  Widget _buildRecordingTimer() { return Container(margin: const EdgeInsets.only(bottom: 20), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)), child: Text('0:0$_remainingTime', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))); }
  Widget _buildRecordButton() { return Stack(alignment: Alignment.center, children: [Container(key: keyRecordButton, height: 85, width: 85, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4))), AnimatedContainer(duration: const Duration(milliseconds: 200), height: _isRecording ? 35 : 70, width: _isRecording ? 35 : 70, decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(_isRecording ? 8 : 40)))]); }
  
  // 💡 사이드바 버그 수정: onTap을 async로 변경하여 데이터 동기화 보장
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
                // PM 지시 사항: 데이터 무결성을 위한 async-await 순서 보장
                onTap: () async { 
                  if (videoManager.currentAlbum == name) return; 

                  // 1. 선제적 UI 클리어 (이전 앨범 고스트 현상 방지)
                  setState(() {
                    videoManager.recordedVideoPaths = []; 
                  });

                  // 2. 데이터 로드 대기
                  videoManager.currentAlbum = name;
                  await videoManager.loadClipsFromCurrentAlbum(); 

                  // 3. 로드 완료 후 햅틱과 함께 화면 갱신
                  if (mounted) {
                    hapticFeedback();
                    setState(() {}); 
                  }
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
  @override Widget build(BuildContext context) { final isFav = widget.favorites.contains(widget.filePath); return Positioned.fill(child: Container(color: Colors.black, child: Stack(children: [Center(child: _vController.value.isInitialized ? AspectRatio(aspectRatio: _vController.value.aspectRatio, child: VideoPlayer(_vController)) : const CircularProgressIndicator()), Positioned(top: 40, left: 20, child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 30), onPressed: widget.onClose)), Positioned(bottom: 50, left: 0, right: 0, child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [IconButton(icon: Icon(widget.isTrashMode ? Icons.settings_backup_restore : (isFav ? Icons.favorite : Icons.favorite_border), color: (isFav && !widget.isTrashMode) ? Colors.red : Colors.white, size: 30), onPressed: () { if (widget.isTrashMode) widget.onRestore(widget.filePath); else { widget.onToggleFav(widget.filePath); setState(() {}); } }), IconButton(icon: const Icon(Icons.delete_outline, color: Colors.white, size: 30), onPressed: () => widget.onDelete(widget.filePath))]))]))); }
}

class VideoManager extends ChangeNotifier {
  String currentAlbum = "일상";
  List<String> albums = ["일상", "휴지통"];
  List<String> recordedVideoPaths = [];
  Set<String> favorites = {};
  final Map<String, Uint8List> thumbnailCache = {};

  Future<Uint8List?> getThumbnail(String videoPath) async {
    if (thumbnailCache.containsKey(videoPath)) return thumbnailCache[videoPath];
    final docDir = await getApplicationDocumentsDirectory();
    final thumbDir = Directory(p.join(docDir.path, 'thumbnails'));
    if (!await thumbDir.exists()) await thumbDir.create(recursive: true);
    final thumbFile = File(p.join(thumbDir.path, "${p.basename(videoPath)}.jpg"));
    if (await thumbFile.exists()) {
      final data = await thumbFile.readAsBytes();
      thumbnailCache[videoPath] = data; 
      return data;
    }
    final data = await thum.VideoThumbnail.thumbnailData(video: videoPath, imageFormat: thum.ImageFormat.JPEG, maxWidth: 150, quality: 15);
    if (data != null) {
      thumbnailCache[videoPath] = data;
      thumbFile.writeAsBytes(data).catchError((e) => null); 
    }
    return data;
  }

  Future<void> convertPhotoToVideo(String imagePath, String targetAlbum) async {
    final docDir = await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(docDir.path, 'vlogs', targetAlbum));
    if (!await outDir.exists()) await outDir.create(recursive: true);
    final String outPath = p.join(outDir.path, "photo_${DateTime.now().millisecondsSinceEpoch}.mp4");
    final String ffmpegCommand = "-loop 1 -i \"$imagePath\" -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 -c:v libx264 -t 3 -pix_fmt yuv420p -vf \"scale=trunc(iw/2)*2:trunc(ih/2)*2\" -c:a aac -shortest \"$outPath\"";
    await FFmpegKit.execute(ffmpegCommand).then((session) async { final returnCode = await session.getReturnCode(); if (!ReturnCode.isSuccess(returnCode)) throw Exception("FFmpeg failed"); });
  }

  Future<void> initAlbumSystem() async {
    final docDir = await getApplicationDocumentsDirectory();
    final baseDir = Directory(p.join(docDir.path, 'vlogs'));
    if (!await baseDir.exists()) await baseDir.create(recursive: true);
    await Directory(p.join(baseDir.path, '일상')).create();
    await Directory(p.join(baseDir.path, '휴지통')).create();
    await Directory(p.join(docDir.path, 'thumbnails')).create();
    List<FileSystemEntity> entities = baseDir.listSync().whereType<Directory>().toList();
    List<MapEntry<String, DateTime>> albumWithTime = [];
    for (var entity in entities) { String name = p.basename(entity.path); FileStat stat = await entity.stat(); albumWithTime.add(MapEntry(name, stat.changed)); }
    albumWithTime.sort((a, b) { if (a.key == "일상") return -1; if (b.key == "일상") return 1; if (a.key == "휴지통") return 1; if (b.key == "휴지통") return -1; return a.value.compareTo(b.value); });
    albums = albumWithTime.map((e) => e.key).toList();
    notifyListeners();
  }
  void clearClips() {
    recordedVideoPaths = [];
    notifyListeners();
  }
  Future<void> loadClipsFromCurrentAlbum() async {
    // 1. 기존 데이터 즉시 삭제 (고스트 방지 핵심)
    recordedVideoPaths = [];
    
    final docDir = await getApplicationDocumentsDirectory();
    final albumDir = Directory(p.join(docDir.path, 'vlogs', currentAlbum));
    if (!await albumDir.exists()) await albumDir.create(recursive: true);
    
    final files = albumDir.listSync().whereType<File>()
        .where((f) => f.path.endsWith('.mp4'))
        .map((f) => f.path).toList();
    
    files.sort((a, b) => File(b).lastModifiedSync().compareTo(File(a).lastModifiedSync()));
    
    // 2. 로드 완료 후 할당
    recordedVideoPaths = files;
    notifyListeners();
  }

  void toggleFavoritesBatch(List<String> paths) { for (var path in paths) { if (favorites.contains(path)) favorites.remove(path); else favorites.add(path); } }
  Future<void> moveClipsBatch(List<String> paths, String targetAlbum) async { final docDir = await getApplicationDocumentsDirectory(); for (var oldPath in paths) { final dest = p.join(docDir.path, 'vlogs', targetAlbum, p.basename(oldPath)); try { await File(oldPath).rename(dest); } catch (e) { await File(oldPath).copy(dest); await File(oldPath).delete(); } } notifyListeners(); }
  Future<void> deleteClipsBatch(List<String> paths) async { for (var path in paths) await moveToTrash(path); }
  Future<void> saveRecordedVideo(XFile video) async { final docDir = await getApplicationDocumentsDirectory(); final savePath = p.join(docDir.path, 'vlogs', currentAlbum, "clip_${DateTime.now().millisecondsSinceEpoch}.mp4"); await File(video.path).copy(savePath); await loadClipsFromCurrentAlbum(); }
  Future<void> createNewAlbum(String name) async { final d = await getApplicationDocumentsDirectory(); await Directory(p.join(d.path, 'vlogs', name)).create(recursive: true); await initAlbumSystem(); }
  Future<void> deleteAlbums(Set<String> names) async { final docDir = await getApplicationDocumentsDirectory(); for (var name in names) { if (name == "일상" || name == "휴지통") continue; final dir = Directory(p.join(docDir.path, 'vlogs', name)); if (await dir.exists()) { for (var f in dir.listSync().whereType<File>()) await f.rename(p.join(docDir.path, 'vlogs', '휴지통', "${name}__${p.basename(f.path)}")); await dir.delete(recursive: true); } } }
  Future<void> moveToTrash(String path) async { final docDir = await getApplicationDocumentsDirectory(); await File(path).rename(p.join(docDir.path, 'vlogs', '휴지통', "${currentAlbum}__${p.basename(path)}")); }
  Future<void> restoreClip(String trashPath) async { final docDir = await getApplicationDocumentsDirectory(); final fileName = p.basename(trashPath); String target = "일상"; if (fileName.contains("__")) { final origin = fileName.split("__")[0]; if (await Directory(p.join(docDir.path, 'vlogs', origin)).exists()) target = origin; } final newName = fileName.contains("__") ? fileName.split("__")[1] : fileName; await File(trashPath).rename(p.join(docDir.path, 'vlogs', target, newName)); }
  Future<void> executeTransfer(String target, bool isMove, List<String> list) async { final docDir = await getApplicationDocumentsDirectory(); for (var old in list) { final dest = p.join(docDir.path, 'vlogs', target, p.basename(old)); if (isMove) { final f = File(old); try { await f.rename(dest); } catch (e) { await f.copy(dest); await f.delete(); } } else { await File(old).copy(dest); } } }
  
  Future<String?> getFirstClipPath(String n) async { final docDir = await getApplicationDocumentsDirectory(); final dir = Directory(p.join(docDir.path, 'vlogs', n)); if (!await dir.exists()) return null; final f = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.mp4')).toList(); return f.isNotEmpty ? f.first.path : null; }
  Future<int> getClipCount(String name) async { final docDir = await getApplicationDocumentsDirectory(); final dir = Directory(p.join(docDir.path, 'vlogs', name)); if (!await dir.exists()) return 0; return dir.listSync().whereType<File>().where((f) => f.path.endsWith('.mp4')).length; }
}