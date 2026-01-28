class _MainNavigationScreenState extends State<MainNavigationScreen>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;

  // 💡 VideoManager 인스턴스 생성
  final VideoManager videoManager = VideoManager();

  // 촬영 및 포커스 상태 (UI 상태이므로 유지)
  bool _isRecording = false;
  int _remainingTime = 3;
  Timer? _recordingTimer;
  Offset? _tapPosition;
  late AnimationController _focusAnimController;

  // UI 전용 제어 상태 (유지)
  bool _isInAlbumDetail = false;
  bool _isClipSelectionMode = false;
  bool _isAlbumSelectionMode = false;
  bool _isDragAdding = true;
  int? _lastProcessedIndex;
  int _gridColumnCount = 3;
  bool _isZoomingLocked = false;
  double _lastScale = 1.0;
  bool _isSidebarOpen = true;
  final double _narrowSidebarWidth = 80.0;
  String? _previewingPath;

  final GlobalKey _clipGridKey = GlobalKey(debugLabel: 'clipGrid');
  final GlobalKey _albumGridKey = GlobalKey(debugLabel: 'albumGrid');

  @override
  void initState() {
    super.initState();
    _controller = CameraController(cameras[0], ResolutionPreset.high, enableAudio: true);
    _initializeControllerFuture = _controller.initialize();
    _focusAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    
    // 초기 데이터 로드
    _refreshData();
  }

  // 데이터 갱신 보조 함수
  Future<void> _refreshData() async {
    await videoManager.initAlbumSystem();
    if (_isInAlbumDetail) await videoManager.loadClipsFromCurrentAlbum();
    if (mounted) setState(() {});
  }

  // ... (기존 위젯 빌드 함수들 내에서 아래와 같이 호출)
  // 예: _albums[index] -> videoManager.albums[index]
  // 예: _recordedVideoPaths.length -> videoManager.recordedVideoPaths.length
  // 예: _favorites.contains(path) -> videoManager.favorites.contains(path)