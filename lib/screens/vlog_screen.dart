import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../widgets/video_widgets.dart';
import '../widgets/media_widgets.dart';
import '../widgets/media_dialogs.dart';
import '../utils/haptics.dart';
import '../utils/media_selection_helper.dart';
import '../managers/video_manager.dart';
import 'package:intl/intl.dart';
import '../models/vlog_project.dart';
import '../screens/video_edit_screen.dart';
import '../screens/paywall_screen.dart';

class VlogScreen extends StatefulWidget {
  final Function() onRefresh;
  final Function(String path) onEditRequest;
  
  const VlogScreen({
    super.key,
    required this.onRefresh,
    required this.onEditRequest,
  });

  @override
  State<VlogScreen> createState() => _VlogScreenState();
}

class _VlogScreenState extends State<VlogScreen> {
  bool _isInFolderDetail = false;
  bool _isVlogSelectionMode = false;
  bool _isFolderSelectionMode = false;
  bool _isDragAdding = true;
  int? _dragStartIndex;
  
  int _gridColumnCount = 3;
  bool _isZoomingLocked = false;
  


  String? _previewingPath;

  final GlobalKey _vlogGridKey = GlobalKey(debugLabel: 'vlogGrid');
  final GlobalKey _folderGridKey = GlobalKey(debugLabel: 'folderGrid');

  List<String> _selectedVlogPaths = [];
  Set<String> _selectedFolderNames = {};

  late VideoManager videoManager;

  @override
  Widget build(BuildContext context) {
    videoManager = Provider.of<VideoManager>(context);
    
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (_previewingPath != null) setState(() => _previewingPath = null);
        else if (_isVlogSelectionMode) setState(() { _isVlogSelectionMode = false; _selectedVlogPaths.clear(); });
        else if (_isFolderSelectionMode) setState(() { _isFolderSelectionMode = false; _selectedFolderNames.clear(); });
        else if (_isInFolderDetail) setState(() => _isInFolderDetail = false);
      },
      child: _isInFolderDetail ? _buildDetailView() : _buildFolderListTab(),
    );
  }

  Future<void> _loadVlogsFromCurrentFolder() async {
    setState(() {
      videoManager.vlogProjectPaths.clear();
    });
    await videoManager.loadVlogsFromCurrentFolder();
    if (mounted) setState(() {});
  }

  Widget _buildFolderListTab() {
    final allFolders = videoManager.vlogAlbums.where((f) => f != "일상").toList();
    final selectableFolders = allFolders.where((f) => f != "기본" && f != "휴지통").toList();
    final bool isAll = _selectedFolderNames.length == selectableFolders.length && _selectedFolderNames.isNotEmpty;
    
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: GestureDetector(
        key: _folderGridKey, // Restore Key
        onScaleStart: (d) {
          _isZoomingLocked = false;
          if (_isFolderSelectionMode && d.pointerCount == 1) {
            _startDragSelection(d.focalPoint, false);
          }
        },
        onScaleUpdate: (d) => _handleScaleUpdate(d, false),
        onScaleEnd: (_) => _dragStartIndex = null,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              backgroundColor: Colors.white.withOpacity(0.8),
              surfaceTintColor: Colors.transparent,
              pinned: true,
              floating: true,
              centerTitle: false,
              title: Row(
                children: [
                  const Icon(Icons.video_library, color: Colors.deepPurple, size: 28),
                  const SizedBox(width: 8),
                  Text(
                    _isFolderSelectionMode ? "${_selectedFolderNames.length} Selected" : "Vlog",
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
                if (_isFolderSelectionMode)
                  IconButton(
                    icon: Icon(isAll ? Icons.check_box : Icons.check_box_outline_blank, color: Colors.black),
                    onPressed: _toggleSelectAllFolders,
                  )
                else ...[
                  // PRO Badge
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
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: Colors.black),
                    onPressed: _showCreateFolderDialog,
                  ),
                ],
              ],
            ),
            
            allFolders.isEmpty
              ? SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.folder_open, color: Colors.grey, size: 60),
                        SizedBox(height: 16),
                        Text(
                          "No Vlog folders.\nAdd one to start!",
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
                        final folderName = allFolders[index];
                        final isSelected = _selectedFolderNames.contains(folderName);
                        final canSelect = folderName != "기본" && folderName != "휴지통";

                        return MediaWidgets.buildFolderGridItem(
                          folderName: folderName,
                          clipCount: 0, // TODO: Count implementation
                          isSelected: isSelected,
                          canSelect: canSelect,
                          isSelectionMode: _isFolderSelectionMode,
                          gridColumnCount: _gridColumnCount,
                          onTap: () {
                            if (_isFolderSelectionMode) {
                              if (!canSelect) return;
                              setState(() {
                                if (isSelected) {
                                  _selectedFolderNames.remove(folderName);
                                } else {
                                  _selectedFolderNames.add(folderName);
                                }
                              });
                            } else {
                              setState(() {
                                videoManager.currentVlogFolder = folderName;
                                _isInFolderDetail = true;
                                _selectedVlogPaths.clear();
                                _isVlogSelectionMode = false;
                              });
                              _loadVlogsFromCurrentFolder();
                            }
                          },
                          onLongPress: canSelect
                              ? () {
                                  setState(() {
                                    _isFolderSelectionMode = true;
                                    if (isSelected) {
                                      _selectedFolderNames.remove(folderName);
                                    } else {
                                      _selectedFolderNames.add(folderName);
                                    }
                                  });
                                  hapticFeedback();
                                }
                              : null,
                          getIcon: _getFolderIcon,
                          getColor: _getFolderColor,
                        );
                      },
                      childCount: allFolders.length,
                    ),
                  ),
                ),
          ],
        ),
      ),
      floatingActionButton: _isFolderSelectionMode && _selectedFolderNames.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _handleFolderBatchDelete,
              backgroundColor: Colors.deepPurple,
              icon: const Icon(Icons.delete),
              label: const Text("Delete"),
            )
          : null,
    );
  }
  
  IconData _getFolderIcon(String folderName) {
    if (folderName == "기본") return Icons.home;
    if (folderName == "휴지통") return Icons.delete_outline;
    return Icons.video_library;
  }
  
  Color _getFolderColor(String folderName) {
    if (folderName == "기본") return Colors.blue;
    if (folderName == "휴지통") return Colors.deepPurple;
    return Colors.purple;
  }

  Widget _buildDetailView() {
    // Use filteredProjects instead of vlogProjects
    final projects = videoManager.filteredProjects;

    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        key: _vlogGridKey, // Restore Key
        onScaleStart: (d) {
          _isZoomingLocked = false;
          if (_isVlogSelectionMode && d.pointerCount == 1) {
             _startDragSelection(d.focalPoint, true);
          }
        },
        onScaleUpdate: (d) => _handleScaleUpdate(d, true),
        onScaleEnd: (_) => _dragStartIndex = null,
        child: Stack(
          children: [
            CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverAppBar(
                  backgroundColor: Colors.white.withOpacity(0.9),
                  surfaceTintColor: Colors.transparent,
                  pinned: true,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
                    onPressed: () {
                      if (_isVlogSelectionMode) {
                        setState(() {
                          _isVlogSelectionMode = false;
                          _selectedVlogPaths.clear();
                        });
                      } else {
                        setState(() => _isInFolderDetail = false);
                      }
                    },
                  ),
                  centerTitle: false,
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isVlogSelectionMode ? "${_selectedVlogPaths.length} Selected" : videoManager.currentVlogFolder,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                       if (!_isVlogSelectionMode)
                        Text(
                          "${projects.length} Vlogs",
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
                    if (_isVlogSelectionMode)
                      IconButton(
                        icon: Icon(
                          _selectedVlogPaths.length == projects.length
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          color: Colors.black,
                        ),
                        onPressed: _toggleSelectAllVlogs,
                      )
                  ],
                ),
                
                if (projects.isEmpty)
                   SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.stars, size: 60, color: Colors.grey),
                            SizedBox(height: 16),
                            Text(
                              "No Vlogs.\nMerge clips to create one!",
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
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _gridColumnCount,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                        childAspectRatio: 1.0,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final project = projects[index];
                          final isSelected = _selectedVlogPaths.contains(project.id);
                          final int selectIdx = _selectedVlogPaths.indexOf(project.id);

                          return MediaWidgets.buildMediaGridItem(
                            // Thumbnail from first clip
                            path: project.videoPaths.isNotEmpty ? project.videoPaths.first : '', 
                            isSelected: isSelected,
                            selectIndex: selectIdx,
                            isSelectionMode: _isVlogSelectionMode,
                            gridColumnCount: _gridColumnCount,
                            isFavorite: false, // Favorites removed for Vlogs
                            subtitle: "${DateFormat('MM/dd').format(project.updatedAt)} • ${project.videoPaths.length} clips",
                            title: project.title,
                            onTap: () {
                              if (_isVlogSelectionMode) {
                                setState(() {
                                  if (isSelected) {
                                    _selectedVlogPaths.remove(project.id);
                                  } else {
                                    _selectedVlogPaths.add(project.id);
                                  }
                                });
                              } else {
                                // Navigate to Editor
                                Navigator.push(
                                  context, 
                                  MaterialPageRoute(builder: (_) => VideoEditScreen(project: project))
                                ).then((_) => widget.onRefresh());
                              }
                            },
                            onLongPress: () {
                              setState(() {
                                _isVlogSelectionMode = true;
                                _dragStartIndex = index;
                                _isDragAdding = !isSelected;
                                if (_isDragAdding) {
                                  _selectedVlogPaths.add(project.id);
                                } else {
                                  _selectedVlogPaths.remove(project.id);
                                }
                              });
                              hapticFeedback();
                            },
                            getThumbnail: videoManager.getThumbnail,
                          );
                        },
                        childCount: projects.length,
                      ),
                    ),
                  ),
              ],
            ),
            // Preview Overlay Integration
            if (_previewingPath != null)
              ResultPreviewWidget(
                videoPath: _previewingPath!,
                onShare: () => Share.shareXFiles([XFile(_previewingPath!)], text: 'Made with 3S Vlog'),
                onEdit: () => widget.onEditRequest(_previewingPath!),
                onClose: () => setState(() => _previewingPath = null),
              ),
          ],
        ),
      ),
      floatingActionButton: (_isVlogSelectionMode && _selectedVlogPaths.isNotEmpty)
          ? MediaWidgets.buildActionPanel(
              isTrashMode: videoManager.currentVlogFolder == "휴지통",
              onCreateVlog: null, 
              onFavorite: null, // Removed favorite action
              onMove: () => _handleMoveOrCopy(true),
              // Copy not requested for folders phase, but keeping placeholder or removing?
              // User said: "moveProjectToFolder(VlogProject project, String targetFolder) 메서드를 구현해라."
              // and in Step 3: "_handleMoveOrCopy에서 폴더 선택 후 videoManager.moveProjectToFolder를 호출하도록 연결해라."
              // Assuming Copy is not priority or should behave like Move (duplicate then move?)
              // For now, let's keep Copy as void or implementing duplication later if needed.
              // Logic changes: _handleMoveOrCopy implemented below.
              onCopy: () => _handleMoveOrCopy(false), 
              onDelete: _handleVlogBatchDelete,
              onRestore: () async {
                // Restore from Trash (which is a folder now) = Move to '기본' or original?
                // Logic for filteredProjects handles '휴지통' folder.
                // We should use moveProjectToFolder('기본') for restore if simple.
                for (var id in _selectedVlogPaths) {
                   final p = projects.firstWhere((element) => element.id == id);
                   await videoManager.moveProjectToFolder(p, '기본');
                }
                setState(() {
                  _isVlogSelectionMode = false;
                  _selectedVlogPaths.clear();
                });
                hapticFeedback();
              },
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  // --- [제스처 처리] ---

  void _startDragSelection(Offset position, bool isVlog) {
    final targetList = isVlog 
        ? videoManager.vlogProjects.map((p) => p.id).toList()
        : videoManager.vlogAlbums.where((f) => f != "일상").toList(); // ✅ 휴지통 포함
    
    double topPad = MediaQuery.of(context).padding.top + kToolbarHeight;
    double currentScroll = _scrollController.hasClients ? _scrollController.offset : 0.0;
    
    MediaSelectionHelper.startDragSelection(
      focalPoint: position,
      gridKey: isVlog ? _vlogGridKey : _folderGridKey,
      columnCount: _gridColumnCount,
      childAspectRatio: isVlog ? 1.0 : (_gridColumnCount == 3 ? 0.7 : 0.85),
      targetList: targetList.map((e) => e.toString()).toList(), // Fix type mapping if needed, assuming Vlogs/Folders are Strings or have IDs
      currentSelection: isVlog ? _selectedVlogPaths : _selectedFolderNames,
      scrollOffset: currentScroll,
      topPadding: topPad,
      onSelectionChanged: (item, isAdding) {
        setState(() {
          if (isVlog) {
            if (isAdding) {
              _selectedVlogPaths.add(item);
            } else {
              _selectedVlogPaths.remove(item);
            }
          } else {
            if (isAdding) {
              _selectedFolderNames.add(item);
            } else {
              _selectedFolderNames.remove(item);
            }
          }
        });
      },
      onDragStarted: (index, isAdding) {
        _dragStartIndex = index;
        _isDragAdding = isAdding;
      },
      canSelectItem: isVlog 
          ? null 
          : (item) => item != "기본" && item != "휴지통",
    );
  }

  void _handleScaleUpdate(ScaleUpdateDetails details, bool isVlog) {
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
    final isActive = isVlog ? _isVlogSelectionMode : _isFolderSelectionMode;
    if (!isActive) return;
    
    final targetList = isVlog 
        ? videoManager.vlogProjects.map((p) => p.id).toList()
        : videoManager.vlogAlbums.where((f) => f != "일상").toList(); // ✅ 휴지통 포함
    
    double topPad = MediaQuery.of(context).padding.top + kToolbarHeight; 
    double currentScroll = _scrollController.hasClients ? _scrollController.offset : 0.0;

    MediaSelectionHelper.updateDragSelection(
      focalPoint: details.focalPoint,
      gridKey: isVlog ? _vlogGridKey : _folderGridKey,
      columnCount: _gridColumnCount,
      childAspectRatio: isVlog ? 1.0 : (_gridColumnCount == 3 ? 0.7 : 0.85),
      targetList: targetList.map((e) => e.toString()).toList(),
      currentSelection: isVlog ? _selectedVlogPaths : _selectedFolderNames,
      dragStartIndex: _dragStartIndex ?? -1,
      isDragAdding: _isDragAdding,
      scrollOffset: currentScroll,
      topPadding: topPad,
      onSelectionChanged: (item, isAdding) {
        setState(() {
          if (isVlog) {
            if (isAdding) {
              _selectedVlogPaths.add(item);
            } else {
              _selectedVlogPaths.remove(item);
            }
          } else {
            if (isAdding) {
              _selectedFolderNames.add(item);
            } else {
              _selectedFolderNames.remove(item);
            }
          }
        });
      },
      canSelectItem: isVlog 
          ? null 
          : (item) => item != "기본" && item != "휴지통",
    );
  }

  void _toggleSelectAllFolders() {
    setState(() {
      final selectable = videoManager.vlogAlbums
          .where((f) => f != "기본" && f != "휴지통" && f != "일상")
          .toList();
      if (_selectedFolderNames.length == selectable.length) {
        _selectedFolderNames.clear();
      } else {
        _selectedFolderNames = Set.from(selectable);
      }
    });
    hapticFeedback();
  }

   // --- [액션 핸들러] ---

  void _showCreateFolderDialog() async {
    String? name = await MediaDialogs.showCreateVlogFolderDialog(context: context);
    if (name != null && name.trim().isNotEmpty) {
      if (videoManager.vlogAlbums.contains(name.trim())) return;
      await videoManager.createNewVlogAlbum(name.trim());
      widget.onRefresh();
    }
  }

  Future<void> _handleFolderBatchDelete() async {
    bool? ok = await MediaDialogs.showConfirmDialog(
      context: context,
      title: "폴더 삭제",
      content: "폴더는 삭제되고 Vlog는 휴지통으로 이동합니다.",
    );
    if (ok == true) {
      await videoManager.deleteVlogAlbums(_selectedFolderNames);
      setState(() {
        _isFolderSelectionMode = false;
        _selectedFolderNames.clear();
      });
      await videoManager.initAlbumSystem();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
         // ... existing code ...
         if (mounted) setState(() {});
      });
    }
  }
  
  final ScrollController _scrollController = ScrollController();

  Future<void> _handleVlogBatchDelete() async {
    bool isTrash = videoManager.currentVlogFolder == "휴지통";
    if (isTrash) {
      bool? ok = await MediaDialogs.showConfirmDialog(
        context: context,
        title: "영구 삭제",
        content: "선택한 Vlog 프로젝트를 영구 삭제할까요? 복구할 수 없습니다.",
      );
      if (ok != true) return;
      for (var id in _selectedVlogPaths) await videoManager.deleteProject(id);
    } else {
      bool? ok = await MediaDialogs.showConfirmDialog(
        context: context,
        title: "프로젝트 삭제",
        content: "선택한 프로젝트를 휴지통으로 이동할까요?",
      );
      if (ok != true) return;
      
      for (var id in _selectedVlogPaths) {
        await videoManager.moveProjectToTrash(id);
      }
      Fluttertoast.showToast(msg: "휴지통으로 이동되었습니다");
    }
    setState(() {
      _isVlogSelectionMode = false;
      _selectedVlogPaths.clear();
    });
    hapticFeedback();
  }

  void _toggleSelectAllVlogs() {
    setState(() {
      final projects = videoManager.filteredProjects;
      if (_selectedVlogPaths.length == projects.length) {
        _selectedVlogPaths.clear();
      } else {
        _selectedVlogPaths = projects.map((p) => p.id).toList();
      }
    });
    hapticFeedback();
  }

  // ... 

  Future<void> _handleMoveOrCopy(bool isMove) async {
    if (!isMove) {
      Fluttertoast.showToast(msg: "복사 기능은 준비중입니다.");
       setState(() {
        _isVlogSelectionMode = false;
        _selectedVlogPaths.clear();
      });
      return;
    }

    // Show Folder Selection Dialog
    final folders = videoManager.vlogAlbums.where((f) => f != "휴지통" && f != videoManager.currentVlogFolder).toList();
    if (folders.isEmpty) {
      Fluttertoast.showToast(msg: "이동할 다른 폴더가 없습니다.");
      return;
    }

    String? targetFolder = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("폴더 이동"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: folders.length,
            itemBuilder: (context, index) {
              return ListTile(
                leading: const Icon(Icons.folder),
                title: Text(folders[index]),
                onTap: () => Navigator.pop(context, folders[index]),
              );
            },
          ),
        ),
      ),
    );

    if (targetFolder != null) {
      final projects = videoManager.filteredProjects;
      for (var id in _selectedVlogPaths) {
        final project = projects.firstWhere((p) => p.id == id);
        await videoManager.moveProjectToFolder(project, targetFolder);
      }
      
      Fluttertoast.showToast(msg: "${_selectedVlogPaths.length}개 이동됨");
      setState(() {
        _isVlogSelectionMode = false;
        _selectedVlogPaths.clear();
      });
      hapticFeedback();
    }
  }
}
