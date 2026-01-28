import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:path/path.dart' as p;
import 'package:video_thumbnail/video_thumbnail.dart' as thum;

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
      title: '3s 4.0.8',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: const ColorScheme.light(
          primary: Colors.black,
          secondary: Colors.blueAccent,
        ),
        useMaterial3: true,
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
  // 💡 데이터 로직 관리자 (인스턴스 유지)
  final VideoManager videoManager = VideoManager();
  
  int _selectedIndex = 0;
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;

  // 촬영 및 포커스 상태
  bool _isRecording = false;
  int _remainingTime = 3;
  Timer? _recordingTimer;
  Offset? _tapPosition;
  late AnimationController _focusAnimController;

  bool _isInAlbumDetail = false;

  // 선택 상태
  bool _isClipSelectionMode = false;
  Set<String> _selectedClipPaths = {};
  bool _isAlbumSelectionMode = false;
  Set<String> _selectedAlbumNames = {};
  bool _isDragAdding = true;
  int? _lastProcessedIndex;

  // 제스처 및 레이아웃 (수치 보존)
  int _gridColumnCount = 3;
  bool _isZoomingLocked = false;
  double _lastScale = 1.0;
  bool _isSidebarOpen = true;
  final double _narrowSidebarWidth = 80.0;

  final GlobalKey _clipGridKey = GlobalKey(debugLabel: 'clipGrid');
  final GlobalKey _albumGridKey = GlobalKey(debugLabel: 'albumGrid');
  String? _previewingPath;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(cameras[0], ResolutionPreset.high, enableAudio: true);
    _initializeControllerFuture = _controller.initialize();
    _focusAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _initAlbumSystem();
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _controller.dispose();
    _focusAnimController.dispose();
    super.dispose();
  }

  void hapticFeedback() {
    HapticFeedback.lightImpact();
  }

  // --- [데이터 엔진 연동 부] ---

  Future<void> _initAlbumSystem() async {
    await videoManager.initAlbumSystem();
    if (_isInAlbumDetail) await _loadClipsFromCurrentAlbum();
    if (mounted) setState(() {});
  }

  Future<void> _loadClipsFromCurrentAlbum() async {
    await videoManager.loadClipsFromCurrentAlbum();
    setState(() {
      _selectedClipPaths.clear();
      _isClipSelectionMode = false;
    });
  }

  // 💡 UI 호출부 수리: _restoreClip 로컬 함수를 제거하고 videoManager로 통합
  Future<void> _handleRestore(String path) async {
    await videoManager.restoreClip(path);
    await _loadClipsFromCurrentAlbum();
    if (mounted) setState(() {});
    hapticFeedback();
  }

  Future<void> _executeTransfer(String target, bool isMove, List<String> list) async {
    if (isMove) {
      await videoManager.moveClipsBatch(list, target);
    } else {
      await videoManager.executeTransfer(target, isMove, list);
    }
    await _loadClipsFromCurrentAlbum();
    if (mounted) setState(() {});
  }

  // --- [기존 제스처 및 디자인 로직 (절대 보존)] ---

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
        if (isClip) {
          if (_isDragAdding) _selectedClipPaths.add(item); else _selectedClipPaths.remove(item);
        } else {
          if (item != "일상" && item != "휴지통") {
            if (_isDragAdding) _selectedAlbumNames.add(item); else _selectedAlbumNames.remove(item);
          }
        }
      });
      HapticFeedback.selectionClick();
    }
  }

  void _handleScaleUpdate(ScaleUpdateDetails d, bool isClip) {
    if (d.pointerCount > 1) {
      if (_isZoomingLocked) return;
      if ((d.scale - _lastScale).abs() > 0.1) {
        setState(() {
          if (d.scale > 1.05) { if (_gridColumnCount > 2) _gridColumnCount = _gridColumnCount == 5 ? 3 : 2; }
          else if (d.scale < 0.95) { if (_gridColumnCount < 5) _gridColumnCount = _gridColumnCount == 2 ? 3 : 5; }
          _isZoomingLocked = true;
          HapticFeedback.mediumImpact();
        });
        _lastScale = d.scale;
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
          if (isClip) {
            if (_isDragAdding) _selectedClipPaths.add(item); else _selectedClipPaths.remove(item);
          } else {
            if (item != "일상" && item != "휴지통") {
              if (_isDragAdding) _selectedAlbumNames.add(item); else _selectedAlbumNames.remove(item);
            }
          }
        });
        HapticFeedback.selectionClick();
      }
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
        body: IndexedStack(
          index: _selectedIndex,
          children: [_buildCaptureTab(), _buildLibraryMain()],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (i) {
            setState(() {
              _selectedIndex = i;
              if (i == 0 && videoManager.currentAlbum == "휴지통") videoManager.currentAlbum = "일상";
              if (i == 1) _initAlbumSystem();
            });
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: "촬영"),
            BottomNavigationBarItem(icon: Icon(Icons.photo_library), label: "라이브러리"),
          ],
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
                  CameraPreview(_controller),
                  if (_tapPosition != null)
                    Positioned(
                      left: _tapPosition!.dx - 35, top: _tapPosition!.dy - 35,
                      child: AnimatedBuilder(
                        animation: _focusAnimController,
                        builder: (context, child) => Container(
                          width: 70, height: 70,
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.yellow, width: 2)),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 55, left: 20,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          height: 42, padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: videoManager.albums.contains(videoManager.currentAlbum) && videoManager.currentAlbum != "휴지통"
                                  ? videoManager.currentAlbum : "일상",
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
                              dropdownColor: Colors.black.withOpacity(0.8),
                              onChanged: (v) { setState(() => videoManager.currentAlbum = v!); hapticFeedback(); },
                              items: videoManager.albums
                                  .where((a) => a != "휴지통")
                                  .map((a) => DropdownMenuItem(value: a, child: Text(a, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14))))
                                  .toList(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 70, left: 0, right: 0,
                    child: Column(
                      children: [
                        if (_isRecording)
                          Container(
                            margin: const EdgeInsets.only(bottom: 20),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                            child: Text('0:0$_remainingTime', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        GestureDetector(
                          onTap: _isRecording ? _stopRecording : _startRecording,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(height: 85, width: 85, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4))),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                height: _isRecording ? 35 : 70, width: _isRecording ? 35 : 70,
                                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(_isRecording ? 8 : 40)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  Widget _buildLibraryMain() {
    if (_isInAlbumDetail) return _buildDetailView();
    return _buildAlbumGridView();
  }

  Widget _buildAlbumGridView() {
    bool isAll = _selectedAlbumNames.length == videoManager.albums.where((a) => a != "일상" && a != "휴지통").length && _selectedAlbumNames.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        leading: _isAlbumSelectionMode ? IconButton(icon: Icon(isAll ? Icons.check_box : Icons.check_box_outline_blank), onPressed: () => _toggleSelectAll(false)) : null,
        title: Text(_isAlbumSelectionMode ? "${_selectedAlbumNames.length}개 선택" : "앨범"),
        actions: [
          if (!_isAlbumSelectionMode) IconButton(icon: const Icon(Icons.add), onPressed: _showCreateAlbumMain),
          TextButton(onPressed: () => setState(() { _isAlbumSelectionMode = !_isAlbumSelectionMode; _selectedAlbumNames.clear(); }), child: Text(_isAlbumSelectionMode ? "취소" : "선택")),
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
            final name = videoManager.albums[index];
            final isS = _selectedAlbumNames.contains(name);
            final isP = name == "일상" || name == "휴지통";
            return GestureDetector(
              onLongPress: () { if (!isP) { setState(() { _isAlbumSelectionMode = true; _lastProcessedIndex = index; _isDragAdding = !isS; _selectedAlbumNames.add(name); }); hapticFeedback(); } },
              onTap: () {
                if (_isAlbumSelectionMode) { if (!isP) setState(() => isS ? _selectedAlbumNames.remove(name) : _selectedAlbumNames.add(name)); }
                else { setState(() { videoManager.currentAlbum = name; _isInAlbumDetail = true; }); _loadClipsFromCurrentAlbum(); }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: name == "휴지통" ? const Color(0xFFF2F2F7) : Colors.grey[200],
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    name == "휴지통" ? const Icon(Icons.delete_outline, size: 40, color: Colors.black26) : _buildAlbumThumbnail(name),
                    if (isS) Container(color: Colors.white60),
                    Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black54], stops: [0.7, 1.0]))),
                    Positioned(
                      bottom: 10, left: 10, right: 10,
                      child: FutureBuilder<int>(
                        future: videoManager.getClipCount(name),
                        builder: (context, snapshot) => Text("$name (${snapshot.data ?? 0})", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    if (_isAlbumSelectionMode && !isP)
                      Positioned(top: 8, right: 8, child: Icon(isS ? Icons.check_circle : Icons.radio_button_unchecked, color: isS ? Colors.blueAccent : Colors.white70, size: 22)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: (_isAlbumSelectionMode && _selectedAlbumNames.isNotEmpty)
          ? FloatingActionButton.extended(onPressed: _handleAlbumBatchDelete, backgroundColor: Colors.redAccent, label: const Text("삭제"), icon: const Icon(Icons.delete))
          : null,
    );
  }

  Widget _buildDetailView() {
    bool isAll = _selectedClipPaths.length == videoManager.recordedVideoPaths.length && _selectedClipPaths.isNotEmpty;
    return Row(
      children: [
        AnimatedContainer(duration: const Duration(milliseconds: 250), width: _isSidebarOpen ? _narrowSidebarWidth : 0, color: const Color(0xFFFBFBFC), child: _buildNarrowSidebar()),
        Expanded(
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.white, elevation: 0,
              leading: _isClipSelectionMode
                  ? IconButton(icon: Icon(isAll ? Icons.check_box : Icons.check_box_outline_blank), onPressed: () => _toggleSelectAll(true))
                  : IconButton(icon: const Icon(Icons.menu_open), onPressed: () => setState(() => _isSidebarOpen = !_isSidebarOpen)),
              title: Text(_isClipSelectionMode ? "${_selectedClipPaths.length}개 선택" : "${videoManager.currentAlbum} (${videoManager.recordedVideoPaths.length})"),
              actions: [TextButton(onPressed: () => setState(() { _isClipSelectionMode = !_isClipSelectionMode; _selectedClipPaths.clear(); }), child: Text(_isClipSelectionMode ? "완료" : "선택"))],
            ),
            body: GestureDetector(
              onScaleStart: (d) { _isZoomingLocked = false; if (_isClipSelectionMode && d.pointerCount == 1) _startDragSelection(d.focalPoint, true); },
              onScaleUpdate: (d) => _handleScaleUpdate(d, true),
              child: Stack(
                children: [
                  GridView.builder(
                    key: _clipGridKey, padding: const EdgeInsets.all(2),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: _gridColumnCount, crossAxisSpacing: 2, mainAxisSpacing: 2),
                    itemCount: videoManager.recordedVideoPaths.length,
                    itemBuilder: (context, index) {
                      final path = videoManager.recordedVideoPaths[index];
                      final isS = _selectedClipPaths.contains(path);
                      final isFav = videoManager.favorites.contains(path);
                      return GestureDetector(
                        onLongPress: () { setState(() { _isClipSelectionMode = true; _lastProcessedIndex = index; _isDragAdding = !isS; _selectedClipPaths.add(path); }); hapticFeedback(); },
                        onTap: () { if (_isClipSelectionMode) setState(() => isS ? _selectedClipPaths.remove(path) : _selectedClipPaths.add(path)); else setState(() => _previewingPath = path); },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildThumbnailWidget(path),
                            if (isFav) Positioned(bottom: 4, left: 4, child: const Icon(Icons.favorite, color: Colors.white, size: 16)),
                            if (isS) Container(color: Colors.white54),
                            if (_isClipSelectionMode) Positioned(bottom: 4, right: 4, child: Icon(isS ? Icons.check_circle : Icons.radio_button_unchecked, color: isS ? Colors.blueAccent : Colors.white70, size: 20)),
                          ],
                        ),
                      );
                    },
                  ),
                  if (_previewingPath != null)
                    VideoPreviewWidget(
                      filePath: _previewingPath!,
                      favorites: videoManager.favorites,
                      isTrashMode: videoManager.currentAlbum == "휴지통",
                      onToggleFav: (p) => setState(() { if (videoManager.favorites.contains(p)) videoManager.favorites.remove(p); else videoManager.favorites.add(p); }),
                      onRestore: (p) => _handleRestore(p), // 💡 호출부 수리
                      onDelete: (p) => _handleSafeSingleDelete(p),
                      onClose: () => setState(() => _previewingPath = null),
                    ),
                ],
              ),
            ),
            floatingActionButton: (_isClipSelectionMode && _selectedClipPaths.isNotEmpty) ? _buildExtendedActionPanel() : null,
            floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
          ),
        ),
      ],
    );
  }

  // --- [액션 패널 및 배치 처리 로직 연결] ---

  Widget _buildExtendedActionPanel() {
    bool isTrash = videoManager.currentAlbum == "휴지통";
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20), padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(blurRadius: 15, color: Colors.black12)]),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: isTrash
            ? [
                IconButton(icon: const Icon(Icons.settings_backup_restore, color: Colors.blueAccent), onPressed: () async {
                   for (var p in _selectedClipPaths) await videoManager.restoreClip(p);
                   await _loadClipsFromCurrentAlbum();
                   setState(() => _isClipSelectionMode = false);
                   hapticFeedback();
                }),
                IconButton(icon: const Icon(Icons.delete_forever, color: Colors.redAccent), onPressed: _handleClipBatchDelete),
              ]
            : [
                if (_selectedClipPaths.length >= 2) IconButton(icon: const Icon(Icons.ios_share, color: Colors.blue), onPressed: () => _handleMerge()),
                IconButton(icon: const Icon(Icons.favorite, color: Colors.pink), onPressed: () { 
                  videoManager.toggleFavoritesBatch(_selectedClipPaths.toList()); // 💡 일괄 즐겨찾기
                  setState(() { _isClipSelectionMode = false; _selectedClipPaths.clear(); }); 
                  hapticFeedback(); 
                }),
                IconButton(icon: const Icon(Icons.drive_file_move, color: Colors.blue), onPressed: () => _handleMoveOrCopy(true)),
                IconButton(icon: const Icon(Icons.content_copy, color: Colors.blue), onPressed: () => _handleMoveOrCopy(false)),
                IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: _handleClipBatchDelete),
              ],
      ),
    );
  }

  // --- [스마트 병합 로직] ---

  Future<void> _handleMerge() async {
    List<String> paths = _selectedClipPaths.toList();
    
    // 💡 스마트 병합: 별표(Favorite) 표시된 클립을 리스트 상단(앞쪽)으로 정렬
    paths.sort((a, b) {
      bool favA = videoManager.favorites.contains(a);
      bool favB = videoManager.favorites.contains(b);
      if (favA && !favB) return -1;
      if (!favA && favB) return 1;
      return 0;
    });

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final String outputPath = p.join(docDir.path, 'exports', "vlog_${DateTime.now().millisecondsSinceEpoch}.mp4");
      const platform = MethodChannel('com.vlog.app/video_merger');
      final String? mergedPath = await platform.invokeMethod('mergeVideos', { 'inputPaths': paths, 'outputPath': outputPath });
      if (mergedPath != null) await Share.shareXFiles([XFile(mergedPath)], text: '3s Vlog');
    } catch (e) { debugPrint("Merge Error: $e"); }
  }

  // --- [기타 실행부] ---

  Future<void> _startRecording() async {
    await _controller.startVideoRecording();
    setState(() { _isRecording = true; _remainingTime = 3; });
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingTime > 1 && mounted) setState(() => _remainingTime--);
      else if (mounted) { _stopRecording(); timer.cancel(); }
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    _recordingTimer?.cancel();
    final video = await _controller.stopVideoRecording();
    await videoManager.saveRecordedVideo(video);
    if (mounted) setState(() { _isRecording = false; _remainingTime = 3; });
  }

  Future<void> _handleSafeSingleDelete(String path) async {
    bool isTrash = videoManager.currentAlbum == "휴지통";
    if (isTrash) {
      bool? ok = await showDialog(context: context, builder: (c) => AlertDialog(title: const Text("영구 삭제"), content: const Text("복구할 수 없습니다. 삭제할까요?"), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("취소")), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("확인"))]));
      if (ok != true) return;
      await File(path).delete();
    } else {
      await videoManager.moveToTrash(path);
    }
    await _loadClipsFromCurrentAlbum();
    setState(() => _previewingPath = null);
    hapticFeedback();
  }

  Future<void> _handleClipBatchDelete() async {
    bool isTrash = videoManager.currentAlbum == "휴지통";
    if (isTrash) {
      bool? ok = await showDialog(context: context, builder: (c) => AlertDialog(title: const Text("영구 삭제"), content: const Text("선택한 클립을 모두 삭제할까요?"), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("취소")), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("확인"))]));
      if (ok != true) return;
      for (var path in _selectedClipPaths) await File(path).delete();
    } else {
      await videoManager.deleteClipsBatch(_selectedClipPaths.toList()); // 💡 일괄 삭제 연결
    }
    await _loadClipsFromCurrentAlbum();
    hapticFeedback();
  }

  Future<void> _handleAlbumBatchDelete() async {
    bool? ok = await showDialog(context: context, builder: (c) => AlertDialog(title: const Text("앨범 삭제"), content: const Text("앨범은 삭제되고 클립은 휴지통으로 이동합니다."), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("취소")), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("확인", style: TextStyle(color: Colors.red)))]));
    if (ok == true) {
      await videoManager.deleteAlbums(_selectedAlbumNames);
      setState(() { _isAlbumSelectionMode = false; _selectedAlbumNames.clear(); });
      await _initAlbumSystem();
    }
  }

  Future<void> _handleMoveOrCopy(bool isMove) async {
    final snapshot = List<String>.from(_selectedClipPaths);
    final String? result = await showDialog<String>(context: context, builder: (c) => AlertDialog(title: Text(isMove ? "이동" : "복사"), content: Column(mainAxisSize: MainAxisSize.min, children: [ListTile(leading: const Icon(Icons.add_circle, color: Colors.blueAccent), title: const Text("새 앨범 만들기"), onTap: () => Navigator.pop(c, "NEW")), const Divider(), ...videoManager.albums.where((a) => a != videoManager.currentAlbum && a != "휴지통").map((a) => ListTile(title: Text(a), onTap: () => Navigator.pop(c, a)))])));
    if (result == "NEW") {
      String? name = await _showCreateAlbumDialog();
      if (name != null) {
        await videoManager.createNewAlbum(name.trim());
        await _executeTransfer(name.trim(), isMove, snapshot);
      }
    } else if (result != null) {
      await _executeTransfer(result, isMove, snapshot);
    }
  }

  void _toggleSelectAll(bool isClip) {
    setState(() {
      if (isClip) { if (_selectedClipPaths.length == videoManager.recordedVideoPaths.length) _selectedClipPaths.clear(); else _selectedClipPaths = Set.from(videoManager.recordedVideoPaths); }
      else { final selectable = videoManager.albums.where((a) => a != "일상" && a != "휴지통").toList(); if (_selectedAlbumNames.length == selectable.length) _selectedAlbumNames.clear(); else _selectedAlbumNames = Set.from(selectable); }
    });
    hapticFeedback();
  }

  void _showCreateAlbumMain() async {
    String? name = await _showCreateAlbumDialog();
    if (name != null && name.trim().isNotEmpty) {
      if (videoManager.albums.contains(name.trim())) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("중복 이름입니다."), backgroundColor: Colors.orange));
        return;
      }
      await videoManager.createNewAlbum(name.trim());
      await _initAlbumSystem();
    }
  }

  Future<String?> _showCreateAlbumDialog() async {
    String input = "";
    return showDialog<String>(context: context, builder: (c) => AlertDialog(title: const Text("새 앨범"), content: TextField(onChanged: (v) => input = v, autofocus: true, maxLength: 12), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("취소")), TextButton(onPressed: () => Navigator.pop(c, input), child: const Text("확정"))]));
  }

  Future<void> _handleFocus(TapDownDetails d, BoxConstraints c) async {
    if (d.localPosition.dy > c.maxHeight - 150) return;
    setState(() => _tapPosition = d.localPosition);
    _focusAnimController.forward(from: 0.0);
    try { await _controller.setFocusPoint(Offset(d.localPosition.dx / c.maxWidth, d.localPosition.dy / c.maxHeight)); } catch (_) {}
    Future.delayed(const Duration(milliseconds: 500), () { if (mounted) setState(() => _tapPosition = null); });
  }

  Widget _buildNarrowSidebar() {
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 12),
          IconButton(icon: const Icon(Icons.grid_view_rounded, size: 22), onPressed: () => setState(() => _isInAlbumDetail = false)),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: videoManager.albums.length,
              itemBuilder: (context, index) {
                final name = videoManager.albums[index];
                bool isS = videoManager.currentAlbum == name;
                return GestureDetector(
                  onTap: () { setState(() => videoManager.currentAlbum = name); _loadClipsFromCurrentAlbum(); },
                  child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(children: [Icon(name == "휴지통" ? Icons.delete_outline : Icons.folder_rounded, color: isS ? Colors.blueAccent : Colors.black26, size: 26), const SizedBox(height: 2), Text(name, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9))])),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumThumbnail(String name) {
    return FutureBuilder<String?>(future: videoManager.getFirstClipPath(name), builder: (c, s) => s.hasData && s.data != null ? _buildThumbnailWidget(s.data!) : const Center(child: Icon(Icons.folder_open, size: 40, color: Colors.black12)));
  }

  Widget _buildThumbnailWidget(String p) {
    return FutureBuilder<Uint8List?>(future: videoManager.getThumbnail(p), builder: (c, s) => s.hasData ? Image.memory(s.data!, fit: BoxFit.cover) : Container(color: Colors.grey[100]));
  }
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
  @override Widget build(BuildContext context) {
    final isFav = widget.favorites.contains(widget.filePath);
    return Positioned.fill(child: Container(color: Colors.black, child: Stack(children: [Center(child: _vController.value.isInitialized ? AspectRatio(aspectRatio: _vController.value.aspectRatio, child: VideoPlayer(_vController)) : const CircularProgressIndicator()), Positioned(top: 40, left: 20, child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 30), onPressed: widget.onClose)), Positioned(bottom: 50, left: 0, right: 0, child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [IconButton(icon: Icon(widget.isTrashMode ? Icons.settings_backup_restore : (isFav ? Icons.favorite : Icons.favorite_border), color: (isFav && !widget.isTrashMode) ? Colors.red : Colors.white, size: 30), onPressed: () { if (widget.isTrashMode) widget.onRestore(widget.filePath); else { widget.onToggleFav(widget.filePath); setState(() {}); } }), IconButton(icon: const Icon(Icons.delete_outline, color: Colors.white, size: 30), onPressed: () => widget.onDelete(widget.filePath))]))])));
  }
}

// --- [💡 VideoManager 클래스: 데이터 로직 및 배치 기능 강화] ---

class VideoManager extends ChangeNotifier {
  String currentAlbum = "일상";
  List<String> albums = ["일상", "휴지통"];
  List<String> recordedVideoPaths = [];
  Set<String> favorites = {};
  final Map<String, Uint8List> thumbnailCache = {};

  Future<void> initAlbumSystem() async {
    final docDir = await getApplicationDocumentsDirectory();
    final baseDir = Directory(p.join(docDir.path, 'vlogs'));
    if (!await baseDir.exists()) await baseDir.create(recursive: true);
    await Directory(p.join(baseDir.path, '일상')).create();
    await Directory(p.join(baseDir.path, '휴지통')).create();

    List<FileSystemEntity> entities = baseDir.listSync().whereType<Directory>().toList();
    List<MapEntry<String, DateTime>> albumWithTime = [];
    for (var entity in entities) {
      String name = p.basename(entity.path);
      FileStat stat = await entity.stat();
      albumWithTime.add(MapEntry(name, stat.changed));
    }

    albumWithTime.sort((a, b) {
      if (a.key == "일상") return -1; if (b.key == "일상") return 1;
      if (a.key == "휴지통") return 1; if (b.key == "휴지통") return -1;
      return a.value.compareTo(b.value);
    });

    albums = albumWithTime.map((e) => e.key).toList();
    notifyListeners();
  }

  Future<void> loadClipsFromCurrentAlbum() async {
    final docDir = await getApplicationDocumentsDirectory();
    final albumDir = Directory(p.join(docDir.path, 'vlogs', currentAlbum));
    if (!await albumDir.exists()) await albumDir.create(recursive: true);
    final files = albumDir.listSync().whereType<File>().where((f) => f.path.endsWith('.mp4')).map((f) => f.path).toList();
    files.sort((a, b) => File(b).lastModifiedSync().compareTo(File(a).lastModifiedSync()));
    recordedVideoPaths = files;
    notifyListeners();
  }

  // 💡 확장: 별표 상태 일괄 처리
  void toggleFavoritesBatch(List<String> paths) {
    for (var path in paths) {
      if (favorites.contains(path)) favorites.remove(path);
      else favorites.add(path);
    }
  }

  // 💡 확장: 선택 클립 일괄 폴더 이동 (Rename)
  Future<void> moveClipsBatch(List<String> paths, String targetAlbum) async {
    final docDir = await getApplicationDocumentsDirectory();
    for (var oldPath in paths) {
      final dest = p.join(docDir.path, 'vlogs', targetAlbum, p.basename(oldPath));
      try { await File(oldPath).rename(dest); } catch (e) {
        await File(oldPath).copy(dest);
        await File(oldPath).delete();
      }
    }
  }

  // 💡 확장: 선택 클립 일괄 삭제 (휴지통 이동)
  Future<void> deleteClipsBatch(List<String> paths) async {
    for (var path in paths) { await moveToTrash(path); }
  }

  Future<void> saveRecordedVideo(XFile video) async {
    final docDir = await getApplicationDocumentsDirectory();
    final savePath = p.join(docDir.path, 'vlogs', currentAlbum, "clip_${DateTime.now().millisecondsSinceEpoch}.mp4");
    await File(video.path).copy(savePath);
    await loadClipsFromCurrentAlbum();
  }

  Future<void> createNewAlbum(String name) async {
    final d = await getApplicationDocumentsDirectory();
    await Directory(p.join(d.path, 'vlogs', name)).create(recursive: true);
    await initAlbumSystem();
  }

  Future<void> deleteAlbums(Set<String> names) async {
    final docDir = await getApplicationDocumentsDirectory();
    for (var name in names) {
      if (name == "일상" || name == "휴지통") continue;
      final dir = Directory(p.join(docDir.path, 'vlogs', name));
      if (await dir.exists()) {
        for (var f in dir.listSync().whereType<File>()) {
          await f.rename(p.join(docDir.path, 'vlogs', '휴지통', "${name}__${p.basename(f.path)}"));
        }
        await dir.delete(recursive: true);
      }
    }
  }

  Future<void> moveToTrash(String path) async {
    final docDir = await getApplicationDocumentsDirectory();
    await File(path).rename(p.join(docDir.path, 'vlogs', '휴지통', "${currentAlbum}__${p.basename(path)}"));
  }

  Future<void> restoreClip(String trashPath) async {
    final docDir = await getApplicationDocumentsDirectory();
    final fileName = p.basename(trashPath);
    String target = "일상";
    if (fileName.contains("__")) {
      final origin = fileName.split("__")[0];
      if (await Directory(p.join(docDir.path, 'vlogs', origin)).exists()) target = origin;
    }
    final newName = fileName.contains("__") ? fileName.split("__")[1] : fileName;
    await File(trashPath).rename(p.join(docDir.path, 'vlogs', target, newName));
  }

  Future<void> executeTransfer(String target, bool isMove, List<String> list) async {
    final docDir = await getApplicationDocumentsDirectory();
    for (var old in list) {
      final dest = p.join(docDir.path, 'vlogs', target, p.basename(old));
      if (isMove) {
        final f = File(old);
        try { await f.rename(dest); } catch (e) { await f.copy(dest); await f.delete(); }
      } else { await File(old).copy(dest); }
    }
  }

  Future<Uint8List?> getThumbnail(String p) async {
    if (thumbnailCache.containsKey(p)) return thumbnailCache[p];
    final data = await thum.VideoThumbnail.thumbnailData(video: p, imageFormat: thum.ImageFormat.JPEG, maxWidth: 250, quality: 25);
    if (data != null) thumbnailCache[p] = data;
    return data;
  }

  Future<String?> getFirstClipPath(String n) async {
    final docDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docDir.path, 'vlogs', n));
    if (!await dir.exists()) return null;
    final f = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.mp4')).toList();
    return f.isNotEmpty ? f.first.path : null;
  }

  Future<int> getClipCount(String name) async {
    final docDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docDir.path, 'vlogs', name));
    if (!await dir.exists()) return 0;
    return dir.listSync().whereType<File>().where((f) => f.path.endsWith('.mp4')).length;
  }
}