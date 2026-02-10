import 'package:flutter/material.dart';

/// 💬 공용 다이얼로그
/// Library와 Vlog 화면에서 공통으로 사용하는 다이얼로그들

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
  }) async {
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(isMove ? "이동" : "복사"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_circle, color: Colors.blueAccent),
              title: const Text("새 폴더 만들기"),
              onTap: () => Navigator.pop(c, "NEW"),
            ),
            const Divider(),
            ...folderList
                .where((a) => a != currentFolder && !excludeFolders.contains(a))
                .map((a) => ListTile(
                      title: Text(a),
                      onTap: () => Navigator.pop(c, a),
                    ))
          ],
        ),
      ),
    );
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

  /// Vlog 폴더 생성 다이얼로그 (Vlog 전용)
  static Future<String?> showCreateVlogFolderDialog({
    required BuildContext context,
  }) {
    return showCreateFolderDialog(
      context: context,
      title: "새 Vlog 폴더",
    );
  }
}
