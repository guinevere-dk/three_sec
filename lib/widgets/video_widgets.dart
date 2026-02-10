import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../widgets/media_widgets.dart';

/// 🎬 비디오 미리보기 위젯 (Library 탭에서 사용)
class VideoPreviewWidget extends StatefulWidget {
  final String filePath;
  final Set<String> favorites;
  final bool isTrashMode;
  final Function(String) onToggleFav;
  final Function(String) onRestore;
  final Function(String) onDelete;
  final VoidCallback onClose;

  const VideoPreviewWidget({
    super.key,
    required this.filePath,
    required this.favorites,
    required this.isTrashMode,
    required this.onToggleFav,
    required this.onRestore,
    required this.onDelete,
    required this.onClose,
  });

  @override
  State<VideoPreviewWidget> createState() => _VideoPreviewWidgetState();
}

class _VideoPreviewWidgetState extends State<VideoPreviewWidget> {
  late VideoPlayerController _vController;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _vController = VideoPlayerController.file(File(widget.filePath))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          _vController.setLooping(true);
          _vController.play();
        }
      });
    _vController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _vController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFav = widget.favorites.contains(widget.filePath);
    final duration = _vController.value.duration;
    final position = _vController.value.position;
    
    return GestureDetector(
      onTap: () => setState(() => _showControls = !_showControls),
      child: Positioned.fill(
        child: Container(
          color: Colors.black,
          child: Stack(
            children: [
              Center(
                child: _vController.value.isInitialized
                    ? AspectRatio(
                        aspectRatio: _vController.value.aspectRatio,
                        child: VideoPlayer(_vController),
                      )
                    : const CircularProgressIndicator(),
              ),
              if (_showControls) ...[
                Positioned(
                  top: 40,
                  left: 20,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: widget.onClose,
                  ),
                ),
                // ✅ 진행바 추가
                Positioned(
                  bottom: 100,
                  left: 20,
                  right: 20,
                  child: MediaWidgets.buildVideoProgressBar(
                    position: position,
                    duration: duration,
                    onSeek: (d) => _vController.seekTo(d),
                  ),
                ),
                Positioned(
                  bottom: 50,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(
                          widget.isTrashMode
                              ? Icons.settings_backup_restore
                              : (isFav ? Icons.favorite : Icons.favorite_border),
                          color: (isFav && !widget.isTrashMode) ? Colors.red : Colors.white,
                          size: 30,
                        ),
                        onPressed: () {
                          if (widget.isTrashMode) {
                            widget.onRestore(widget.filePath);
                          } else {
                            widget.onToggleFav(widget.filePath);
                            setState(() {});
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.white, size: 30),
                        onPressed: () => widget.onDelete(widget.filePath),
                      )
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 🎬 결과물 미리보기 위젯 (Vlog 탭에서 사용)
class ResultPreviewWidget extends StatefulWidget {
  final String videoPath;
  final VoidCallback onClose; // 필수: 닫기 버튼 콜백
  final VoidCallback? onShare; // 선택: 공유 버튼 콜백
  final VoidCallback? onEdit;  // 선택: 편집 버튼 콜백

  const ResultPreviewWidget({
    super.key,
    required this.videoPath,
    required this.onClose,
    this.onShare,
    this.onEdit,
  });

  @override
  State<ResultPreviewWidget> createState() => _ResultPreviewWidgetState();
}

class _ResultPreviewWidgetState extends State<ResultPreviewWidget> {
  late VideoPlayerController _controller;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          _controller.play();
          _controller.setLooping(true);
        }
      });
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = _controller.value.duration;
    final position = _controller.value.position;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: () => setState(() => _showControls = !_showControls),
              child: Center(
                child: _controller.value.isInitialized
                    ? AspectRatio(
                        aspectRatio: _controller.value.aspectRatio,
                        child: VideoPlayer(_controller),
                      )
                    : const CircularProgressIndicator(color: Colors.white24),
              ),
            ),
            if (_showControls) ...[
              Positioned(
                top: 20,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: widget.onClose,
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Colors.black87],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ✅ 공용 진행바 사용
                      MediaWidgets.buildVideoProgressBar(
                        position: position,
                        duration: duration,
                        onSeek: (d) => _controller.seekTo(d),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          if (widget.onShare != null)
                            _buildPremiumActionButton(Icons.share_rounded, "공유", widget.onShare!),
                          if (widget.onEdit != null)
                            _buildPremiumActionButton(Icons.auto_awesome, "편집", widget.onEdit!),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 💡 [Ver 2.8.6] 세련된 화이트 액션 버튼 위젯
  Widget _buildPremiumActionButton(IconData icon, String label, VoidCallback onTap) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          onPressed: onTap,
          backgroundColor: Colors.white,
          elevation: 0,
          child: Icon(icon, color: Colors.black87),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
