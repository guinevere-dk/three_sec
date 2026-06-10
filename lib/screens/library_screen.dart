import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/video_widgets.dart';
import '../widgets/media_widgets.dart';
import '../widgets/media_dialogs.dart';
import '../utils/haptics.dart';
import '../utils/media_selection_helper.dart';
import '../managers/video_manager.dart';
import '../managers/user_status_manager.dart';
import '../services/cloud_service.dart';
import '../services/auth_service.dart';
import '../theme/moa_design_tokens.dart';
import 'subscription_management_screen.dart';

enum LibraryClipTransferAction {
  upload,
  download,
  cloudDone,
  progress,
  disabled,
}

LibraryClipTransferAction resolveLibraryClipTransferAction(
  Iterable<ClipStorageState> states,
) {
  final list = states.toList(growable: false);
  if (list.isEmpty) return LibraryClipTransferAction.disabled;

  if (list.contains(ClipStorageState.pendingUpload)) {
    return LibraryClipTransferAction.progress;
  }

  final uploadable = list.every(
    (state) =>
        state == ClipStorageState.localOnly ||
        state == ClipStorageState.failedUpload,
  );
  if (uploadable) return LibraryClipTransferAction.upload;

  final downloadable = list.every(
    (state) =>
        state == ClipStorageState.cloudOnly ||
        state == ClipStorageState.failedDownload,
  );
  if (downloadable) return LibraryClipTransferAction.download;

  final cloudSyncedLocal = list.every(
    (state) => state == ClipStorageState.cloudSyncedLocal,
  );
  if (cloudSyncedLocal) return LibraryClipTransferAction.cloudDone;

  return LibraryClipTransferAction.disabled;
}

IconData libraryClipTransferIconForAction(LibraryClipTransferAction action) {
  switch (action) {
    case LibraryClipTransferAction.upload:
      return Icons.cloud_upload_rounded;
    case LibraryClipTransferAction.download:
      return Icons.download_rounded;
    case LibraryClipTransferAction.cloudDone:
      return Icons.cloud_done_rounded;
    case LibraryClipTransferAction.progress:
      return Icons.sync_rounded;
    case LibraryClipTransferAction.disabled:
      return Icons.download_for_offline_rounded;
  }
}

bool shouldShowLibraryClipTransferButton({
  required LibraryClipTransferAction action,
  required bool isGuest,
  required bool canStartNewCloudWrite,
  required bool canReadExistingCloudClips,
}) {
  if (isGuest) return false;
  switch (action) {
    case LibraryClipTransferAction.upload:
      return canStartNewCloudWrite;
    case LibraryClipTransferAction.download:
      return canReadExistingCloudClips;
    case LibraryClipTransferAction.cloudDone:
    case LibraryClipTransferAction.progress:
    case LibraryClipTransferAction.disabled:
      return canStartNewCloudWrite || canReadExistingCloudClips;
  }
}

bool isUploadMoveEligibleFromPrePendingState(ClipStorageState? state) {
  return state == ClipStorageState.localOnly ||
      state == ClipStorageState.failedUpload;
}

Map<String, int> clipStorageStateCountsForStates(
  Iterable<ClipStorageState> states,
) {
  final counts = <String, int>{
    'localFileCount': 0,
    'localOnlyCount': 0,
    'cloudSyncedLocalCount': 0,
    'cloudOnlyCount': 0,
    'pendingUploadCount': 0,
    'failedUploadCount': 0,
    'failedDownloadCount': 0,
    'uploadableCount': 0,
  };

  for (final state in states) {
    switch (state) {
      case ClipStorageState.localOnly:
        counts['localOnlyCount'] = counts['localOnlyCount']! + 1;
        counts['uploadableCount'] = counts['uploadableCount']! + 1;
        break;
      case ClipStorageState.pendingUpload:
        counts['pendingUploadCount'] = counts['pendingUploadCount']! + 1;
        break;
      case ClipStorageState.cloudSyncedLocal:
        counts['cloudSyncedLocalCount'] = counts['cloudSyncedLocalCount']! + 1;
        break;
      case ClipStorageState.cloudOnly:
        counts['cloudOnlyCount'] = counts['cloudOnlyCount']! + 1;
        break;
      case ClipStorageState.failedUpload:
        counts['failedUploadCount'] = counts['failedUploadCount']! + 1;
        counts['uploadableCount'] = counts['uploadableCount']! + 1;
        break;
      case ClipStorageState.failedDownload:
        counts['failedDownloadCount'] = counts['failedDownloadCount']! + 1;
        break;
    }
  }

  return Map<String, int>.unmodifiable(counts);
}

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
  static const String _traceTag = '[LibraryTrace]';
  static const EdgeInsets _clipGridPadding = EdgeInsets.fromLTRB(8, 8, 8, 210);
  static const double _clipGridSpacing = 3.0;
  static const double _clipFilterBarEstimatedExtent = 56.0;

  bool _isInAlbumDetail = false;
  bool _isClipSelectionMode = false;
  bool _isAlbumSelectionMode = false;
  bool _isDragAdding = true;
  int? _dragStartIndex;

  int _gridColumnCount = 3;
  bool _isZoomingLocked = false;

  String? _previewingPath;
  String _storageFilter = 'all';
  bool _showFavoritesOnly = false;
  String? _loadingAlbumName;
  int? _loadingAlbumExpectedCount;

  final GlobalKey _clipGridKey = GlobalKey(debugLabel: 'clipGrid');
  final GlobalKey _albumGridKey = GlobalKey(debugLabel: 'albumGrid');

  List<String> _selectedClipPaths = [];
  Set<String> _selectedAlbumNames = {};

  late VideoManager videoManager;
  final CloudService _cloudService = CloudService();
  final UserStatusManager _userStatusManager = UserStatusManager();
  bool _lastAlbumDetailVisible = false;
  bool _lastCreateProjectButtonVisible = false;
  String? _lastDetailRenderSignature;
  String? _lastTransferRenderSignature;
  final Set<String> _thumbnailLoggedLoadingPaths = <String>{};
  final Set<String> _thumbnailLoggedReadyPaths = <String>{};
  final Set<String> _thumbnailLoggedErrorPaths = <String>{};

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
      await _userStatusManager.initialize();
      await videoManager.initAlbumSystem();
      await videoManager.syncCloudMetadataToLibrary(trigger: 'library_init');
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
    _showFavoritesOnly = false;
    _loadingAlbumName = null;
    _loadingAlbumExpectedCount = null;
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
      widget.onSelectedClipPathsChanged?.call(
        List<String>.from(_selectedClipPaths),
      );
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

  Future<void> _loadClipsFromCurrentAlbum([String? expectedAlbum]) async {
    final album = expectedAlbum ?? videoManager.currentAlbum;
    final startedAt = DateTime.now();
    debugPrint('$_traceTag load_clips_start album=$album');
    setState(() {
      _loadingAlbumName = album;
      _loadingAlbumExpectedCount = videoManager.albumCounts[album] ?? 0;
      videoManager.recordedVideoPaths = <String>[];
    });
    try {
      await videoManager.loadClipsFromAlbum(album);
      final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      if (!mounted || !_isInAlbumDetail || videoManager.currentAlbum != album) {
        debugPrint(
          '$_traceTag load_clips_stale_ignored album=$album '
          'current=${videoManager.currentAlbum} elapsedMs=$elapsedMs',
        );
        return;
      }
      debugPrint(
        '$_traceTag load_clips_success album=$album '
        'count=${videoManager.recordedVideoPaths.length} elapsedMs=$elapsedMs',
      );
      setState(() {
        if (_loadingAlbumName == album) {
          _loadingAlbumName = null;
          _loadingAlbumExpectedCount = null;
        }
      });
    } catch (error) {
      final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      debugPrint(
        '$_traceTag load_clips_error album=$album elapsedMs=$elapsedMs '
        'errorType=${error.runtimeType}',
      );
      if (mounted && _loadingAlbumName == album) {
        setState(() {
          _loadingAlbumName = null;
          _loadingAlbumExpectedCount = null;
        });
      }
      rethrow;
    }
  }

  void _traceDetailRender(
    List<String> visibleClipPaths, {
    required int displayCount,
    required bool isLoading,
  }) {
    final firstPath = visibleClipPaths.isNotEmpty
        ? visibleClipPaths.first
        : 'none';
    final lastPath = visibleClipPaths.isNotEmpty
        ? visibleClipPaths.last
        : 'none';
    final signature = [
      videoManager.currentAlbum,
      _storageFilter,
      _showFavoritesOnly,
      _gridColumnCount,
      visibleClipPaths.length,
      displayCount,
      isLoading,
      firstPath,
      lastPath,
    ].join('|');
    if (_lastDetailRenderSignature == signature) return;
    _lastDetailRenderSignature = signature;
    debugPrint(
      '$_traceTag clip_list_render album=${videoManager.currentAlbum} '
      'filter=$_storageFilter favoritesOnly=$_showFavoritesOnly '
      'count=$displayCount visibleCount=${visibleClipPaths.length} '
      'loading=$isLoading grid=$_gridColumnCount '
      'first=$firstPath last=$lastPath',
    );
  }

  Future<Uint8List?> _traceThumbnailRequest(String path, int index) async {
    if (_thumbnailLoggedLoadingPaths.add(path)) {
      debugPrint(
        '$_traceTag thumbnail_request album=${videoManager.currentAlbum} '
        'index=$index path=<redacted-path>',
      );
      debugPrint(
        '[thumbnailLog] {"event":"ui_request","operation":"LibraryScreen.getThumbnail",'
        '"status":"request","album":"${videoManager.currentAlbum}",'
        '"index":$index,"videoPath":"<redacted-path>"}',
      );
    }
    try {
      final thumbnail = await videoManager.getThumbnail(path);
      if (thumbnail == null) {
        if (_thumbnailLoggedErrorPaths.add('null:$path')) {
          debugPrint(
            '$_traceTag thumbnail_null album=${videoManager.currentAlbum} '
            'index=$index path=<redacted-path> fallback=empty_or_plugin_unavailable',
          );
          debugPrint(
            '[thumbnailLog] {"event":"ui_null","operation":"LibraryScreen.getThumbnail",'
            '"status":"null","fallback":"empty_or_plugin_unavailable",'
            '"album":"${videoManager.currentAlbum}","index":$index,"videoPath":"<redacted-path>"}',
          );
        }
      } else if (_thumbnailLoggedReadyPaths.add(path)) {
        debugPrint(
          '$_traceTag thumbnail_ready album=${videoManager.currentAlbum} '
          'index=$index bytes=${thumbnail.length} path=<redacted-path>',
        );
        debugPrint(
          '[thumbnailLog] {"event":"ui_ready","operation":"LibraryScreen.getThumbnail",'
          '"status":"ready","album":"${videoManager.currentAlbum}",'
          '"index":$index,"bytes":${thumbnail.length},"videoPath":"<redacted-path>"}',
        );
      }
      return thumbnail;
    } catch (error) {
      if (_thumbnailLoggedErrorPaths.add('error:$path')) {
        debugPrint(
          '$_traceTag thumbnail_error album=${videoManager.currentAlbum} '
          'index=$index path=<redacted-path> errorType=${error.runtimeType}',
        );
        debugPrint(
          '[thumbnailLog] {"event":"ui_fallback","operation":"LibraryScreen.getThumbnail",'
          '"status":"fallback","reason":"exception",'
          '"album":"${videoManager.currentAlbum}","index":$index,'
          '"videoPath":"<redacted-path>","error":"${error.runtimeType}"}',
        );
      }
      rethrow;
    }
  }

  Widget _buildLibraryTab() {
    final allAlbums = videoManager.clipAlbums; // Vlog 제외 조건 삭제
    final showStandardBadge = _userStatusManager.currentTier == UserTier.free;
    final selectableAlbums = allAlbums
        .where((a) => a != "일상" && a != "휴지통")
        .toList();
    final bool isAll =
        _selectedAlbumNames.length == selectableAlbums.length &&
        _selectedAlbumNames.isNotEmpty;

    return Scaffold(
      backgroundColor: MoaDesignTokens.background,
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
              backgroundColor: MoaDesignTokens.background,
              surfaceTintColor: Colors.transparent,
              pinned: true,
              floating: false,
              centerTitle: false,
              title: Text(
                _isAlbumSelectionMode
                    ? "${_selectedAlbumNames.length}개 선택됨"
                    : "Library",
                style: const TextStyle(
                  color: MoaDesignTokens.textPrimary,
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
                      color: MoaDesignTokens.textPrimary,
                    ),
                    onPressed: _toggleSelectAllAlbums,
                  )
                else ...[
                  if (showStandardBadge) _buildStandardHeaderBadge(),
                  IconButton(
                    key: widget.keyPickMedia,
                    icon: const Icon(
                      Icons.add,
                      color: MoaDesignTokens.textPrimary,
                      size: 21,
                    ),
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
                              debugPrint(
                                '$_traceTag album_enter_tap album=$albumName '
                                'clipCount=$clipCount',
                              );
                              setState(() {
                                videoManager.currentAlbum = albumName;
                                _isInAlbumDetail = true;
                                _selectedClipPaths.clear();
                                _isClipSelectionMode = false;
                                _storageFilter = 'all';
                                _showFavoritesOnly = false;
                              });
                              _loadClipsFromCurrentAlbum(albumName);
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
              backgroundColor: MoaDesignTokens.danger,
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

  List<String> _visibleClipPathsForCurrentFilter() {
    return videoManager
        .getClipsInAlbum(videoManager.currentAlbum)
        .where(
          (path) =>
              videoManager.isClipVisibleByStorageFilter(path, _storageFilter),
        )
        .where(
          (path) =>
              !_showFavoritesOnly || videoManager.favorites.contains(path),
        )
        .toList();
  }

  Widget _buildDetailView() {
    final visibleClipPaths = _visibleClipPathsForCurrentFilter();
    final showStandardBadge = _userStatusManager.currentTier == UserTier.free;

    // Determine subtitle
    final isCurrentAlbumLoading =
        _loadingAlbumName == videoManager.currentAlbum;
    final usePendingAlbumCount =
        isCurrentAlbumLoading &&
        visibleClipPaths.isEmpty &&
        _storageFilter == 'all' &&
        !_showFavoritesOnly;
    final int count = usePendingAlbumCount
        ? (_loadingAlbumExpectedCount ?? 0)
        : visibleClipPaths.length;
    _traceDetailRender(
      visibleClipPaths,
      displayCount: count,
      isLoading: isCurrentAlbumLoading,
    );
    final String subtitle = "$count Clips";
    final selectionState = _resolveSelectionActionState();
    final showTransferButton = _shouldShowTransferButton(selectionState);
    _logTransferRenderIfChanged(
      action: selectionState,
      showTransferButton: showTransferButton,
    );

    return Scaffold(
      backgroundColor: MoaDesignTokens.background,
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
              backgroundColor: MoaDesignTokens.surface,
              surfaceTintColor: Colors.transparent,
              pinned: true,
              leading: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new,
                  color: MoaDesignTokens.textPrimary,
                ),
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
                      color: MoaDesignTokens.textPrimary,
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
                if (!_isClipSelectionMode) ...[
                  if (showStandardBadge) _buildStandardHeaderBadge(),
                  IconButton(
                    key: widget.keyPickMedia,
                    icon: const Icon(
                      Icons.add_photo_alternate_outlined,
                      color: MoaDesignTokens.textPrimary,
                    ),
                    onPressed: () => widget.onPickMedia(''),
                  ),
                ],
                if (_isClipSelectionMode)
                  TextButton(
                    onPressed: _toggleSelectAllClips,
                    child: const Text(
                      'Select All',
                      style: TextStyle(
                        color: MoaDesignTokens.accentStrong,
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
                    _buildLibraryFilterChip('all', 'All'),
                    _buildLibraryFilterChip('device', 'Local'),
                    _buildLibraryFilterChip('cloud', 'Cloud'),
                    _buildLibraryFilterChip(
                      'favorites',
                      '',
                      icon: Icons.favorite_border_rounded,
                      selectedIcon: Icons.favorite_rounded,
                    ),
                  ],
                ),
              ),
            ),

            // Clip Grid
            if (visibleClipPaths.isEmpty && isCurrentAlbumLoading)
              SliverFillRemaining(
                child: Center(
                  key: widget.keyFirstClip,
                  child: const CircularProgressIndicator(),
                ),
              )
            else if (visibleClipPaths.isEmpty)
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
                padding: _clipGridPadding,
                sliver: SliverGrid(
                  // key: _clipGridKey removed from here
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _gridColumnCount,
                    crossAxisSpacing: _clipGridSpacing,
                    mainAxisSpacing: _clipGridSpacing,
                    childAspectRatio: 1.0,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final path = visibleClipPaths[index];
                    final isSelected = _selectedClipPaths.contains(path);
                    final int selectIdx = _selectedClipPaths.indexOf(path);
                    final storageState = videoManager.getClipStorageState(path);
                    final item = MediaWidgets.buildMediaGridItem(
                      path: path,
                      isSelected: isSelected,
                      selectIndex: selectIdx,
                      isSelectionMode: _isClipSelectionMode,
                      gridColumnCount: _gridColumnCount,
                      benchmarkStyle: true,
                      showDurationBadge: true,
                      statusBadge: videoManager.getClipStatusBadge(path),
                      isCloudOnly: storageState == ClipStorageState.cloudOnly,
                      getCloudThumbnail:
                          storageState == ClipStorageState.cloudOnly &&
                              videoManager.hasCompletedCloudThumbnail(path)
                          ? videoManager.getCloudThumbnail
                          : null,
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
                        } else if (videoManager.isCloudOnlyPlaceholder(path)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Cloud 클립은 길게 눌러 선택한 뒤 다운로드 아이콘으로 복원해 주세요.',
                              ),
                            ),
                          );
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
                      getThumbnail: (path) =>
                          _traceThumbnailRequest(path, index),
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
                    showTransferButton: showTransferButton,
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
                filePaths: visibleClipPaths,
                favorites: videoManager.favorites,
                isTrashMode: videoManager.currentAlbum == "휴지통",
                onFilePathChanged: (p) => setState(() => _previewingPath = p),
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

  Widget _buildStandardHeaderBadge() {
    return InkWell(
      onTap: _openSubscriptionManagement,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        margin: const EdgeInsets.only(right: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7D6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFE7C867)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, size: 16, color: Color(0xFF9A6B00)),
          ],
        ),
      ),
    );
  }

  Future<void> _openSubscriptionManagement() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SubscriptionManagementScreen()),
    );
    await _userStatusManager.initialize();
    if (mounted) setState(() {});
  }

  void _startDragSelection(Offset position, bool isClip) {
    final targetList = isClip
        ? _visibleClipPathsForCurrentFilter()
        : videoManager.clipAlbums;

    double topPad = MediaQuery.of(context).padding.top + kToolbarHeight;
    if (isClip) {
      topPad += _clipFilterBarEstimatedExtent;
    }
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
      gridPadding: isClip ? _clipGridPadding : EdgeInsets.zero,
      crossAxisSpacing: isClip ? _clipGridSpacing : 0.0,
      mainAxisSpacing: isClip ? _clipGridSpacing : 0.0,
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
        ? _visibleClipPathsForCurrentFilter()
        : videoManager.clipAlbums;

    double topPad = MediaQuery.of(context).padding.top + kToolbarHeight;
    if (isClip) {
      topPad += _clipFilterBarEstimatedExtent;
    }
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
        gridPadding: isClip ? _clipGridPadding : EdgeInsets.zero,
        crossAxisSpacing: isClip ? _clipGridSpacing : 0.0,
        mainAxisSpacing: isClip ? _clipGridSpacing : 0.0,
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
    final visibleClipPaths = videoManager
        .getClipsInAlbum(videoManager.currentAlbum)
        .where(
          (path) =>
              videoManager.isClipVisibleByStorageFilter(path, _storageFilter),
        )
        .where(
          (path) =>
              !_showFavoritesOnly || videoManager.favorites.contains(path),
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

  LibraryClipTransferAction _resolveSelectionActionState() {
    return resolveLibraryClipTransferAction(
      _selectedClipPaths.map(videoManager.getClipStorageState),
    );
  }

  Map<String, int> _selectedStorageStateCounts() {
    return videoManager.getStorageStateDebugCounts(paths: _selectedClipPaths);
  }

  String _transferBranchName(LibraryClipTransferAction action) {
    switch (action) {
      case LibraryClipTransferAction.upload:
        return 'upload_move';
      case LibraryClipTransferAction.download:
        return 'download_move';
      case LibraryClipTransferAction.cloudDone:
        return 'cloud_done';
      case LibraryClipTransferAction.progress:
        return 'progress';
      case LibraryClipTransferAction.disabled:
        return 'disabled';
    }
  }

  void _logLibraryTransfer(
    String event, {
    required LibraryClipTransferAction action,
    required String branch,
    required bool handlerInvoked,
    bool? showTransferButton,
  }) {
    final counts = _selectedStorageStateCounts();
    final canStartNewCloudWrite = _userStatusManager.canStartNewCloudWrite();
    final canReadExistingCloudClips = _userStatusManager
        .canReadExistingCloudClips();
    debugPrint(
      '[LibraryTransfer] $event '
      'selected_count=${_selectedClipPaths.length} '
      'state_counts '
      'localOnly=${counts['localOnlyCount'] ?? 0} '
      'cloudOnly=${counts['cloudOnlyCount'] ?? 0} '
      'cloudSyncedLocal=${counts['cloudSyncedLocalCount'] ?? 0} '
      'pendingUpload=${counts['pendingUploadCount'] ?? 0} '
      'failedUpload=${counts['failedUploadCount'] ?? 0} '
      'failedDownload=${counts['failedDownloadCount'] ?? 0} '
      'uploadable=${counts['uploadableCount'] ?? 0} '
      'resolved_action=${action.name} '
      'show_transfer_button=${showTransferButton ?? 'unknown'} '
      'can_start_new_cloud_write=$canStartNewCloudWrite '
      'can_read_existing_cloud_clips=$canReadExistingCloudClips '
      'branch=$branch '
      'handler_invoked=$handlerInvoked',
    );
  }

  void _logTransferRenderIfChanged({
    required LibraryClipTransferAction action,
    required bool showTransferButton,
  }) {
    if (!_isClipSelectionMode) return;
    final counts = _selectedStorageStateCounts();
    final signature = [
      _selectedClipPaths.length,
      counts['localOnlyCount'] ?? 0,
      counts['cloudOnlyCount'] ?? 0,
      counts['cloudSyncedLocalCount'] ?? 0,
      counts['pendingUploadCount'] ?? 0,
      counts['failedUploadCount'] ?? 0,
      counts['failedDownloadCount'] ?? 0,
      counts['uploadableCount'] ?? 0,
      action.name,
      showTransferButton,
      _userStatusManager.canStartNewCloudWrite(),
      _userStatusManager.canReadExistingCloudClips(),
    ].join('|');
    if (_lastTransferRenderSignature == signature) return;
    _lastTransferRenderSignature = signature;
    _logLibraryTransfer(
      'render',
      action: action,
      branch: 'render',
      handlerInvoked: false,
      showTransferButton: showTransferButton,
    );
  }

  void _logUploadMoveMethod(
    String event, {
    required int targetCount,
    int? selectedCount,
    bool? isGuest,
    bool? canStartNewCloudWrite,
    bool? pendingUploadUiSet,
    String? earlyReturnReason,
    bool? backgroundDispatchInvoked,
    bool? taskStarted,
    Map<String, int>? stateCounts,
    int? stateAllowedCount,
    int? stateMismatchCount,
    int? localFileExistsCount,
    int? localFileMissingCount,
    int? uploadVideoImmediateCallCount,
    int? uploadSuccessCount,
    int? uploadFailureCount,
    int? successCount,
    int? failureCount,
    int? skippedCount,
    String? finalToastType,
  }) {
    final counts = stateCounts ?? const <String, int>{};
    debugPrint(
      '[LibraryTransfer][UploadMove] $event '
      'target_count=$targetCount '
      'selected_count=${selectedCount ?? 'unknown'} '
      'is_guest=${isGuest ?? 'unknown'} '
      'can_start_new_cloud_write=${canStartNewCloudWrite ?? 'unknown'} '
      'pending_upload_ui_set=${pendingUploadUiSet ?? 'unknown'} '
      'early_return_reason=${earlyReturnReason ?? 'none'} '
      'background_dispatch_invoked=${backgroundDispatchInvoked ?? false} '
      'task_started=${taskStarted ?? false} '
      'state_counts '
      'localOnly=${counts['localOnlyCount'] ?? 0} '
      'cloudOnly=${counts['cloudOnlyCount'] ?? 0} '
      'cloudSyncedLocal=${counts['cloudSyncedLocalCount'] ?? 0} '
      'pendingUpload=${counts['pendingUploadCount'] ?? 0} '
      'failedUpload=${counts['failedUploadCount'] ?? 0} '
      'failedDownload=${counts['failedDownloadCount'] ?? 0} '
      'uploadable_count=${counts['uploadableCount'] ?? 0} '
      'state_allowed_count=${stateAllowedCount ?? 0} '
      'state_mismatch_count=${stateMismatchCount ?? 0} '
      'local_file_exists_count=${localFileExistsCount ?? 0} '
      'local_file_missing_count=${localFileMissingCount ?? 0} '
      'uploadVideoImmediate_call_count=${uploadVideoImmediateCallCount ?? 0} '
      'upload_success_count=${uploadSuccessCount ?? 0} '
      'upload_failure_count=${uploadFailureCount ?? 0} '
      'success_count=${successCount ?? 0} '
      'failure_count=${failureCount ?? 0} '
      'skipped_count=${skippedCount ?? 0} '
      'final_toast_type=${finalToastType ?? 'none'}',
    );
  }

  IconData _transferIconForSelectionState(LibraryClipTransferAction action) {
    return libraryClipTransferIconForAction(action);
  }

  bool _shouldShowTransferButton(LibraryClipTransferAction action) {
    return shouldShowLibraryClipTransferButton(
      action: action,
      isGuest: AuthService().isGuest,
      canStartNewCloudWrite: _userStatusManager.canStartNewCloudWrite(),
      canReadExistingCloudClips: _userStatusManager.canReadExistingCloudClips(),
    );
  }

  VoidCallback? _transferHandlerForSelectionState(
    LibraryClipTransferAction action,
  ) {
    VoidCallback wrap(String branch, VoidCallback handler) {
      return () {
        _logLibraryTransfer(
          'tap_start',
          action: action,
          branch: branch,
          handlerInvoked: true,
          showTransferButton: _shouldShowTransferButton(action),
        );
        handler();
      };
    }

    if (AuthService().isGuest) {
      return wrap('guest_blocked', _showGuestCloudActionBlockedToast);
    }

    switch (action) {
      case LibraryClipTransferAction.upload:
        if (!_userStatusManager.canStartNewCloudWrite()) {
          return wrap('write_gate_blocked', _showCloudWriteBlockedToast);
        }
        return wrap('upload_move', _moveSelectedLocalToCloud);
      case LibraryClipTransferAction.download:
        if (!_userStatusManager.canReadExistingCloudClips()) {
          return wrap('read_gate_blocked', _showCloudReadBlockedToast);
        }
        return wrap('download_move', _removeSelectedCloudBackup);
      case LibraryClipTransferAction.cloudDone:
        return wrap(
          _transferBranchName(action),
          () => _showCloudTransferUnavailableToast('이미 기기와 Cloud에 동기화된 클립입니다.'),
        );
      case LibraryClipTransferAction.progress:
        return wrap(
          _transferBranchName(action),
          () => _showCloudTransferUnavailableToast(
            'Cloud 작업이 진행 중인 클립입니다. 완료 후 다시 시도해 주세요.',
          ),
        );
      case LibraryClipTransferAction.disabled:
        return wrap(
          _transferBranchName(action),
          () => _showCloudTransferUnavailableToast(
            '서로 다른 Cloud 상태의 클립은 한 번에 처리할 수 없습니다.',
          ),
        );
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

  void _showCloudWriteBlockedToast() {
    if (!mounted) return;
    final message = _userStatusManager.canReadExistingCloudClips()
        ? _cloudService.subscriptionExpiredCloudWriteMessage()
        : '클라우드 이동은 Standard 이상에서 사용할 수 있어요. 플랜을 확인해주세요.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
    );
  }

  void _showCloudReadBlockedToast() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_cloudService.subscriptionExpiredCloudReadMessage()),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  void _showCloudTransferUnavailableToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  Future<void> _moveSelectedLocalToCloud() async {
    final targets = List<String>.from(_selectedClipPaths);
    final prePendingStates = <String, ClipStorageState>{
      for (final path in targets) path: videoManager.getClipStorageState(path),
    };
    final selectedCount = _selectedClipPaths.length;
    final isGuest = AuthService().isGuest;
    final canStartNewCloudWrite = _userStatusManager.canStartNewCloudWrite();
    _logUploadMoveMethod(
      '_moveSelectedLocalToCloud_entry',
      targetCount: targets.length,
      selectedCount: selectedCount,
      isGuest: isGuest,
      canStartNewCloudWrite: canStartNewCloudWrite,
      pendingUploadUiSet: false,
      stateCounts: clipStorageStateCountsForStates(prePendingStates.values),
    );

    if (targets.isEmpty) {
      _logUploadMoveMethod(
        '_moveSelectedLocalToCloud_early_return',
        targetCount: targets.length,
        selectedCount: selectedCount,
        isGuest: isGuest,
        canStartNewCloudWrite: canStartNewCloudWrite,
        pendingUploadUiSet: false,
        earlyReturnReason: 'no_targets',
        stateCounts: clipStorageStateCountsForStates(prePendingStates.values),
      );
      return;
    }

    if (isGuest) {
      _logUploadMoveMethod(
        '_moveSelectedLocalToCloud_early_return',
        targetCount: targets.length,
        selectedCount: selectedCount,
        isGuest: isGuest,
        canStartNewCloudWrite: canStartNewCloudWrite,
        pendingUploadUiSet: false,
        earlyReturnReason: 'guest_blocked',
        stateCounts: clipStorageStateCountsForStates(prePendingStates.values),
      );
      _showGuestCloudActionBlockedToast();
      return;
    }

    if (!canStartNewCloudWrite) {
      _logUploadMoveMethod(
        '_moveSelectedLocalToCloud_early_return',
        targetCount: targets.length,
        selectedCount: selectedCount,
        isGuest: isGuest,
        canStartNewCloudWrite: canStartNewCloudWrite,
        pendingUploadUiSet: false,
        earlyReturnReason: 'write_gate_blocked',
        stateCounts: clipStorageStateCountsForStates(prePendingStates.values),
      );
      _showCloudWriteBlockedToast();
      return;
    }

    setState(() {
      _isClipSelectionMode = false;
      _selectedClipPaths.clear();
    });

    for (final path in targets) {
      videoManager.markClipTransferPendingUpload(path);
    }

    _logUploadMoveMethod(
      '_moveSelectedLocalToCloud_background_dispatch',
      targetCount: targets.length,
      selectedCount: selectedCount,
      isGuest: isGuest,
      canStartNewCloudWrite: canStartNewCloudWrite,
      pendingUploadUiSet: true,
      backgroundDispatchInvoked: true,
      stateCounts: clipStorageStateCountsForStates(prePendingStates.values),
    );
    unawaited(
      _moveSelectedLocalToCloudInBackground(
        targets,
        prePendingStates: prePendingStates,
      ),
    );
  }

  Future<void> _moveSelectedLocalToCloudInBackground(
    List<String> targets, {
    required Map<String, ClipStorageState> prePendingStates,
  }) async {
    var success = 0;
    var failed = 0;
    var skipped = 0;
    var stateAllowedCount = 0;
    var stateMismatchCount = 0;
    var localFileExistsCount = 0;
    var localFileMissingCount = 0;
    var uploadVideoImmediateCallCount = 0;
    var uploadSuccessCount = 0;
    var uploadFailureCount = 0;
    String? firstErrorCode;
    String? firstErrorCopy;
    _logUploadMoveMethod(
      '_moveSelectedLocalToCloudInBackground_entry',
      targetCount: targets.length,
      selectedCount: 0,
      pendingUploadUiSet: true,
      taskStarted: true,
      stateCounts: clipStorageStateCountsForStates(prePendingStates.values),
    );

    for (final path in targets) {
      try {
        final prePendingState = prePendingStates[path];
        if (!isUploadMoveEligibleFromPrePendingState(prePendingState)) {
          stateMismatchCount++;
          skipped++;
          videoManager.markClipTransferUploadFailed(path);
          failed++;
          continue;
        }
        stateAllowedCount++;
        final file = File(path);
        if (!await file.exists()) {
          localFileMissingCount++;
          skipped++;
          videoManager.markClipTransferUploadFailed(path);
          failed++;
          continue;
        }
        localFileExistsCount++;

        uploadVideoImmediateCallCount++;
        final videoId = await _cloudService.uploadVideoImmediate(
          videoFile: file,
          albumName: videoManager.currentAlbum,
          isFavorite: videoManager.favorites.contains(path),
          localPath: path,
        );

        if (videoId == null) {
          uploadFailureCount++;
          firstErrorCode ??= _cloudService.lastImmediateUploadErrorCode;
          firstErrorCopy ??= _cloudService.lastImmediateUploadErrorCopy;
          videoManager.markClipTransferUploadFailed(path);
          failed++;
          continue;
        }

        uploadSuccessCount++;
        // Exclusive storage model: a completed Cloud move removes the local
        // copy so the clip exists in exactly one storage tier.
        await videoManager.removeLocalClipAfterCloudMove(
          path: path,
          albumName: videoManager.currentAlbum,
        );
        videoManager.clearClipTransferUiState(path);
        success++;
      } catch (_) {
        uploadFailureCount++;
        videoManager.markClipTransferUploadFailed(path);
        failed++;
      }
    }

    final finalToastType = failed == 0
        ? 'success'
        : (success > 0 ? 'partial' : 'failure');
    _logUploadMoveMethod(
      '_moveSelectedLocalToCloudInBackground_summary',
      targetCount: targets.length,
      selectedCount: 0,
      pendingUploadUiSet: true,
      stateCounts: clipStorageStateCountsForStates(prePendingStates.values),
      stateAllowedCount: stateAllowedCount,
      stateMismatchCount: stateMismatchCount,
      localFileExistsCount: localFileExistsCount,
      localFileMissingCount: localFileMissingCount,
      uploadVideoImmediateCallCount: uploadVideoImmediateCallCount,
      uploadSuccessCount: uploadSuccessCount,
      uploadFailureCount: uploadFailureCount,
      successCount: success,
      failureCount: failed,
      skippedCount: skipped,
      finalToastType: finalToastType,
    );

    final text = failed == 0
        ? '클라우드로 $success개 이동 완료'
        : '클라우드 이동 완료 $success개, 실패 $failed개';
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }

    if (success > 0) {
      await videoManager.syncCloudMetadataToLibrary(trigger: 'move_to_cloud');
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
      case 'subscription_expired':
        return '구독이 만료되어 신규 Cloud 업로드/복사가 중지되었어요. 기존 Cloud 클립은 만료 후 30일 동안 복원할 수 있으며, 구독 복원 또는 재구독 후 다시 이용할 수 있어요.';
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

  Future<void> _removeSelectedCloudBackup() async {
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

    unawaited(_removeSelectedCloudBackupInBackground(targets));
  }

  Future<void> _removeSelectedCloudBackupInBackground(
    List<String> targets,
  ) async {
    var success = 0;
    var failed = 0;

    for (final path in targets) {
      try {
        if (videoManager.isCloudOnlyPlaceholder(path)) {
          final meta = videoManager.getCloudMetadataForPath(path);
          if (meta == null) {
            videoManager.markClipTransferDownloadFailed(path);
            failed++;
            continue;
          }
          final albumName = meta.albumName.trim().isEmpty
              ? videoManager.currentAlbum
              : meta.albumName.trim();
          final fileName = meta.fileName.trim().isEmpty
              ? '${meta.videoId}.mp4'
              : meta.fileName.trim();
          final localPath = await videoManager.buildUniqueRawClipPath(
            albumName: albumName,
            fileName: fileName,
          );
          final ok = await _cloudService.downloadVideo(
            videoId: meta.videoId,
            localPath: localPath,
          );
          if (!ok || !await File(localPath).exists()) {
            videoManager.markClipTransferDownloadFailed(path);
            failed++;
            continue;
          }

          final removedFromCloud = await _cloudService.markVideoMovedToDevice(
            meta.videoId,
          );
          if (!removedFromCloud) {
            final downloadedFile = File(localPath);
            if (await downloadedFile.exists()) {
              await downloadedFile.delete();
            }
            videoManager.markClipTransferDownloadFailed(path);
            failed++;
            continue;
          }

          await videoManager.registerCloudMovedToDeviceClip(
            path: localPath,
            albumName: albumName,
            cloudMetadata: meta,
          );
          videoManager.clearClipTransferUiState(path);
          success++;
          continue;
        }

        if (!videoManager.isClipCloudSynced(path)) {
          videoManager.markClipTransferDownloadFailed(path);
          failed++;
          continue;
        }

        videoManager.clearClipTransferUiState(path);
        success++;
      } catch (_) {
        videoManager.markClipTransferDownloadFailed(path);
        failed++;
      }
    }

    final text = failed == 0
        ? 'Cloud 클립 $success개 복원 완료'
        : 'Cloud 클립 복원 완료 $success개, 실패 $failed개';
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  bool _isLibraryFilterSelected(String value) {
    if (value == 'favorites') return _showFavoritesOnly;
    return !_showFavoritesOnly && _storageFilter == value;
  }

  void _setLibraryFilter(String value) {
    setState(() {
      if (value == 'favorites') {
        _storageFilter = 'all';
        _showFavoritesOnly = true;
      } else {
        _storageFilter = value;
        _showFavoritesOnly = false;
      }
      _selectedClipPaths.clear();
      _isClipSelectionMode = false;
      if (_previewingPath != null &&
          !videoManager.isClipVisibleByStorageFilter(
            _previewingPath!,
            _storageFilter,
          )) {
        _previewingPath = null;
      }
      if (_previewingPath != null &&
          _showFavoritesOnly &&
          !videoManager.favorites.contains(_previewingPath)) {
        _previewingPath = null;
      }
    });
  }

  Widget _buildLibraryFilterChip(
    String value,
    String label, {
    IconData? icon,
    IconData? selectedIcon,
  }) {
    final selected = _isLibraryFilterSelected(value);
    final resolvedIcon = selected ? selectedIcon ?? icon : icon;
    final iconOnly = label.isEmpty && resolvedIcon != null;
    return ChoiceChip(
      label: iconOnly
          ? Icon(
              resolvedIcon,
              size: 18,
              color: value == 'favorites'
                  ? const Color(0xFFE91E63)
                  : MoaDesignTokens.accentStrong,
            )
          : Text(label),
      avatar: iconOnly || resolvedIcon == null
          ? null
          : Icon(
              resolvedIcon,
              size: 18,
              color: value == 'favorites'
                  ? const Color(0xFFE91E63)
                  : MoaDesignTokens.accentStrong,
            ),
      showCheckmark: !iconOnly,
      selected: selected,
      selectedColor: value == 'favorites'
          ? const Color(0xFFFFE5EC)
          : MoaDesignTokens.accentSoft,
      backgroundColor: MoaDesignTokens.surfaceAlt,
      disabledColor: MoaDesignTokens.surfaceAlt.withValues(alpha: 0.55),
      side: BorderSide(
        color: selected
            ? MoaDesignTokens.accent.withValues(alpha: 0.62)
            : MoaDesignTokens.stroke,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      labelStyle: TextStyle(
        color: selected
            ? MoaDesignTokens.textPrimary
            : MoaDesignTokens.textMuted,
        fontWeight: FontWeight.w800,
      ),
      checkmarkColor: value == 'favorites'
          ? const Color(0xFFE91E63)
          : MoaDesignTokens.accentStrong,
      onSelected: (_) => _setLibraryFilter(value),
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
