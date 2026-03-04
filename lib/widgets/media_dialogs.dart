import 'package:flutter/material.dart';

/// 💬 공용 다이얼로그
/// Library와 Project 화면에서 공통으로 사용하는 다이얼로그들

class MediaDialogs {
  /// 폴더 생성 다이얼로그
  static Future<String?> showCreateFolderDialog({
    required BuildContext context,
    required String title,
  }) async {
    String input = "";
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          onChanged: (v) => input = v,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(
            hintText: "폴더 이름 입력",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("취소"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, input),
            child: const Text("확정"),
          )
        ],
      ),
    );
  }

  /// 확인 다이얼로그
  static Future<bool?> showConfirmDialog({
    required BuildContext context,
    required String title,
    required String content,
    String confirmText = "확인",
    Color confirmColor = Colors.red,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text("취소"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(confirmText, style: TextStyle(color: confirmColor)),
          )
        ],
      ),
    );
  }

  /// 이동/복사 대상 폴더 선택 다이얼로그
  static Future<String?> showMoveOrCopyDialog({
    required BuildContext context,
    required bool isMove,
    required List<String> folderList,
    required String currentFolder,
    required List<String> excludeFolders, // 휴지통 등 제외할 폴더
    String createLabel = 'Create New Album',
    IconData createIcon = Icons.add,
    bool showItemSubtitle = true,
    String Function(String folderName)? itemSubtitleBuilder,
  }) async {
    final candidates = folderList
        .where((a) => a != currentFolder && !excludeFolders.contains(a))
        .toList();

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF6F7F9),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 96,
                height: 7,
                decoration: BoxDecoration(
                  color: const Color(0xFFC9CED6),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        isMove ? 'Move to...' : 'Copy to...',
                        style: const TextStyle(
                          fontSize: 44 / 2,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF131D31),
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(c),
                      icon: const Icon(
                        Icons.close,
                        size: 36,
                        color: Color(0xFF6E7785),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => Navigator.pop(c, "NEW"),
                  child: Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDFE5EF),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Icon(
                          createIcon,
                          size: 30,
                          color: Color(0xFF3B82F6),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        createLabel,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF3B82F6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Divider(height: 1, color: Color(0xFFD5DAE2)),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 16),
                  itemCount: candidates.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final album = candidates[index];
                    final iconColor = _albumColorByIndex(index);
                    final subtitleText = itemSubtitleBuilder?.call(album);
                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      leading: Icon(
                        Icons.folder,
                        color: iconColor,
                        size: 44,
                      ),
                      title: Text(
                        album,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF161F32),
                        ),
                      ),
                      subtitle: showItemSubtitle && subtitleText != null
                          ? Text(
                              subtitleText,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Color(0xFF687386),
                                fontWeight: FontWeight.w500,
                              ),
                            )
                          : null,
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: Color(0xFFA2AAB7),
                        size: 34,
                      ),
                      onTap: () => Navigator.pop(c, album),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _albumColorByIndex(int index) {
    const colors = [
      Color(0xFFF4C500),
      Color(0xFF78D89A),
      Color(0xFFF3B162),
      Color(0xFFB997E8),
      Color(0xFF8AC0FF),
    ];
    return colors[index % colors.length];
  }

  /// 앨범 생성 다이얼로그 (라이브러리 전용)
  static Future<String?> showCreateAlbumDialog({
    required BuildContext context,
  }) {
    return showCreateFolderDialog(
      context: context,
      title: "새 앨범",
    );
  }

  /// Project 폴더 생성 다이얼로그 (Project 전용)
  static Future<String?> showCreateProjectFolderDialog({
    required BuildContext context,
  }) {
    return showCreateFolderDialog(
      context: context,
      title: "새 Project 폴더",
    );
  }
}
