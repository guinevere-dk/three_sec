import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/video_widgets.dart';
import '../widgets/media_widgets.dart';
import '../widgets/media_dialogs.dart';
import '../utils/haptics.dart';
import '../utils/media_selection_helper.dart';
import '../managers/video_manager.dart';
import '../screens/paywall_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/video_edit_screen.dart';
import '../models/vlog_project.dart';

class LibraryScreen extends StatefulWidget {
  final GlobalKey keyPickMedia;
  final GlobalKey keyFirstClip;
  final Function() onRefreshData;
  final Function(List<String> selectedPaths) onMerge;
  final Function(String path) onPickMedia;
  
  const LibraryScreen({
    super.key,
    required this.keyPickMedia,
    required this.keyFirstClip,
    required this.onRefreshData,
    required this.onMerge,
    required this.onPickMedia,
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

  final GlobalKey _clipGridKey = GlobalKey(debugLabel: 'clipGrid');
  final GlobalKey _albumGridKey = GlobalKey(debugLabel: 'albumGrid');

  List<String> _selectedClipPaths = [];
  Set<String> _selectedAlbumNames = {};

  late VideoManager videoManager;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      videoManager = Provider.of<VideoManager>(context, listen: false);
      await videoManager.initAlbumSystem();
      if (mounted) setState(() {});
    });
  }
  
  final ScrollController _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    videoManager = Provider.of<VideoManager>(context);
    
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (_previewingPath != null) setState(() => _previewingPath = null);
        else if (_isClipSelectionMode) setState(() { _isClipSelectionMode = false; _selectedClipPaths.clear(); });
        else if (_isAlbumSelectionMode) setState(() { _isAlbumSelectionMode = false; _selectedAlbumNames.clear(); });
        else if (_isInAlbumDetail) setState(() => _isInAlbumDetail = false);
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
    final selectableAlbums = allAlbums.where((a) => a != "일상" && a != "휴지통").toList();
    final bool isAll = _selectedAlbumNames.length == selectableAlbums.length && _selectedAlbumNames.isNotEmpty;
    
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
          controller: _scrollController, // Attach Controller
          physics: const AlwaysScrollableScrollPhysics(), // Ensure scrolling works
          slivers: [
            // Library Header
            SliverAppBar(
            backgroundColor: Colors.white.withOpacity(0.8),
            surfaceTintColor: Colors.transparent,
            pinned: true,
            floating: true,
            centerTitle: false,
            title: Row(
              children: [
                const Icon(Icons.folder, color: Colors.blueAccent, size: 28),
                const SizedBox(width: 8),
                Text(
                  _isAlbumSelectionMode ? "${_selectedAlbumNames.length} Selected" : "Library",
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            actions: [
              if (_isAlbumSelectionMode)
                 IconButton(
                  icon: Icon(isAll ? Icons.check_box : Icons.check_box_outline_blank, color: Colors.black),
                  onPressed: _toggleSelectAllAlbums,
                )
              else ...[
                 // PRO Badge (Upgrade)
                 GestureDetector(
                   onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen())),
                   child: Container(
                     margin: const EdgeInsets.only(right: 12),
                     width: 40,
                     height: 40,
                     decoration: BoxDecoration(
                       gradient: const LinearGradient(colors: [Colors.amber, Colors.orangeAccent]),
                       shape: BoxShape.circle,
                       boxShadow: [
                         BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))
                       ],
                     ),
                     child: const Icon(Icons.star, color: Colors.white, size: 20),
                   ),
                 ),
                 // Add Media Button (Unified Design)
                 IconButton(
                   key: widget.keyPickMedia,
                   icon: const Icon(Icons.add_circle_outline, color: Colors.black),
                   onPressed: () => widget.onPickMedia(''),
                 ),
              ]
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
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _gridColumnCount,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.85,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final albumName = allAlbums[index];
                      final clipCount = videoManager.albumCounts[albumName] ?? 0;
                      final isSelected = _selectedAlbumNames.contains(albumName);
                      final canSelect = albumName != "일상" && albumName != "휴지통"; // 'Vlog' 제외 조건 삭제

                      return MediaWidgets.buildFolderGridItem(
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
                    },
                    childCount: allAlbums.length,
                  ),
                ),
              ),
        ],
        ),
      ),
      floatingActionButton: _isAlbumSelectionMode && _selectedAlbumNames.isNotEmpty
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
    if (albumName == "휴지통") return Colors.red;
    return const Color(0xFFFFD66B);
  }

  Widget _buildDetailView() {
    // Determine subtitle
    final int count = videoManager.recordedVideoPaths.length;
    final String subtitle = "$count Clips";

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
          controller: _scrollController, // Attach Controller
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
                  _isClipSelectionMode ? "${_selectedClipPaths.length} Selected" : videoManager.currentAlbum,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (!_isClipSelectionMode)
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
              ],
            ),
            actions: [
              if (_isClipSelectionMode) ...[
                 if (_selectedClipPaths.length >= 2 && videoManager.currentAlbum != "휴지통")
                    IconButton(
                      icon: const Icon(Icons.movie_creation, color: Colors.blueAccent),
                      tooltip: 'Create Vlog',
                      onPressed: () {
                        final pathsCopy = List<String>.from(_selectedClipPaths);
                        _handleMerge(pathsCopy);
                        setState(() {
                          _isClipSelectionMode = false;
                          _selectedClipPaths.clear();
                        });
                      },
                    ),
                  IconButton(
                    icon: Icon(
                      _selectedClipPaths.length == videoManager.recordedVideoPaths.length
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      color: Colors.black,
                    ),
                    onPressed: _toggleSelectAllClips,
                  ),
              ] else ...[
                 // Play Button Eliminated
                  if (videoManager.currentAlbum != "휴지통") ...[
                    // Brush button removed
                    IconButton(
                      icon: const Icon(Icons.add_photo_alternate_outlined, color: Colors.black54),
                      tooltip: "Import",
                      onPressed: () => widget.onPickMedia(''),
                    ),
                  ]
              ]
            ],
          ),

          // Clip Grid
          if (videoManager.recordedVideoPaths.isEmpty)
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
                      )
                    ],
                  ),
                ),
             )
          else
            SliverPadding(
              padding: const EdgeInsets.all(4),
              sliver: SliverGrid(
                // key: _clipGridKey removed from here
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _gridColumnCount,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                  childAspectRatio: 1.0,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final path = videoManager.recordedVideoPaths[index];
                    final isSelected = _selectedClipPaths.contains(path);
                    final int selectIdx = _selectedClipPaths.indexOf(path);
                    
                    return MediaWidgets.buildMediaGridItem(
                      path: path,
                      isSelected: isSelected,
                      selectIndex: selectIdx,
                      isSelectionMode: _isClipSelectionMode,
                      gridColumnCount: _gridColumnCount,
                      isFavorite: videoManager.favorites.contains(path),
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
                  },
                  childCount: videoManager.recordedVideoPaths.length,
                ),
              ),
            ),
        ],
        ),
      ),
      // Bottom Navigation Eliminated
      
      // Bottom Navigation (Visual Only)

      
       // Floating Actions (Multi-Select)
       // Magic Brush (Vlog Create) FAB
      floatingActionButton: (_isClipSelectionMode && _selectedClipPaths.isNotEmpty)
          ? MediaWidgets.buildActionPanel(
              isTrashMode: videoManager.currentAlbum == "휴지통",
              onCreateVlog: null, // User requested to remove this from FAB
              onFavorite: () {
                videoManager.toggleFavoritesBatch(_selectedClipPaths);
                setState(() {
                  _isClipSelectionMode = false;
                  _selectedClipPaths.clear();
                });
                hapticFeedback();
              },
              onMove: () => _handleMoveOrCopy(true),
              onCopy: () => _handleMoveOrCopy(false),
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
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      
      // Preview Overlay
      bottomSheet: _previewingPath != null ? SizedBox(
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
      ) : null,
    );
  }

  // --- [제스처 처리] ---

  void _startDragSelection(Offset position, bool isClip) {
    final targetList = isClip 
        ? videoManager.recordedVideoPaths 
        : videoManager.clipAlbums;
    
    double topPad = MediaQuery.of(context).padding.top + kToolbarHeight; 
    double currentScroll = _scrollController.hasClients ? _scrollController.offset : 0.0;
    
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
      canSelectItem: isClip 
          ? null 
          : (item) => item != "일상" && item != "휴지통",
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
    double currentScroll = _scrollController.hasClients ? _scrollController.offset : 0.0;

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
      // onIndexProcessed removed from helper
      canSelectItem: isClip 
          ? null 
          : (item) => item != "일상" && item != "휴지통",
    );
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
    setState(() {
      if (_selectedClipPaths.length == videoManager.recordedVideoPaths.length) {
        _selectedClipPaths.clear();
      } else {
        _selectedClipPaths = List.from(videoManager.recordedVideoPaths);
      }
    });
    hapticFeedback();
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
    if (isTrash) {
      bool? ok = await MediaDialogs.showConfirmDialog(
        context: context,
        title: "영구 삭제",
        content: "이 클립을 삭제할까요?",
      );
      if (ok != true) return;
      await File(path).delete();
    } else {
      await videoManager.moveToTrash(path);
    }
    setState(() => _previewingPath = null);
    await _loadClipsFromCurrentAlbum();
    hapticFeedback();
  }

  Future<void> _handleMoveOrCopy(bool isMove) async {
    final String? result = await MediaDialogs.showMoveOrCopyDialog(
      context: context,
      isMove: isMove,
      folderList: videoManager.clipAlbums,
      currentFolder: videoManager.currentAlbum,
      excludeFolders: ["휴지통"],
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

  Future<void> _handleMerge(List<String> paths) async {
    if (paths.length < 2) return;
    
    // Create Project
    final project = await videoManager.createProject(paths);
    
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VideoEditScreen(project: project)),
    );
  }
}
