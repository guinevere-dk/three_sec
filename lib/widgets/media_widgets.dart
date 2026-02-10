import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../utils/haptics.dart';

/// 📦 공용 미디어 위젯 컴포넌트
/// Library와 Vlog 화면에서 공통으로 사용하는 UI 요소들

class MediaWidgets {
  /// 비디오 진행바 (공용)
  static Widget buildVideoProgressBar({
    required Duration position,
    required Duration duration,
    required Function(Duration) onSeek,
  }) {
    String formatDuration(Duration d) {
      String twoDigits(int n) => n.toString().padLeft(2, '0');
      return "${d.inMinutes}:${twoDigits(d.inSeconds.remainder(60))}";
    }

    return Row(
      children: [
        Text(
          formatDuration(position),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        Expanded(
          child: Slider(
            value: position.inMilliseconds
                .toDouble()
                .clamp(0, duration.inMilliseconds.toDouble()),
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
    // Selection Visuals
    final bool showSelectedState = isSelectionMode && isSelected;
    final Color folderColor = getColor(folderName);
    
    return GestureDetector(
      onLongPress: canSelect ? onLongPress : null,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24), // rounded-3xl
          border: showSelectedState
              ? Border.all(color: Colors.blueAccent, width: 3) // Thick Blue Border
              : Border.all(color: Colors.grey.shade100, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Main Content
            if (gridColumnCount > 4)
              // Compact Mode (5+ columns): Icon Only + Badge
              Stack(
                alignment: Alignment.center,
                children: [
                  // Icon pushed down slightly to avoid badge overlap
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Icon(
                      getIcon(folderName),
                      color: folderColor,
                      size: 24, // Reduced from 32
                    ),
                  ),
                  if (clipCount > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          clipCount > 99 ? '99+' : '$clipCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              )
            else
              // Standard Mode: Icon + Text
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Icon Container
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: folderColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20), // rounded-2xl
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      getIcon(folderName),
                      color: folderColor,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Title
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      folderName,
                      style: const TextStyle(
                        fontSize: 14, // Slightly reduced
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B), // Slate-800
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis, // Critical
                    ),
                  ),
                  const SizedBox(height: 4),
                  
                  // Count
                  Text(
                    '$clipCount items',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[400], // Slate-400
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            
            // Selection Overlay
            if (showSelectedState)
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.1), // Dark overlay
                  borderRadius: BorderRadius.circular(21), // Inner radius match
                ),
                child: const Center(
                  child: Icon(Icons.check_circle, color: Colors.blueAccent, size: 32),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 클립/Vlog 아이템 빌더 (New Design: Thumbnail Style)
  static Widget buildMediaGridItem({
    required String path,
    required bool isSelected,
    required int selectIndex,
    required bool isSelectionMode,
    required int gridColumnCount,
    required bool isFavorite,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
    required Future<Uint8List?> Function(String) getThumbnail,
  }) {
    final bool showSelectedState = isSelectionMode && isSelected;

    return GestureDetector(
      onLongPress: onLongPress,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12), // rounded-xl
          border: showSelectedState
              ? Border.all(color: Colors.blueAccent, width: 3) // Thick Blue Border
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
                  : Container(color: Colors.grey[200]),
            ),
            
            // Duration Badge (Dummy for now as logic isn't passed, but styled)
            // Or Favorite Icon
            if (isFavorite)
              const Positioned(
                bottom: 8,
                left: 8,
                child: Icon(Icons.favorite, color: Colors.white, size: 16),
              ),

            // Selection Overlay
            if (showSelectedState) ...[
              Container(color: Colors.black.withOpacity(0.4)), // Darker Overlay
              Center(
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: Colors.blueAccent,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${selectIndex + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ] else if (isSelectionMode) ...[
               // Unselected state in multi-select mode: subtle overlay to indicate "not selected"
               Container(color: Colors.white.withOpacity(0.3)),
            ]
          ],
        ),
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

    required VoidCallback? onCreateVlog, // ✅ 복원됨
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            blurRadius: 25,
            color: Colors.black.withOpacity(0.1),
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: SingleChildScrollView( 
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center, 
          children: isTrashMode
              ? [
                  _buildSimpleAction(Icons.settings_backup_restore, Colors.blueAccent, onRestore ?? () {}),
                  const SizedBox(width: 12),
                  _buildSimpleAction(Icons.delete_forever, Colors.redAccent, onDelete),
                ]
              : [
                  // Vlog Create (Magic Brush) - Most Prominent
                  if (onCreateVlog != null) ...[
                    _buildSimpleAction(Icons.auto_awesome, Colors.deepPurpleAccent, onCreateVlog),
                    Container(height: 24, width: 1, color: Colors.grey[200], margin: const EdgeInsets.symmetric(horizontal: 4)),
                  ],

                  if (onFavorite != null)
                    _buildSimpleAction(Icons.favorite, Colors.pinkAccent, onFavorite),
                  const SizedBox(width: 4), 
                  _buildSimpleAction(Icons.drive_file_move, Colors.blue, onMove),
                  const SizedBox(width: 4),
                  _buildSimpleAction(Icons.content_copy, Colors.teal, onCopy),
                  const SizedBox(width: 4),
                  _buildSimpleAction(Icons.delete, Colors.redAccent, onDelete),
                ],
        ),
      ),
    );
  }

  static Widget _buildSimpleAction(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), // 패딩 축소 (18 -> 14)
        child: Icon(icon, color: color, size: 28),
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
                          name == "휴지통" || name == "Vlog 휴지통" 
                              ? Icons.delete_outline 
                              : Icons.folder_rounded,
                          color: isSelected ? Colors.blueAccent : Colors.black26,
                          size: 26,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          name,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 9),
                        )
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
