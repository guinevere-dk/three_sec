import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/video_widgets.dart';
import '../widgets/media_widgets.dart';
import '../widgets/media_dialogs.dart';
import '../utils/haptics.dart';
import '../utils/media_selection_helper.dart';
import '../managers/video_manager.dart';
import '../services/cloud_service.dart';
import '../services/auth_service.dart';

enum _SelectionActionState { local, cloud, mixed }

class LibraryScreen extends StatefulWidget {
  final GlobalKey keyPickMedia;
  final GlobalKey keyAlbumGridItem;
  final GlobalKey keyFirstClip;
  final GlobalKey keyCreateProject;
  final Function() onRefreshData;
  final Function(List<String> selectedPaths) onMerge;
  final Function(String path) onPickMedia;
  final ValueChanged<bool>? onAlbumDetailVisibilityChanged;
  final ValueChanged<bool>? onCreateProjectButtonVisibilityChanged;
  final ValueChanged<List<String>>? onSelectedClipPathsChanged;
  final bool isActive;

  const LibraryScreen({
    super.key,
    required this.keyPickMedia,
    required this.keyAlbumGridItem,
    required this.keyFirstClip,
    required this.keyCreateProject,
    required this.onRefreshData,
    required this.onMerge,
    required this.onPickMedia,
    this.onAlbumDetailVisibilityChanged,
    this.onCreateProjectButtonVisibilityChanged,
    this.onSelectedClipPathsChanged,
    required this.isActive,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _isInAlbumDetail = false;
  bool _isClipSelectionMode = false;
  bool _isAlbumSelectionMode = false;
  bool _isDragAdding = true;
  int? _dragStartIndex;

  int _gridColumnCount = 3;
  bool _isZoomingLocked = false;

  String? _previewingPath;
  String _storageFilter = 'all';

  final GlobalKey _clipGridKey = GlobalKey(debugLabel: 'clipGrid');
  final GlobalKey _albumGridKey = GlobalKey(debugLabel: 'albumGrid');

  List<String> _selectedClipPaths = [];
  Set<String> _selectedAlbumNames = {};

  late VideoManager videoManager;
  final CloudService _cloudService = CloudService();
  bool _lastAlbumDetailVisible = false;
  bool _lastCreateProjectButtonVisible = false;

  bool _isCreateProjectButtonVisible() {
    return _isClipSelectionMode &&
        _selectedClipPaths.length >= 2 &&
        videoManager.currentAlbum != '휴지통';
  }

  void _notifyCreateProjectButtonVisibilityIfNeeded() {
    final visible = _isCreateProjectButtonVisible();
    if (visible == _lastCreateProjectButtonVisible) return;
    _lastCreateProjectButtonVisible = visible;
    widget.onCreateProjectButtonVisibilityChanged?.call(visible);
  }

  void _notifyAlbumDetailVisibilityIfNeeded() {
    final visible = _isInAlbumDetail;
    if (visible == _lastAlbumDetailVisible) return;
    _lastAlbumDetailVisible = visible;
    widget.onAlbumDetailVisibilityChanged?.call(visible);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      videoManager = Provider.of<VideoManager>(context, listen: false);
      await videoManager.initAlbumSystem();
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      setState(_resetTransientState);
    }
  }

  void _resetTransientState() {
    _isInAlbumDetail = false;
    _isClipSelectionMode = false;
    _isAlbumSelectionMode = false;
    _isDragAdding = true;
    _dragStartIndex = null;
    _gridColumnCount = 3;
    _isZoomingLocked = false;
    _previewingPath = null;
    _storageFilter = 'all';
    _selectedClipPaths.clear();
    _selectedAlbumNames.clear();
    _lastAlbumDetailVisible = false;
    _lastCreateProjectButtonVisible = false;
  }

  final ScrollController _albumScrollController = ScrollController();
  final ScrollController _clipScrollController = ScrollController();

  @override
  void dispose() {
    _albumScrollController.dispose();
    _clipScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    videoManager = Provider.of<VideoManager>(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifyAlbumDetailVisibilityIfNeeded();
      _notifyCreateProjectButtonVisibilityIfNeeded();
      widget.onSelectedClipPathsChanged?.call(List<String>.from(_selectedClipPaths));
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (_previewingPath != null)
          setState(() => _previewingPath = null);
        else if (_isClipSelectionMode)
          setState(() {
            _isClipSelectionMode = false;
            _selectedClipPaths.clear();
          });
        else if (_isAlbumSelectionMode)
          setState(() {
            _isAlbumSelectionMode = false;
            _selectedAlbumNames.clear();
          });
        else if (_isInAlbumDetail)
          setState(() => _isInAlbumDetail = false);
      },
      child: _isInAlbumDetail ? _buildDetailView() : _buildLibraryTab(),
    );
  }

  Future<void> _loadClipsFromCurrentAlbum() async {
    setState(() {
      videoManager.recordedVideoPaths.clear();
    });
    await videoManager.loadClipsFromCurrentAlbum();
    if (mounted) setState(() {});
  }

  Widget _buildLibraryTab() {
    final allAlbums = videoManager.clipAlbums; // Vlog 제외 조건 삭제
    final selectableAlbums = allAlbums
        .where((a) => a != "일상" && a != "휴지통")
        .toList();
    final bool isAll =
        _selectedAlbumNames.length == selectableAlbums.length &&
        _selectedAlbumNames.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8), // App BG Color
      body: GestureDetector(
        key: _albumGridKey, // Restore Key to GestureDetector
        onScaleStart: (d) {
          _isZoomingLocked = false;
          if (_isAlbumSelectionMode && d.pointerCount == 1) {
            _startDragSelection(d.focalPoint, false);
          }
        },
        onScaleUpdate: (d) => _handleScaleUpdate(d, false),
        onScaleEnd: (_) => _dragStartIndex = null,
        child: CustomScrollView(
          controller: _albumScrollController,
          physics:
              const AlwaysScrollableScrollPhysics(), // Ensure scrolling works
          slivers: [
            // Library Header
            SliverAppBar(
              backgroundColor: const Color(0xFFF4F6F8),
              surfaceTintColor: Colors.transparent,
              pinned: true,
              floating: false,
              centerTitle: false,
              title: Text(
                _isAlbumSelectionMode
                    ? "${_selectedAlbumNames.length}개 선택됨"
                    : "Library",
                style: const TextStyle(
                  color: Color(0xFF303236),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.1,
                  height: 1,
                ),
              ),
              toolbarHeight: 88,
              actions: [
                if (_isAlbumSelectionMode)
                  IconButton(
                    icon: Icon(
                      isAll ? Icons.check_box : Icons.check_box_outline_blank,
                      color: Colors.black,
                    ),
                    onPressed: _toggleSelectAllAlbums,
                  )
                else ...[
                  IconButton(
                    key: widget.keyPickMedia,
                    icon: const Icon(Icons.add, color: Colors.black, size: 21),
                    onPressed: _showCreateAlbumDialog,
                  ),
                ],
              ],
            ),

            // Album Grid
            allAlbums.isEmpty
                ? SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.folder_open, color: Colors.grey, size: 60),
                          SizedBox(height: 16),
                          Text(
                            "No albums yet.\nAdd an album to start!",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _gridColumnCount,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 20,
                        childAspectRatio: 0.75,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final albumName = allAlbums[index];
                        final clipCount =
                            videoManager.albumCounts[albumName] ?? 0;
                        final isSelected = _selectedAlbumNames.contains(
                          albumName,
                        );
                        final canSelect =
                            albumName != "일상" &&
                            albumName != "휴지통"; // 'Vlog' 제외 조건 삭제

                        final tile = MediaWidgets.buildFolderGridItem(
                          folderName: albumName,
                          clipCount: clipCount,
                          isSelected: isSelected,
                          canSelect: canSelect,
                          isSelectionMode: _isAlbumSelectionMode,
                          gridColumnCount: _gridColumnCount,
                          onTap: () {
                            if (_isAlbumSelectionMode) {
                              if (!canSelect) return;
                              setState(() {
                                if (isSelected) {
                                  _selectedAlbumNames.remove(albumName);
                                } else {
                                  _selectedAlbumNames.add(albumName);
                                }
                              });
                            } else {
                              setState(() {
                                videoManager.currentAlbum = albumName;
                                _isInAlbumDetail = true;
                                _selectedClipPaths.clear();
                                _isClipSelectionMode = false;
                              });
                              _loadClipsFromCurrentAlbum();
                            }
                          },
                          onLongPress: canSelect
                              ? () {
                                  setState(() {
                                    _isAlbumSelectionMode = true;
                                    if (isSelected) {
                                      _selectedAlbumNames.remove(albumName);
                                    } else {
                                      _selectedAlbumNames.add(albumName);
                                    }
                                  });
                                  hapticFeedback();
                                }
                              : null,
                          getIcon: _getAlbumIcon,
                          getColor: _getAlbumColor,
                        );

                        if (albumName == '일상') {
                          return KeyedSubtree(
                            key: widget.keyAlbumGridItem,
                            child: tile,
                          );
                        }
                        return tile;
                      }, childCount: allAlbums.length),
                    ),
                  ),
          ],
        ),
      ),
      floatingActionButton:
          _isAlbumSelectionMode && _selectedAlbumNames.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _handleAlbumBatchDelete,
              backgroundColor: Colors.redAccent,
              icon: const Icon(Icons.delete),
              label: const Text("Delete"),
            )
          : null,
    );
  }

  IconData _getAlbumIcon(String albumName) {
    if (albumName == "일상") return Icons.home;
    if (albumName == "휴지통") return Icons.delete;
    return Icons.folder;
  }

  Color _getAlbumColor(String albumName) {
    if (albumName == "일상") return Colors.blue;
    if (albumName == "휴지통") return const Color(0xFF7D8594);
    return const Color(0xFFFFD66B);
  }

  Widget _buildDetailView() {
    final visibleClipPaths = videoManager.recordedVideoPaths
        .where(
          (path) =>
              videoManager.isClipVisibleByStorageFilter(path, _storageFilter),
        )
        .toList();

    // Determine subtitle
    final int count = visibleClipPaths.length;
    final String subtitle = "$count Clips";
    final selectionState = _resolveSelectionActionState();

    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        key: _clipGridKey, // Restore Key to GestureDetector
        onScaleStart: (d) {
          _isZoomingLocked = false;
          if (_isClipSelectionMode && d.pointerCount == 1) {
            _startDragSelection(d.focalPoint, true);
          }
        },
        onScaleUpdate: (d) => _handleScaleUpdate(d, true),
        onScaleEnd: (_) => _dragStartIndex = null,
        child: CustomScrollView(
          controller: _clipScrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Detail Header
            SliverAppBar(
              backgroundColor: Colors.white.withOpacity(0.9),
              surfaceTintColor: Colors.transparent,
              pinned: true,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
                onPressed: () {
                  if (_isClipSelectionMode) {
                    setState(() {
                      _isClipSelectionMode = false;
                      _selectedClipPaths.clear();
                    });
                  } else {
                    setState(() => _isInAlbumDetail = false);
                  }
                },
              ),
              centerTitle: false,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isClipSelectionMode
                        ? "${_selectedClipPaths.length}개 선택됨"
                        : "${videoManager.currentAlbum} $count",
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (!_isClipSelectionMode)
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
              actions: [
                if (!_isClipSelectionMode)
                  IconButton(
                    key: widget.keyPickMedia,
                    icon: const Icon(
                      Icons.add_photo_alternate_outlined,
                      color: Colors.black,
                    ),
                    onPressed: () => widget.onPickMedia(''),
                  ),
                if (_isClipSelectionMode)
                  TextButton(
                    onPressed: _toggleSelectAllClips,
                    child: const Text(
                      'Select All',
                      style: TextStyle(
                        color: Color(0xFF1A73E8),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    _buildStorageFilterChip('all', '전체'),
                    _buildStorageFilterChip('device', '기기'),
                  ],
                ),
              ),
            ),

            // Clip Grid
            if (visibleClipPaths.isEmpty)
              SliverFillRemaining(
                child: Center(
                  key: widget.keyFirstClip,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.photo_library, size: 60, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        "No clips.\nRecord something!",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 210),
                sliver: SliverGrid(
                  // key: _clipGridKey removed from here
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _gridColumnCount,
                    crossAxisSpacing: 3,
                    mainAxisSpacing: 3,
                    childAspectRatio: 1.0,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final path = visibleClipPaths[index];
                    final isSelected = _selectedClipPaths.contains(path);
                    final int selectIdx = _selectedClipPaths.indexOf(path);
                    final item = MediaWidgets.buildMediaGridItem(
                      path: path,
                      isSelected: isSelected,
                      selectIndex: selectIdx,
                      isSelectionMode: _isClipSelectionMode,
                      gridColumnCount: _gridColumnCount,
                      benchmarkStyle: true,
                      showDurationBadge: true,
                      statusBadge: videoManager.getClipStatusBadge(path),
                      isFavorite: videoManager.favorites.contains(path),
                      getDuration: videoManager.getVideoDuration,
                      onTap: () {
                        if (_isClipSelectionMode) {
                          setState(() {
                            if (isSelected) {
                              _selectedClipPaths.remove(path);
                            } else {
                              _selectedClipPaths.add(path);
                            }
                          });
                        } else {
                          setState(() => _previewingPath = path);
                        }
                      },
                      onLongPress: () {
                        setState(() {
                          _isClipSelectionMode = true;
                          _dragStartIndex = index;
                          _isDragAdding = !isSelected;
                          if (_isDragAdding) {
                            _selectedClipPaths.add(path);
                          } else {
                            _selectedClipPaths.remove(path);
                          }
                        });
                        hapticFeedback();
                      },
                      getThumbnail: videoManager.getThumbnail,
                    );

                    if (index == 0) {
                      return KeyedSubtree(
                        key: widget.keyFirstClip,
                        child: item,
                      );
                    }
                    return item;
                  }, childCount: visibleClipPaths.length),
                ),
              ),
          ],
        ),
      ),
      // Bottom Navigation Eliminated

      // Bottom Navigation (Visual Only)

      // Floating Actions (Multi-Select)
      // Magic Brush (Project Create) FAB
      floatingActionButton:
          (_isClipSelectionMode && _selectedClipPaths.isNotEmpty)
          ? (videoManager.currentAlbum == "휴지통"
                ? MediaWidgets.buildActionPanel(
                    isTrashMode: true,
                    onCreateProject: null,
                    onFavorite: null,
                    onMove: () {},
                    onCopy: () {},
                    onDelete: _handleClipBatchDelete,
                    onRestore: () async {
                      for (var path in _selectedClipPaths) {
                        await videoManager.restoreClip(path);
                      }
                      setState(() {
                        _isClipSelectionMode = false;
                        _selectedClipPaths.clear();
                      });
                      await _loadClipsFromCurrentAlbum();
                      hapticFeedback();
                    },
                  )
                : MediaWidgets.buildLibrarySelectionPanel(
                    transferIcon: _transferIconForSelectionState(
                      selectionState,
                    ),
                    onTransfer: _transferHandlerForSelectionState(
                      selectionState,
                    ),
                    showTransferButton: false,
                    onCreateProject: _selectedClipPaths.length < 2
                        ? null
                        : () {
                            if (_selectedClipPaths.length < 2) return;
                            final pathsCopy = List<String>.from(
                              _selectedClipPaths,
                            );
                            widget.onMerge(pathsCopy);
                            setState(() {
                              _isClipSelectionMode = false;
                              _selectedClipPaths.clear();
                            });
                          },
                    createProjectButtonKey: widget.keyCreateProject,
                    onFavorite: () {
                      videoManager.toggleFavoritesBatch(_selectedClipPaths);
                      setState(() {
                        _isClipSelectionMode = false;
                        _selectedClipPaths.clear();
                      });
                      hapticFeedback();
                    },
                    onCopy: () => _handleMoveOrCopy(false),
                    onMove: () => _handleMoveOrCopy(true),
                    onDelete: _handleClipBatchDelete,
                  ))
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,

      // Preview Overlay
      bottomSheet: _previewingPath != null
          ? SizedBox(
              height: MediaQuery.of(context).size.height,
              child: VideoPreviewWidget(
                filePath: _previewingPath!,
                favorites: videoManager.favorites,
                isTrashMode: videoManager.currentAlbum == "휴지통",
                onToggleFav: (p) {
                  if (videoManager.favorites.contains(p)) {
                    videoManager.favorites.remove(p);
                  } else {
                    videoManager.favorites.add(p);
                  }
                  setState(() {});
                  hapticFeedback();
                },
                onRestore: (p) async {
                  await videoManager.restoreClip(p);
                  setState(() => _previewingPath = null);
                  await _loadClipsFromCurrentAlbum();
                },
                onDelete: (p) async {
                  await _handleSingleClipDelete(p);
                },
                onClose: () => setState(() => _previewingPath = null),
              ),
            )
          : null,
    );
  }

  // --- [제스처 처리] ---

  void _startDragSelection(Offset position, bool isClip) {
    final targetList = isClip
        ? videoManager.recordedVideoPaths
        : videoManager.clipAlbums;

    double topPad = MediaQuery.of(context).padding.top + kToolbarHeight;
    final controller = isClip ? _clipScrollController : _albumScrollController;
    double currentScroll = controller.hasClients ? controller.offset : 0.0;

    MediaSelectionHelper.startDragSelection(
      focalPoint: position,
      gridKey: isClip ? _clipGridKey : _albumGridKey,
      columnCount: _gridColumnCount,
      childAspectRatio: isClip ? 1.0 : (_gridColumnCount == 5 ? 0.7 : 0.85),
      targetList: targetList,
      currentSelection: isClip ? _selectedClipPaths : _selectedAlbumNames,
      scrollOffset: currentScroll,
      topPadding: topPad,
      onSelectionChanged: (item, isAdding) {
        setState(() {
          if (isClip) {
            if (isAdding) {
              _selectedClipPaths.add(item);
            } else {
              _selectedClipPaths.remove(item);
            }
          } else {
            if (isAdding) {
              _selectedAlbumNames.add(item);
            } else {
              _selectedAlbumNames.remove(item);
            }
          }
        });
      },
      onDragStarted: (index, isAdding) {
        _dragStartIndex = index;
        _isDragAdding = isAdding;
      },
      canSelectItem: isClip ? null : (item) => item != "일상" && item != "휴지통",
    );
  }

  void _handleScaleUpdate(ScaleUpdateDetails details, bool isClip) {
    // 줌 처리
    final newCount = MediaSelectionHelper.handleZoomGesture(
      details: details,
      currentColumnCount: _gridColumnCount,
      isZoomingLocked: _isZoomingLocked,
      onZoomChanged: (newCount) {
        setState(() {
          _gridColumnCount = newCount;
          _isZoomingLocked = true;
        });
      },
    );

    if (newCount != null) return;

    // 드래그 선택 처리
    final isActive = isClip ? _isClipSelectionMode : _isAlbumSelectionMode;
    if (!isActive) return;

    final targetList = isClip
        ? videoManager.recordedVideoPaths
        : videoManager.clipAlbums;

    double topPad = MediaQuery.of(context).padding.top + kToolbarHeight;
    final controller = isClip ? _clipScrollController : _albumScrollController;
    double currentScroll = controller.hasClients ? controller.offset : 0.0;

    setState(() {
      MediaSelectionHelper.updateDragSelection(
        focalPoint: details.focalPoint,
        gridKey: isClip ? _clipGridKey : _albumGridKey,
        columnCount: _gridColumnCount,
        childAspectRatio: isClip ? 1.0 : (_gridColumnCount == 5 ? 0.7 : 0.85),
        targetList: targetList,
        currentSelection: isClip ? _selectedClipPaths : _selectedAlbumNames,
        dragStartIndex: _dragStartIndex ?? -1,
        isDragAdding: _isDragAdding,
        scrollOffset: currentScroll,
        topPadding: topPad,
        // onIndexProcessed removed from helper
        canSelectItem: isClip ? null : (item) => item != "일상" && item != "휴지통",
      );
    });
  }

  void _toggleSelectAllAlbums() {
    setState(() {
      final selectable = videoManager.clipAlbums
          .where((a) => a != "일상" && a != "휴지통")
          .toList();
      if (_selectedAlbumNames.length == selectable.length) {
        _selectedAlbumNames.clear();
      } else {
        _selectedAlbumNames = Set.from(selectable);
      }
    });
    hapticFeedback();
  }

  void _toggleSelectAllClips() {
    final visibleClipPaths = videoManager.recordedVideoPaths
        .where(
          (path) =>
              videoManager.isClipVisibleByStorageFilter(path, _storageFilter),
        )
        .toList();
    setState(() {
      if (_selectedClipPaths.length == visibleClipPaths.length) {
        _selectedClipPaths.clear();
      } else {
        _selectedClipPaths = List.from(visibleClipPaths);
      }
    });
    hapticFeedback();
  }

  _SelectionActionState _resolveSelectionActionState() {
    if (_selectedClipPaths.isEmpty) return _SelectionActionState.mixed;

    var cloudCount = 0;

    for (final path in _selectedClipPaths) {
      if (videoManager.isClipCloudSynced(path)) {
        cloudCount++;
      }
    }

    if (cloudCount == 0) return _SelectionActionState.local;
    if (cloudCount == _selectedClipPaths.length)
      return _SelectionActionState.cloud;
    return _SelectionActionState.mixed;
  }

  IconData _transferIconForSelectionState(_SelectionActionState state) {
    switch (state) {
      case _SelectionActionState.local:
        return Icons.cloud_upload_rounded;
      case _SelectionActionState.cloud:
        return Icons.download_for_offline_rounded;
      case _SelectionActionState.mixed:
        return Icons.sync_disabled_rounded;
    }
  }

  VoidCallback? _transferHandlerForSelectionState(_SelectionActionState state) {
    if (AuthService().isGuest) {
      return _showGuestCloudActionBlockedToast;
    }

    switch (state) {
      case _SelectionActionState.local:
        return _moveSelectedLocalToCloud;
      case _SelectionActionState.cloud:
        return _moveSelectedCloudToLocal;
      case _SelectionActionState.mixed:
        return null;
    }
  }

  void _showGuestCloudActionBlockedToast() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('게스트 모드에서는 클라우드 이동/복원이 비활성입니다. 로그인 후 이용해 주세요.'),
      ),
    );
  }

  Future<void> _moveSelectedLocalToCloud() async {
    final targets = List<String>.from(_selectedClipPaths);
    if (targets.isEmpty) return;

    if (AuthService().isGuest) {
      _showGuestCloudActionBlockedToast();
      return;
    }

    setState(() {
      _isClipSelectionMode = false;
      _selectedClipPaths.clear();
    });

    for (final path in targets) {
      videoManager.markClipTransferPendingUpload(path);
    }

    unawaited(_moveSelectedLocalToCloudInBackground(targets));
  }

  Future<void> _moveSelectedLocalToCloudInBackground(
    List<String> targets,
  ) async {
    var success = 0;
    var failed = 0;
    String? firstErrorCode;
    String? firstErrorCopy;

    for (final path in targets) {
      try {
        if (videoManager.isClipCloudSynced(path)) {
          videoManager.markClipTransferUploadFailed(path);
          failed++;
          continue;
        }
        final file = File(path);
        if (!await file.exists()) {
          videoManager.markClipTransferUploadFailed(path);
          failed++;
          continue;
        }

        final videoId = await _cloudService.uploadVideoImmediate(
          videoFile: file,
          albumName: videoManager.currentAlbum,
          isFavorite: videoManager.favorites.contains(path),
          localPath: path,
        );

        if (videoId == null) {
          firstErrorCode ??= _cloudService.lastImmediateUploadErrorCode;
          firstErrorCopy ??= _cloudService.lastImmediateUploadErrorCopy;
          videoManager.markClipTransferUploadFailed(path);
          failed++;
          continue;
        }

        // UX 수정:
        // "클라우드로 이동" 이후 Library에서 항목이 완전히 사라지는 문제를 방지하기 위해
        // 로컬 파일을 즉시 삭제하지 않고, 클라우드 동기화 상태만 마킹한다.
        // (필요 시 별도 '기기에서 삭제' 액션으로 정리)
        await videoManager.markClipCloudSynced(path);
        videoManager.clearClipTransferUiState(path);
        success++;
      } catch (_) {
        videoManager.markClipTransferUploadFailed(path);
        failed++;
      }
    }

    final text = failed == 0
        ? '클라우드로 $success개 이동 완료'
        : '클라우드 이동 완료 $success개, 실패 $failed개';
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }

    if (failed > 0 && mounted) {
      final guide = _cloudMoveFailureGuide(
        errorCode: firstErrorCode,
        fallback: firstErrorCopy,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(guide),
          duration: const Duration(seconds: 6),
          action: (firstErrorCode == 'cloud_api_disabled')
              ? SnackBarAction(
                  label: '복구절차',
                  onPressed: _showCloudApiRecoveryDialog,
                )
              : null,
        ),
      );
    }
  }

  String _cloudMoveFailureGuide({
    required String? errorCode,
    required String? fallback,
  }) {
    switch (errorCode) {
      case 'guest_mode_blocked':
        return '게스트 모드에서는 클라우드 이동/복원이 비활성입니다. 로그인 후 이용해 주세요.';
      case 'cloud_api_disabled':
        return '서버 설정 문제로 클라우드 이동이 막혀 있어요. Firestore API 활성화 후 다시 시도해주세요.';
      case 'permission_denied':
        return '권한 문제로 클라우드 이동에 실패했어요. 로그인/규칙 설정을 확인해주세요.';
      case 'storage_limit':
      case 'quota_exceeded':
        return '저장 용량 제한으로 클라우드 이동에 실패했어요. 용량 정리 후 다시 시도해주세요.';
      case 'auth_required':
        return '로그인이 필요해요. 로그인 후 다시 시도해주세요.';
      default:
        return fallback ?? '일부 항목의 클라우드 이동이 실패했어요. 잠시 후 다시 시도해주세요.';
    }
  }

  void _showCloudApiRecoveryDialog() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('클라우드 설정 복구 절차'),
        content: const Text(
          '1) Firebase 프로젝트에서 Cloud Firestore API를 활성화하세요.\n'
          '2) 활성화 직후에는 전파까지 수 분 소요될 수 있어요.\n'
          '3) 앱을 다시 실행하고 클라우드 이동을 재시도하세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _moveSelectedCloudToLocal() async {
    final targets = List<String>.from(_selectedClipPaths);
    if (targets.isEmpty) return;

    if (AuthService().isGuest) {
      _showGuestCloudActionBlockedToast();
      return;
    }

    setState(() {
      _isClipSelectionMode = false;
      _selectedClipPaths.clear();
    });

    for (final path in targets) {
      videoManager.markClipTransferPendingDownload(path);
    }

    unawaited(_moveSelectedCloudToLocalInBackground(targets));
  }

  Future<void> _moveSelectedCloudToLocalInBackground(
    List<String> targets,
  ) async {
    var success = 0;
    var failed = 0;

    for (final path in targets) {
      try {
        if (!videoManager.isClipCloudSynced(path)) {
          videoManager.markClipTransferDownloadFailed(path);
          failed++;
          continue;
        }

        final ok = await _cloudService.deleteVideoByLocalPath(path);
        if (!ok) {
          videoManager.markClipTransferDownloadFailed(path);
          failed++;
          continue;
        }

        await videoManager.unmarkClipCloudSynced(path);
        videoManager.clearClipTransferUiState(path);
        success++;
      } catch (_) {
        videoManager.markClipTransferDownloadFailed(path);
        failed++;
      }
    }

    final text = failed == 0
        ? '로컬로 $success개 이동 완료'
        : '로컬 이동 완료 $success개, 실패 $failed개';
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Widget _buildStorageFilterChip(String value, String label) {
    final selected = _storageFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _storageFilter = value;
          _selectedClipPaths.clear();
          _isClipSelectionMode = false;
        });
      },
    );
  }

  // --- [액션 핸들러] ---

  void _showCreateAlbumDialog() async {
    String? name = await MediaDialogs.showCreateAlbumDialog(context: context);
    if (name != null && name.trim().isNotEmpty) {
      if (videoManager.clipAlbums.contains(name.trim())) return;
      await videoManager.createNewClipAlbum(name.trim());
      widget.onRefreshData();
    }
  }

  Future<void> _handleAlbumBatchDelete() async {
    bool? ok = await MediaDialogs.showConfirmDialog(
      context: context,
      title: "앨범 삭제",
      content: "앨범은 삭제되고 클립은 휴지통으로 이동합니다.",
    );
    if (ok == true) {
      await videoManager.deleteClipAlbums(_selectedAlbumNames);
      if (!mounted) return;
      setState(() {
        _isAlbumSelectionMode = false;
        _selectedAlbumNames.clear();
      });
      await videoManager.initAlbumSystem();
      if (mounted) setState(() {});
    }
  }

  Future<void> _handleClipBatchDelete() async {
    bool isTrash = videoManager.currentAlbum == "휴지통";
    if (isTrash) {
      bool? ok = await MediaDialogs.showConfirmDialog(
        context: context,
        title: "영구 삭제",
        content: "선택한 클립을 모두 삭제할까요?",
      );
      if (ok != true) return;
      await videoManager.deleteClipsBatch(_selectedClipPaths);
    } else {
      for (var path in _selectedClipPaths) {
        await videoManager.moveToTrash(path);
      }
    }
    if (!mounted) return;
    await _loadClipsFromCurrentAlbum();
    if (!mounted) return;
    setState(() {
      _isClipSelectionMode = false;
      _selectedClipPaths.clear();
    });
    hapticFeedback();
  }

  Future<void> _handleSingleClipDelete(String path) async {
    bool isTrash = videoManager.currentAlbum == "휴지통";
    try {
      if (isTrash) {
        bool? ok = await MediaDialogs.showConfirmDialog(
          context: context,
          title: "영구 삭제",
          content: "이 클립을 삭제할까요?",
        );
        if (ok != true) return;
        await videoManager.deletePermanently(path);
      } else {
        await videoManager.moveToTrash(path);
      }
      if (!mounted) return;
      setState(() => _previewingPath = null);
      await _loadClipsFromCurrentAlbum();
      hapticFeedback();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('클립 삭제 중 오류가 발생했습니다.')));
    }
  }

  Future<void> _handleMoveOrCopy(bool isMove) async {
    await videoManager.initAlbumSystem();
    if (!mounted) return;

    final String? result = await MediaDialogs.showMoveOrCopyDialog(
      context: context,
      isMove: isMove,
      folderList: videoManager.clipAlbums,
      currentFolder: videoManager.currentAlbum,
      excludeFolders: ["휴지통"],
      itemSubtitleBuilder: (albumName) {
        final count = videoManager.albumCounts[albumName] ?? 0;
        return '$count clips';
      },
    );

    if (result == null) return;

    String targetAlbum = result;

    if (result == "NEW") {
      if (!mounted) return;
      String? name = await MediaDialogs.showCreateAlbumDialog(context: context);
      if (name == null || name.trim().isEmpty) return;
      targetAlbum = name.trim();
      await videoManager.createNewClipAlbum(targetAlbum);
    }

    await videoManager.executeTransfer(targetAlbum, isMove, _selectedClipPaths);
    await _loadClipsFromCurrentAlbum();
    if (!mounted) return;

    setState(() {
      _selectedClipPaths.clear();
      _isClipSelectionMode = false;
    });

    hapticFeedback();
  }
}
