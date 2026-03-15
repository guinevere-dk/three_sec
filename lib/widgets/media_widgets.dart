import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../utils/haptics.dart';

/// 📦 공용 미디어 위젯 컴포넌트
/// Library와 Project 화면에서 공통으로 사용하는 UI 요소들

class MediaWidgets {
  static const Color _libraryPrimaryBlue = Color(0xFF1A73E8);
  static const Color _mutedTrashRed = Color(0xFFC56D74);

  /// 비디오 진행바 (공용)
  static Widget buildVideoProgressBar({
    required Duration position,
    required Duration duration,
    required Function(Duration) onSeek,
  }) {
    String formatDuration(Duration d) {
      final milliseconds = d.inMilliseconds.clamp(0, 24 * 60 * 60 * 1000);
      final seconds = milliseconds ~/ 1000;
      String twoDigits(int n) => n.toString().padLeft(2, '0');
      final minutes = seconds ~/ 60;
      return "${minutes.toString().padLeft(2, '0')}:${twoDigits(seconds.remainder(60))}";
    }

    return Row(
      children: [
        Text(
          formatDuration(position),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        Expanded(
          child: Slider(
            value: position.inMilliseconds.toDouble().clamp(
              0,
              duration.inMilliseconds.toDouble(),
            ),
            min: 0.0,
            max: duration.inMilliseconds.toDouble(),
            activeColor: Colors.redAccent,
            onChanged: (v) => onSeek(Duration(milliseconds: v.toInt())),
          ),
        ),
        Text(
          formatDuration(duration),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    );
  }

  /// 폴더 아이템 빌더 (New Design: Card Style)
  static Widget buildFolderGridItem({
    required String folderName,
    required int clipCount,
    required bool isSelected,
    required bool canSelect,
    required bool isSelectionMode,
    required int gridColumnCount,
    required VoidCallback onTap,
    required VoidCallback? onLongPress,
    required IconData Function(String) getIcon,
    required Color Function(String) getColor,
  }) {
    final bool showSelectedState = isSelectionMode && isSelected;
    final Color folderColor = getColor(folderName);
    final bool compact = gridColumnCount > 4;

    return GestureDetector(
      onLongPress: canSelect ? onLongPress : null,
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: showSelectedState
                      ? _libraryPrimaryBlue
                      : Colors.transparent,
                  width: showSelectedState ? 4 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(16),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  if (compact)
                    Positioned(
                      top: 10,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Icon(
                          getIcon(folderName),
                          color: folderColor,
                          size: 20,
                        ),
                      ),
                    )
                  else
                    Center(
                      child: _buildAlbumFolderIcon(
                        folderName: folderName,
                        icon: getIcon(folderName),
                        color: folderColor,
                      ),
                    ),

                  if (compact)
                    Positioned(
                      left: 4,
                      right: 4,
                      bottom: 8,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            folderName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 9,
                              height: 1.05,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF333333),
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '$clipCount',
                            style: const TextStyle(
                              fontSize: 8,
                              color: Color(0xFF8F98A8),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (showSelectedState)
                    Positioned(
                      top: compact ? 6 : 10,
                      right: compact ? 6 : 10,
                      child: Icon(
                        Icons.check_circle,
                        color: _libraryPrimaryBlue,
                        size: compact ? 18 : 24,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 10),
            Text(
              folderName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                height: 1.15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF333333),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$clipCount',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF8F98A8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Widget _buildAlbumFolderIcon({
    required String folderName,
    required IconData icon,
    required Color color,
  }) {
    final bool usePlate = folderName == '일상' || folderName == '휴지통';
    if (usePlate) {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: color.withAlpha(24),
          borderRadius: BorderRadius.circular(18),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: color, size: 30),
      );
    }
    return Icon(icon, color: color, size: 40);
  }

  /// 클립/Project 아이템 빌더 (New Design: Thumbnail Style)
  static Widget buildMediaGridItem({
    required String path,
    required bool isSelected,
    required int selectIndex,
    required bool isSelectionMode,
    required int gridColumnCount,
    required bool isFavorite,
    bool benchmarkStyle = false,
    bool showDurationBadge = false,
    String? statusBadge,
    String? title, // Added
    String? subtitle, // Added
    required VoidCallback onTap,
    required VoidCallback onLongPress,
    required Future<Uint8List?> Function(String) getThumbnail,
    Future<Duration> Function(String)? getDuration,
  }) {
    final bool showSelectedState = isSelectionMode && isSelected;

    return GestureDetector(
      onLongPress: onLongPress,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: showSelectedState
              ? Border.all(color: _libraryPrimaryBlue, width: 4)
              : Border.all(color: Colors.transparent, width: 0),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail
            FutureBuilder<Uint8List?>(
              future: getThumbnail(path),
              builder: (c, s) => s.hasData
                  ? Image.memory(s.data!, fit: BoxFit.cover)
                  : Container(
                      color: benchmarkStyle
                          ? const Color(0xFFD6DBE2)
                          : Colors.grey[200],
                    ),
            ),

            if (showDurationBadge && getDuration != null)
              Positioned(
                left: 8,
                bottom: 8,
                child: FutureBuilder<Duration>(
                  future: getDuration(path),
                  builder: (context, snapshot) {
                    final duration = snapshot.data ?? Duration.zero;
                    if (duration == Duration.zero) {
                      return const SizedBox.shrink();
                    }
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(105),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _formatDurationShort(duration),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  },
                ),
              ),

            if (statusBadge != null && statusBadge.trim().isNotEmpty)
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _statusBadgeBackgroundColor(statusBadge),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: _isLoadingBadge(statusBadge)
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Icon(
                          _statusBadgeIcon(statusBadge),
                          color: Colors.white,
                          size: 14,
                        ),
                ),
              ),

            // Title & Subtitle Overlay (Bottom Gradient)
            if (title != null || subtitle != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withOpacity(0.8),
                        Colors.transparent,
                      ],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (title != null)
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ),

            // Duration Badge (Dummy for now as logic isn't passed, but styled)
            // Or Favorite Icon
            if (isFavorite)
              const Positioned(
                top: 8,
                right: 8,
                child: Icon(Icons.favorite, color: Colors.white, size: 16),
              ),

            // Selection Overlay
            if (showSelectedState)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: _libraryPrimaryBlue,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _libraryPrimaryBlue.withAlpha(90),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${selectIndex + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),

            if (isSelectionMode && !showSelectedState)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withAlpha(24),
                    border: Border.all(
                      color: Colors.white.withAlpha(170),
                      width: 1.2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _formatDurationShort(Duration d) {
    final int seconds = d.inSeconds;
    return '${seconds}s';
  }

  static bool _isLoadingBadge(String statusBadge) => statusBadge == '로딩중';

  static Color _statusBadgeBackgroundColor(String statusBadge) {
    switch (statusBadge) {
      case '동기화 실패':
        return const Color(0xCCD32F2F);
      case '동기화됨':
        return const Color(0xCC2E7D32);
      case '기기':
      case '잠김':
        return const Color(0xCC37474F);
      case '로딩중':
      default:
        return Colors.black.withAlpha(125);
    }
  }

  static IconData _statusBadgeIcon(String statusBadge) {
    switch (statusBadge) {
      case '동기화됨':
        return Icons.cloud_done_rounded;
      case '기기':
      case '잠김':
        return Icons.smartphone_rounded;
      case '동기화 실패':
        return Icons.error_outline_rounded;
      case '로딩중':
        return Icons.sync;
      default:
        return Icons.help_outline_rounded;
    }
  }

  static Widget buildLibrarySelectionPanel({
    required IconData transferIcon,
    required VoidCallback? onTransfer,
    bool showTransferButton = true,
    required VoidCallback? onCreateProject,
    GlobalKey? createProjectButtonKey,
    required VoidCallback? onFavorite,
    required VoidCallback? onCopy,
    required VoidCallback? onMove,
    required VoidCallback onDelete,
    IconData favoriteIcon = Icons.favorite_border_rounded,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(246),
        borderRadius: BorderRadius.circular(33),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(24),
            blurRadius: 24,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 1) 즐겨찾기
            _buildPanelIconButton(favoriteIcon, onFavorite),
            const SizedBox(width: 3),

            // 2) 클라우드 업로드 / 로컬 이동 (보조)
            if (showTransferButton) ...[
              _buildPanelIconButton(transferIcon, onTransfer),
              const SizedBox(width: 6),
            ],

            // 3) Project 만들기 (메인 CTA)
            SizedBox(
              key: createProjectButtonKey,
              width: 72,
              height: 60,
              child: ElevatedButton(
                onPressed: onCreateProject,
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: _libraryPrimaryBlue,
                  disabledBackgroundColor: const Color(0xFFAAC5EE),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  padding: EdgeInsets.zero,
                ),
                child: const Icon(Icons.movie_creation_outlined, size: 33),
              ),
            ),
            const SizedBox(width: 6),

            // 4) 복사
            _buildPanelIconButton(Icons.content_copy_rounded, onCopy),
            const SizedBox(width: 3),

            // 5) 이동
            _buildPanelIconButton(Icons.drive_file_move_rounded, onMove),
            const SizedBox(width: 3),

            // 6) 삭제
            _buildPanelIconButton(
              Icons.delete_outline_rounded,
              onDelete,
              color: _mutedTrashRed,
            ),
          ],
        ),
      ),
    );
  }

  static Widget buildProjectSelectionPanel({
    required VoidCallback? onFavorite,
    required VoidCallback? onCopy,
    required VoidCallback? onMove,
    required VoidCallback onDelete,
    IconData favoriteIcon = Icons.favorite_border_rounded,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(246),
        borderRadius: BorderRadius.circular(33),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(24),
            blurRadius: 24,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildPanelIconButton(favoriteIcon, onFavorite),
            const SizedBox(width: 3),
            _buildPanelIconButton(Icons.content_copy_rounded, onCopy),
            const SizedBox(width: 3),
            _buildPanelIconButton(Icons.drive_file_move_rounded, onMove),
            const SizedBox(width: 3),
            _buildPanelIconButton(
              Icons.delete_outline_rounded,
              onDelete,
              color: _mutedTrashRed,
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildPanelIconButton(
    IconData icon,
    VoidCallback? onTap, {
    Color color = const Color(0xFF4B5563),
  }) {
    final effectiveColor = onTap == null ? color.withAlpha(120) : color;
    return SizedBox(
      width: 54,
      height: 54,
      child: IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 54, minHeight: 54),
        icon: Icon(icon, color: effectiveColor, size: 33),
        splashRadius: 27,
      ),
    );
  }

  /// 하단 액션 패널 (즐겨찾기, 이동, 복사, 삭제)
  static Widget buildActionPanel({
    required bool isTrashMode,
    required VoidCallback? onFavorite,
    required VoidCallback onMove,
    required VoidCallback onCopy,
    required VoidCallback onDelete,
    required VoidCallback? onRestore,

    required VoidCallback? onCreateProject, // ✅ 복원됨
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(246),
        borderRadius: BorderRadius.circular(33),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(24),
            blurRadius: 24,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: isTrashMode
              ? [
                  _buildPanelIconButton(
                    Icons.settings_backup_restore_rounded,
                    onRestore,
                    color: _libraryPrimaryBlue,
                  ),
                  const SizedBox(width: 6),
                  _buildPanelIconButton(
                    Icons.delete_forever_rounded,
                    onDelete,
                    color: _mutedTrashRed,
                  ),
                ]
              : [
                  if (onFavorite != null) ...[
                    _buildSimpleAction(
                      Icons.star_outline_rounded,
                      const Color(0xFF94A3B8),
                      onFavorite,
                    ),
                    const SizedBox(width: 6),
                  ],
                  _buildSimpleAction(
                    Icons.content_copy_rounded,
                    const Color(0xFF94A3B8),
                    onCopy,
                  ),
                  const SizedBox(width: 6),
                  if (onCreateProject != null)
                    SizedBox(
                      width: 126,
                      height: 84,
                      child: ElevatedButton(
                        onPressed: onCreateProject,
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: _libraryPrimaryBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(27),
                          ),
                        ),
                        child: const Icon(
                          Icons.movie_creation_outlined,
                          size: 36,
                        ),
                      ),
                    ),
                  if (onCreateProject != null) const SizedBox(width: 6),
                  _buildSimpleAction(
                    Icons.drive_file_move_rounded,
                    const Color(0xFF94A3B8),
                    onMove,
                  ),
                  const SizedBox(width: 6),
                  _buildSimpleAction(
                    Icons.delete_outline_rounded,
                    _mutedTrashRed,
                    onDelete,
                  ),
                ],
        ),
      ),
    );
  }

  static Widget _buildSimpleAction(
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        child: Icon(icon, color: color, size: 45),
      ),
    );
  }

  /// 좌측 사이드바 빌더
  static Widget buildNarrowSidebar({
    required double headerHeight,
    required List<String> folderList,
    required String currentFolder,
    required VoidCallback onBackToGrid,
    required Function(String) onFolderTap,
  }) {
    return SafeArea(
      child: Column(
        children: [
          SizedBox(
            height: headerHeight,
            child: Center(
              child: IconButton(
                icon: const Icon(Icons.grid_view_rounded, size: 22),
                onPressed: onBackToGrid,
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Colors.black12),
          Expanded(
            child: ListView.builder(
              itemCount: folderList.length,
              itemBuilder: (context, index) {
                final name = folderList[index];
                bool isSelected = currentFolder == name;
                return GestureDetector(
                  onTap: () {
                    if (currentFolder != name) {
                      hapticFeedback();
                      onFolderTap(name);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        Icon(
                          name == "휴지통" || name == "Project 휴지통"
                              ? Icons.delete_outline
                              : Icons.folder_rounded,
                          color: isSelected
                              ? Colors.blueAccent
                              : Colors.black26,
                          size: 26,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          name,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
