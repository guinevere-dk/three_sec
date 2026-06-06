import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

import '../widgets/media_widgets.dart';
import '../widgets/media_dialogs.dart';
import '../utils/haptics.dart';
import '../utils/media_selection_helper.dart';
import '../managers/video_manager.dart';
import '../managers/user_status_manager.dart';
import '../theme/moa_design_tokens.dart';
import '../utils/quality_policy.dart';
import 'package:intl/intl.dart';
import '../models/vlog_project.dart';
import '../screens/video_edit_screen.dart';

class ProjectScreen extends StatefulWidget {
  final Function() onRefresh;
  final bool isActive;
  final VoidCallback onOpenSubscriptionManagement;

  const ProjectScreen({
    super.key,
    required this.onRefresh,
    required this.isActive,
    required this.onOpenSubscriptionManagement,
  });

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
  bool _isFreeExporting = false;

  Future<void> _openProjectWithTierRouting(VlogProject project) async {
    final userStatus = UserStatusManager();

    if (!userStatus.isStandardOrAbove()) {
      if (_isFreeExporting) return;
      setState(() => _isFreeExporting = true);
      Fluttertoast.showToast(msg: '720p로 내보냅니다.');

      final audioConfig = <String, double>{
        for (final clip in project.clips) clip.path: 1.0,
      };

      final String mergeSessionId =
          'edit_${DateTime.now().millisecondsSinceEpoch}';

      String? resultPath;
      try {
        resultPath = await videoManager.exportVlog(
          clips: project.clips,
          audioConfig: audioConfig,
          bgmPath: project.bgmPath,
          bgmVolume: project.bgmVolume,
          quality: kQuality720p,
          userTier: kUserTierFree,
          mergeSessionId: mergeSessionId,
          debugTag: 'ProjectScreen_free_export',
        );
      } finally {
        if (mounted) {
          setState(() => _isFreeExporting = false);
        }
      }

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
        builder: (_) =>
            VideoEditScreen(project: project, mergeSessionId: mergeSessionId),
      ),
    );
    if (!mounted) return;
    widget.onRefresh();
  }

  @override
  void didUpdateWidget(covariant ProjectScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      setState(_resetTransientState);
    }
  }

  void _resetTransientState() {
    _isInFolderDetail = false;
    _isProjectSelectionMode = false;
    _isFolderSelectionMode = false;
    _isDragAdding = true;
    _dragStartIndex = null;
    _gridColumnCount = 3;
    _isZoomingLocked = false;
    _selectedProjectIds.clear();
    _selectedFolderNames.clear();
    _isFreeExporting = false;
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
        if (_isProjectSelectionMode) {
          setState(() {
            _isProjectSelectionMode = false;
            _selectedProjectIds.clear();
          });
        } else if (_isFolderSelectionMode) {
          setState(() {
            _isFolderSelectionMode = false;
            _selectedFolderNames.clear();
          });
        } else if (_isInFolderDetail) {
          setState(() => _isInFolderDetail = false);
        }
      },
      child: _isInFolderDetail ? _buildDetailView() : _buildFolderListTab(),
    );
  }

  Future<void> _loadProjectsFromCurrentFolder(String folderName) async {
    final activeFolder = folderName.trim();
    await videoManager.loadProjects();
    if (!mounted) return;
    if (_isInFolderDetail &&
        activeFolder.isNotEmpty &&
        videoManager.currentVlogFolder.isEmpty) {
      videoManager.currentVlogFolder = activeFolder;
    }
    setState(() {});
  }

  int _projectCountInFolder(String folderName) {
    return videoManager.projectCountInFolder(folderName);
  }

  bool _hasLocalProjectClip(VlogClip clip) {
    return !videoManager.isCloudOnlyPlaceholder(clip.path) &&
        File(clip.path).existsSync();
  }

  bool _hasCloudProjectClip(VlogClip clip) {
    return videoManager.isCloudOnlyPlaceholder(clip.path) ||
        videoManager.isClipCloudSynced(clip.path);
  }

  String _projectThumbnailPath(VlogProject project) {
    for (final clip in project.clips) {
      if (_hasLocalProjectClip(clip)) return clip.path;
    }

    for (final clip in project.clips) {
      if (videoManager.isCloudOnlyPlaceholder(clip.path) &&
          videoManager.hasCompletedCloudThumbnail(clip.path)) {
        return clip.path;
      }
    }

    for (final clip in project.clips) {
      if (videoManager.isCloudOnlyPlaceholder(clip.path)) return clip.path;
    }

    return project.clips.isNotEmpty ? project.clips.first.path : '';
  }

  bool _isProjectThumbnailCloudOnly(String path) {
    return path.isNotEmpty && videoManager.isCloudOnlyPlaceholder(path);
  }

  Future<Uint8List?> _getProjectThumbnail(String path) async {
    if (path.isEmpty) return null;
    if (videoManager.isCloudOnlyPlaceholder(path)) {
      return videoManager.getCloudThumbnail(path);
    }
    return videoManager.getThumbnail(path);
  }

  Future<Duration> _getProjectThumbnailDuration(String path) async {
    if (path.isEmpty) return Duration.zero;
    return videoManager.getVideoDuration(path);
  }

  String _projectSubtitle(VlogProject project) {
    final cloudClipCount = project.clips.where(_hasCloudProjectClip).length;
    final cloudText = cloudClipCount > 0 ? ' • Cloud $cloudClipCount' : '';
    return '${DateFormat('MM/dd').format(project.updatedAt)} • '
        '${project.clips.length} clips$cloudText';
  }

  String? _projectStatusBadge(VlogProject project) {
    if (project.clips.isNotEmpty &&
        project.clips.every(
          (clip) => videoManager.isCloudOnlyPlaceholder(clip.path),
        )) {
      return 'Cloud';
    }

    final cloudId = project.cloudProjectId;
    if (cloudId != null && cloudId.trim().isNotEmpty) {
      return '동기화됨';
    }
    return null;
  }

  Widget _buildFolderListTab() {
    final allFolders = videoManager.projectFolders.toList();
    final selectableFolders = allFolders
        .where((f) => f != "기본" && f != "휴지통")
        .toList();
    final isFreeUser = !UserStatusManager().isStandardOrAbove();
    final bool isAll =
        _selectedFolderNames.length == selectableFolders.length &&
        _selectedFolderNames.isNotEmpty;

    return Scaffold(
      backgroundColor: MoaDesignTokens.background,
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
              backgroundColor: MoaDesignTokens.background,
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
                  color: MoaDesignTokens.textPrimary,
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
                      color: MoaDesignTokens.textPrimary,
                    ),
                    onPressed: _toggleSelectAllFolders,
                  )
                else ...[
                  // PRO Badge
                  IconButton(
                    icon: const Icon(
                      Icons.add,
                      color: MoaDesignTokens.textPrimary,
                      size: 21,
                    ),
                    onPressed: _showCreateFolderDialog,
                  ),
                ],
              ],
            ),

            if (isFreeUser && !_isFolderSelectionMode)
              _buildStandardUpsellSliver(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
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
                              _loadProjectsFromCurrentFolder(folderName);
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
              backgroundColor: MoaDesignTokens.danger,
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
    final currentFolder = videoManager.currentVlogFolder;
    final projects = videoManager.projectsInFolder(currentFolder);
    final isFreeUser = !UserStatusManager().isStandardOrAbove();

    return Scaffold(
      backgroundColor: MoaDesignTokens.background,
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
                  backgroundColor: MoaDesignTokens.surface,
                  surfaceTintColor: Colors.transparent,
                  pinned: true,
                  toolbarHeight: 74,
                  leading: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: MoaDesignTokens.textPrimary,
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
                            : currentFolder,
                        style: const TextStyle(
                          color: MoaDesignTokens.textPrimary,
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
                            color: MoaDesignTokens.textMuted,
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
                          color: MoaDesignTokens.textPrimary,
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
                        final thumbnailPath = _projectThumbnailPath(project);
                        final isCloudThumbnail = _isProjectThumbnailCloudOnly(
                          thumbnailPath,
                        );

                        final item = MediaWidgets.buildMediaGridItem(
                          path: thumbnailPath,
                          isSelected: isSelected,
                          selectIndex: selectIdx,
                          isSelectionMode: _isProjectSelectionMode,
                          gridColumnCount: _gridColumnCount,
                          isFavorite: project.isFavorite,
                          benchmarkStyle: true,
                          showDurationBadge: true,
                          statusBadge: _projectStatusBadge(project),
                          isCloudOnly: isCloudThumbnail,
                          getCloudThumbnail: isCloudThumbnail
                              ? videoManager.getCloudThumbnail
                              : null,
                          subtitle: _projectSubtitle(project),
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
                          getThumbnail: _getProjectThumbnail,
                          getDuration: _getProjectThumbnailDuration,
                        );

                        if (!isFreeUser) return item;

                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            item,
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: _buildFreeExportButton(project),
                            ),
                          ],
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
          ? (videoManager.currentVlogFolder == "휴지통"
                ? MediaWidgets.buildActionPanel(
                    isTrashMode: true,
                    onCreateProject: null,
                    onFavorite: null,
                    onMove: () => _handleMoveOrCopy(true),
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
                : MediaWidgets.buildProjectSelectionPanel(
                    favoriteIcon: Icons.favorite_border_rounded,
                    onFavorite: () async {
                      await videoManager.toggleProjectFavoritesBatch(
                        _selectedProjectIds,
                      );
                      if (!mounted) return;
                      setState(() {
                        _isProjectSelectionMode = false;
                        _selectedProjectIds.clear();
                      });
                      hapticFeedback();
                    },
                    onCopy: () => _handleMoveOrCopy(false),
                    onMove: () => _handleMoveOrCopy(true),
                    onDelete: _handleProjectBatchDelete,
                  ))
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildStandardUpsellSliver({
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(14, 10, 14, 12),
  }) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: padding,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: MoaDesignTokens.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: MoaDesignTokens.stroke),
            boxShadow: MoaDesignTokens.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: MoaDesignTokens.accentSoft.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.workspace_premium_rounded,
                      color: MoaDesignTokens.accentStrong,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Standard 구독 시 Project 편집 가능',
                          style: TextStyle(
                            color: MoaDesignTokens.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          '무료 사용자는 프로젝트를 열지 않고 720p로 바로 내보낼 수 있습니다. Standard는 1080p 내보내기와 50GB Cloud 백업을 제공합니다.',
                          style: TextStyle(
                            color: MoaDesignTokens.textMuted,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StandardBenefitChip(label: '50GB Cloud 백업'),
                  _StandardBenefitChip(label: '1080p 내보내기'),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton.icon(
                  onPressed: widget.onOpenSubscriptionManagement,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                  label: const Text('구독하러가기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFreeExportButton(VlogProject project) {
    return SizedBox(
      height: 34,
      child: FilledButton(
        onPressed: _isFreeExporting
            ? null
            : () => _openProjectWithTierRouting(project),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF111827).withAlpha(220),
          disabledBackgroundColor: const Color(0xFF475569).withAlpha(160),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: Text(
          _isFreeExporting ? '내보내는 중' : '720p 내보내기',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  // --- [제스처 처리] ---

  void _startDragSelection(Offset position, bool isProject) {
    final folderItems = videoManager.projectFolders.toList();
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

    final folderItems = videoManager.projectFolders.toList();
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
      final selectable = videoManager.projectFolders
          .where((f) => f != "기본" && f != "휴지통")
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
      final folderName = videoManager.normalizeProjectFolderName(name);
      if (videoManager.projectFolders.contains(folderName)) return;
      await videoManager.createProjectFolder(folderName);
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
      await videoManager.deleteProjectFolders(_selectedFolderNames);
      setState(() {
        _isFolderSelectionMode = false;
        _selectedFolderNames.clear();
      });
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
      for (var id in _selectedProjectIds) {
        await videoManager.deleteProject(id);
      }
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
    await videoManager.loadProjects();
    if (!mounted) return;

    final String? result = await MediaDialogs.showMoveOrCopyDialog(
      context: context,
      isMove: isMove,
      folderList: videoManager.projectFolders,
      currentFolder: videoManager.currentVlogFolder,
      excludeFolders: const ["휴지통"],
      itemSubtitleBuilder: (folderName) {
        final count = videoManager.projectCountInFolder(folderName);
        return '$count projects';
      },
    );

    if (result == null) return;

    String targetFolder = result;

    if (result == "NEW") {
      if (!mounted) return;
      final String? name = await MediaDialogs.showCreateProjectFolderDialog(
        context: context,
      );
      if (name == null || name.trim().isEmpty) return;
      final createdFolder = await videoManager.createProjectFolder(name);
      if (createdFolder == null) return;
      targetFolder = createdFolder;
    }

    final selectedCount = _selectedProjectIds.length;
    final projects = videoManager.filteredProjects;
    final projectMap = {for (final p in projects) p.id: p};

    for (final id in _selectedProjectIds) {
      final project = projectMap[id];
      if (project == null) continue;

      if (isMove) {
        await videoManager.moveProjectToFolder(project, targetFolder);
      } else {
        await videoManager.copyProjectToFolder(project, targetFolder);
      }
    }

    await videoManager.loadProjects();
    if (!mounted) return;

    setState(() {
      _selectedProjectIds.clear();
      _isProjectSelectionMode = false;
    });

    Fluttertoast.showToast(
      msg: isMove ? "$selectedCount개 이동됨" : "$selectedCount개 복사됨",
    );
    hapticFeedback();
  }
}

class _StandardBenefitChip extends StatelessWidget {
  final String label;

  const _StandardBenefitChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: MoaDesignTokens.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: MoaDesignTokens.stroke),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: MoaDesignTokens.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
