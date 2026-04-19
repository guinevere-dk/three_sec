import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

import '../widgets/media_widgets.dart';
import '../widgets/media_dialogs.dart';
import '../utils/haptics.dart';
import '../utils/media_selection_helper.dart';
import '../managers/video_manager.dart';
import '../managers/user_status_manager.dart';
import '../utils/quality_policy.dart';
import 'package:intl/intl.dart';
import '../models/vlog_project.dart';
import '../screens/video_edit_screen.dart';
import '../screens/paywall_screen.dart';

class ProjectScreen extends StatefulWidget {
  final Function() onRefresh;

  const ProjectScreen({super.key, required this.onRefresh});

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  bool _isInFolderDetail = false;
  bool _isProjectSelectionMode = false;
  bool _isFolderSelectionMode = false;
  bool _isDragAdding = true;
  int? _dragStartIndex;

  int _gridColumnCount = 3;
  bool _isZoomingLocked = false;

  final GlobalKey _projectGridKey = GlobalKey(debugLabel: 'projectGrid');
  final GlobalKey _folderGridKey = GlobalKey(debugLabel: 'folderGrid');

  final ScrollController _folderScrollController = ScrollController();
  final ScrollController _projectScrollController = ScrollController();

  List<String> _selectedProjectIds = [];
  Set<String> _selectedFolderNames = {};

  late VideoManager videoManager;

  Future<void> _openProjectWithTierRouting(VlogProject project) async {
    final userStatus = UserStatusManager();

    if (!userStatus.isStandardOrAbove()) {
      Fluttertoast.showToast(msg: '720p로 내보냅니다.');

      final audioConfig = <String, double>{
        for (final clip in project.clips) clip.path: 1.0,
      };

      final String mergeSessionId =
          'edit_${DateTime.now().millisecondsSinceEpoch}';

      final resultPath = await videoManager.exportVlog(
        clips: project.clips,
        audioConfig: audioConfig,
        bgmPath: project.bgmPath,
        bgmVolume: project.bgmVolume,
        quality: kQuality720p,
        userTier: kUserTierFree,
        mergeSessionId: mergeSessionId,
        debugTag: 'VlogScreen_free_export',
      );

      if (!mounted) return;

      if (resultPath != null) {
        Fluttertoast.showToast(msg: '720p vlog 영상이 갤러리에 저장되었습니다.');
      } else {
        Fluttertoast.showToast(msg: '내보내기에 실패했습니다. 다시 시도해주세요.');
      }
      widget.onRefresh();
      return;
    }

    final String mergeSessionId =
        'edit_${DateTime.now().millisecondsSinceEpoch}';
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoEditScreen(
          project: project,
          mergeSessionId: mergeSessionId,
        ),
      ),
    );
    if (!mounted) return;
    widget.onRefresh();
  }

  @override
  void dispose() {
    _folderScrollController.dispose();
    _projectScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    videoManager = Provider.of<VideoManager>(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (_isProjectSelectionMode)
          setState(() {
            _isProjectSelectionMode = false;
            _selectedProjectIds.clear();
          });
        else if (_isFolderSelectionMode)
          setState(() {
            _isFolderSelectionMode = false;
            _selectedFolderNames.clear();
          });
        else if (_isInFolderDetail)
          setState(() => _isInFolderDetail = false);
      },
      child: _isInFolderDetail ? _buildDetailView() : _buildFolderListTab(),
    );
  }

  Future<void> _loadVlogsFromCurrentFolder() async {
    await videoManager.loadProjects();
    if (mounted) setState(() {});
  }

  Future<void> _openPaywallAndRefresh() async {
    final upgraded = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PaywallScreen()),
    );

    if (upgraded != true) {
      return;
    }

    await UserStatusManager().initialize();
    if (!mounted) return;
    setState(() {});
  }

  int _projectCountInFolder(String folderName) {
    return videoManager.vlogProjects
        .where((p) => p.folderName == folderName)
        .length;
  }

  String? _projectStatusBadge(VlogProject project) {
    final cloudId = project.cloudProjectId;
    if (cloudId != null && cloudId.trim().isNotEmpty) {
      return '동기화됨';
    }
    return null;
  }

  Widget _buildFolderListTab() {
    final allFolders = videoManager.vlogAlbums.where((f) => f != "일상").toList();
    final selectableFolders = allFolders
        .where((f) => f != "기본" && f != "휴지통")
        .toList();
    final bool isAll =
        _selectedFolderNames.length == selectableFolders.length &&
        _selectedFolderNames.isNotEmpty;

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
          controller: _folderScrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              backgroundColor: const Color(0xFFF4F6F8),
              surfaceTintColor: Colors.transparent,
              pinned: true,
              floating: false,
              centerTitle: false,
              toolbarHeight: 88,
              title: Text(
                _isFolderSelectionMode
                    ? "${_selectedFolderNames.length}개 선택됨"
                    : "Project",
                style: const TextStyle(
                  color: Color(0xFF303236),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.1,
                ),
              ),
              actions: [
                if (_isFolderSelectionMode)
                  IconButton(
                    icon: Icon(
                      isAll ? Icons.check_box : Icons.check_box_outline_blank,
                      color: Colors.black,
                    ),
                    onPressed: _toggleSelectAllFolders,
                  )
                else ...[
                  // PRO Badge
                  GestureDetector(
                    onTap: _openPaywallAndRefresh,
                    child: Container(
                      margin: const EdgeInsets.only(right: 12),
                      width: 25,
                      height: 25,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF4CF00),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.star,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.black, size: 21),
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
                            "No Project folders.\nAdd one to start!",
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
                        final folderName = allFolders[index];
                        final isSelected = _selectedFolderNames.contains(
                          folderName,
                        );
                        final canSelect =
                            folderName != "기본" && folderName != "휴지통";

                        return MediaWidgets.buildFolderGridItem(
                          folderName: folderName,
                          clipCount: _projectCountInFolder(folderName),
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
                                _selectedProjectIds.clear();
                                _isProjectSelectionMode = false;
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
                      }, childCount: allFolders.length),
                    ),
                  ),
          ],
        ),
      ),
      floatingActionButton:
          _isFolderSelectionMode && _selectedFolderNames.isNotEmpty
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
      backgroundColor: const Color(0xFFF4F6F8),
      body: GestureDetector(
        key: _projectGridKey, // Restore Key
        onScaleStart: (d) {
          _isZoomingLocked = false;
          if (_isProjectSelectionMode && d.pointerCount == 1) {
            _startDragSelection(d.focalPoint, true);
          }
        },
        onScaleUpdate: (d) => _handleScaleUpdate(d, true),
        onScaleEnd: (_) => _dragStartIndex = null,
        child: Stack(
          children: [
            CustomScrollView(
              controller: _projectScrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverAppBar(
                  backgroundColor: Colors.white.withOpacity(0.92),
                  surfaceTintColor: Colors.transparent,
                  pinned: true,
                  toolbarHeight: 74,
                  leading: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.black,
                    ),
                    onPressed: () {
                      if (_isProjectSelectionMode) {
                        setState(() {
                          _isProjectSelectionMode = false;
                          _selectedProjectIds.clear();
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
                        _isProjectSelectionMode
                            ? "${_selectedProjectIds.length}개 선택됨"
                            : videoManager.currentVlogFolder,
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          height: 0.98,
                          letterSpacing: -1.1,
                        ),
                      ),
                      if (!_isProjectSelectionMode)
                        Text(
                          "${projects.length} Projects",
                          style: TextStyle(
                            color: const Color(0xFF94A3B8),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                          ),
                        ),
                    ],
                  ),
                  actions: [
                    if (_isProjectSelectionMode)
                      IconButton(
                        icon: Icon(
                          _selectedProjectIds.length == projects.length
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          color: Colors.black,
                        ),
                        onPressed: _toggleSelectAllProjects,
                      ),
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
                            "No Projects.\nMerge clips to create one!",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 150),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _gridColumnCount,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                        childAspectRatio: 1.0,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final project = projects[index];
                        final isSelected = _selectedProjectIds.contains(
                          project.id,
                        );
                        final int selectIdx = _selectedProjectIds.indexOf(
                          project.id,
                        );

                        return MediaWidgets.buildMediaGridItem(
                          // Thumbnail from first clip
                          path: project.clips.isNotEmpty
                              ? project.clips.first.path
                              : '',
                          isSelected: isSelected,
                          selectIndex: selectIdx,
                          isSelectionMode: _isProjectSelectionMode,
                          gridColumnCount: _gridColumnCount,
                          isFavorite: false, // Favorites removed for Vlogs
                          benchmarkStyle: true,
                          showDurationBadge: true,
                          statusBadge: _projectStatusBadge(project),
                          subtitle:
                              "${DateFormat('MM/dd').format(project.updatedAt)} • ${project.clips.length} clips",
                          title: project.title,
                          onTap: () {
                            if (_isProjectSelectionMode) {
                              setState(() {
                                if (isSelected) {
                                  _selectedProjectIds.remove(project.id);
                                } else {
                                  _selectedProjectIds.add(project.id);
                                }
                              });
                            } else {
                              _openProjectWithTierRouting(project);
                            }
                          },
                          onLongPress: () {
                            setState(() {
                              _isProjectSelectionMode = true;
                              _dragStartIndex = index;
                              _isDragAdding = !isSelected;
                              if (_isDragAdding) {
                                _selectedProjectIds.add(project.id);
                              } else {
                                _selectedProjectIds.remove(project.id);
                              }
                            });
                            hapticFeedback();
                          },
                          getThumbnail: videoManager.getThumbnail,
                          getDuration: videoManager.getVideoDuration,
                        );
                      }, childCount: projects.length),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      floatingActionButton:
          (_isProjectSelectionMode && _selectedProjectIds.isNotEmpty)
          ? MediaWidgets.buildActionPanel(
              isTrashMode: videoManager.currentVlogFolder == "휴지통",
              onCreateProject: null,
              onFavorite: null, // Removed favorite action
              onMove: () => _handleMoveOrCopy(true),
              // Copy not requested for folders phase, but keeping placeholder or removing?
              // User said: "moveProjectToFolder(VlogProject project, String targetFolder) 메서드를 구현해라."
              // and in Step 3: "_handleMoveOrCopy에서 폴더 선택 후 videoManager.moveProjectToFolder를 호출하도록 연결해라."
              // Assuming Copy is not priority or should behave like Move (duplicate then move?)
              // For now, let's keep Copy as void or implementing duplication later if needed.
              // Logic changes: _handleMoveOrCopy implemented below.
              onCopy: () => _handleMoveOrCopy(false),
              onDelete: _handleProjectBatchDelete,
              onRestore: () async {
                final projectMap = {for (final p in projects) p.id: p};
                for (var id in _selectedProjectIds) {
                  final p = projectMap[id];
                  if (p != null) {
                    await videoManager.restoreProjectFromTrash(p);
                  }
                }
                await videoManager.loadProjects();
                setState(() {
                  _isProjectSelectionMode = false;
                  _selectedProjectIds.clear();
                });
                hapticFeedback();
              },
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  // --- [제스처 처리] ---

  void _startDragSelection(Offset position, bool isProject) {
    final folderItems = videoManager.vlogAlbums
        .where((f) => f != "일상")
        .toList();
    final projectItems = videoManager.filteredProjects
        .map((p) => p.id)
        .toList();
    final targetList = isProject ? projectItems : folderItems;

    double topPad = MediaQuery.of(context).padding.top + kToolbarHeight;
    final controller = isProject
        ? _projectScrollController
        : _folderScrollController;
    double currentScroll = controller.hasClients ? controller.offset : 0.0;

    MediaSelectionHelper.startDragSelection(
      focalPoint: position,
      gridKey: isProject ? _projectGridKey : _folderGridKey,
      columnCount: _gridColumnCount,
      childAspectRatio: isProject ? 1.0 : (_gridColumnCount == 5 ? 0.7 : 0.85),
      targetList: targetList,
      currentSelection: isProject ? _selectedProjectIds : _selectedFolderNames,
      scrollOffset: currentScroll,
      topPadding: topPad,
      onSelectionChanged: (item, isAdding) {
        setState(() {
          if (isProject) {
            if (isAdding) {
              _selectedProjectIds.add(item);
            } else {
              _selectedProjectIds.remove(item);
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
      canSelectItem: isProject ? null : (item) => item != "기본" && item != "휴지통",
    );
  }

  void _handleScaleUpdate(ScaleUpdateDetails details, bool isProject) {
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
    final isActive = isProject
        ? _isProjectSelectionMode
        : _isFolderSelectionMode;
    if (!isActive) return;

    final folderItems = videoManager.vlogAlbums
        .where((f) => f != "일상")
        .toList();
    final projectItems = videoManager.filteredProjects
        .map((p) => p.id)
        .toList();
    final targetList = isProject ? projectItems : folderItems;

    double topPad = MediaQuery.of(context).padding.top + kToolbarHeight;
    final controller = isProject
        ? _projectScrollController
        : _folderScrollController;
    double currentScroll = controller.hasClients ? controller.offset : 0.0;

    setState(() {
      MediaSelectionHelper.updateDragSelection(
        focalPoint: details.focalPoint,
        gridKey: isProject ? _projectGridKey : _folderGridKey,
        columnCount: _gridColumnCount,
        childAspectRatio: isProject
            ? 1.0
            : (_gridColumnCount == 5 ? 0.7 : 0.85),
        targetList: targetList,
        currentSelection: isProject
            ? _selectedProjectIds
            : _selectedFolderNames,
        dragStartIndex: _dragStartIndex ?? -1,
        isDragAdding: _isDragAdding,
        scrollOffset: currentScroll,
        topPadding: topPad,
        canSelectItem: isProject
            ? null
            : (item) => item != "기본" && item != "휴지통",
      );
    });
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
    String? name = await MediaDialogs.showCreateProjectFolderDialog(
      context: context,
    );
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
      content: "폴더는 삭제되고 Project는 휴지통으로 이동합니다.",
    );
    if (ok == true) {
      await videoManager.deleteVlogAlbums(_selectedFolderNames);
      setState(() {
        _isFolderSelectionMode = false;
        _selectedFolderNames.clear();
      });
      await videoManager.initAlbumSystem();
      if (mounted) setState(() {});
    }
  }

  Future<void> _handleProjectBatchDelete() async {
    bool isTrash = videoManager.currentVlogFolder == "휴지통";
    if (isTrash) {
      bool? ok = await MediaDialogs.showConfirmDialog(
        context: context,
        title: "영구 삭제",
        content: "선택한 Project를 영구 삭제할까요? 복구할 수 없습니다.",
      );
      if (ok != true) return;
      for (var id in _selectedProjectIds) await videoManager.deleteProject(id);
    } else {
      bool? ok = await MediaDialogs.showConfirmDialog(
        context: context,
        title: "프로젝트 삭제",
        content: "선택한 프로젝트를 휴지통으로 이동할까요?",
      );
      if (ok != true) return;

      for (var id in _selectedProjectIds) {
        await videoManager.moveProjectToTrash(id);
      }
      Fluttertoast.showToast(msg: "휴지통으로 이동되었습니다");
    }
    setState(() {
      _isProjectSelectionMode = false;
      _selectedProjectIds.clear();
    });
    await videoManager.loadProjects();
    hapticFeedback();
  }

  void _toggleSelectAllProjects() {
    setState(() {
      final projects = videoManager.filteredProjects;
      if (_selectedProjectIds.length == projects.length) {
        _selectedProjectIds.clear();
      } else {
        _selectedProjectIds = projects.map((p) => p.id).toList();
      }
    });
    hapticFeedback();
  }

  // ...

  Future<void> _handleMoveOrCopy(bool isMove) async {
    if (!isMove) {
      Fluttertoast.showToast(msg: "복사 기능은 준비중입니다.");
      setState(() {
        _isProjectSelectionMode = false;
        _selectedProjectIds.clear();
      });
      return;
    }

    // Show Folder Selection Dialog
    final folders = videoManager.vlogAlbums
        .where((f) => f != "휴지통" && f != videoManager.currentVlogFolder)
        .toList();
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
      final projectMap = {for (final p in projects) p.id: p};
      for (var id in _selectedProjectIds) {
        final project = projectMap[id];
        if (project != null) {
          await videoManager.moveProjectToFolder(project, targetFolder);
        }
      }
      await videoManager.loadProjects();

      Fluttertoast.showToast(msg: "${_selectedProjectIds.length}개 이동됨");
      setState(() {
        _isProjectSelectionMode = false;
        _selectedProjectIds.clear();
      });
      hapticFeedback();
    }
  }
}
