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
  VideoPlayerController? _vController;
  String? _initError;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _initializePreviewController();
  }

  @override
  void didUpdateWidget(covariant VideoPreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _initializePreviewController();
    }
  }

  Future<void> _initializePreviewController() async {
    final oldController = _vController;
    final file = File(widget.filePath);

    if (!file.existsSync()) {
      if (!mounted) return;
      setState(() {
        _vController = null;
        _initError = '파일을 찾을 수 없습니다.';
      });
      await oldController?.dispose();
      return;
    }

    final controller = VideoPlayerController.file(file);
    controller.addListener(() {
      if (mounted) setState(() {});
    });

    if (mounted) {
      setState(() {
        _vController = controller;
        _initError = null;
      });
    }

    await oldController?.dispose();

    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (!mounted || _vController != controller) return;
      setState(() {});
    } catch (_) {
      if (!mounted || _vController != controller) return;
      setState(() {
        _initError = '미리보기를 재생할 수 없습니다.';
      });
    }
  }

  @override
  void dispose() {
    _vController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFav = widget.favorites.contains(widget.filePath);
    final controller = _vController;
    final duration = controller?.value.duration ?? Duration.zero;
    final position = controller?.value.position ?? Duration.zero;
    final isInitialized = controller?.value.isInitialized ?? false;
    final isPlaying = controller?.value.isPlaying ?? false;
    
    return GestureDetector(
      onTap: () => setState(() => _showControls = !_showControls),
      child: SizedBox.expand(
        child: Container(
          color: Colors.black,
          child: Stack(
            children: [
              Center(
                child: _initError != null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _initError!,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _initializePreviewController,
                            child: const Text('다시 시도'),
                          ),
                        ],
                      )
                    : isInitialized
                    ? AspectRatio(
                        aspectRatio: controller!.value.aspectRatio,
                        child: VideoPlayer(controller),
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
                    onSeek: (d) => controller?.seekTo(d),
                  ),
                ),
                if (isInitialized && !isPlaying)
                  Positioned(
                    bottom: 160,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: IconButton(
                        icon: const Icon(
                          Icons.play_circle_fill,
                          size: 56,
                          color: Colors.white,
                        ),
                        onPressed: () => controller?.play(),
                      ),
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
  final VoidCallback? onOpenGallery; // 선택: 갤러리 이동 버튼 콜백
  final VoidCallback? onRetry; // 선택: 종료 버튼 콜백

  const ResultPreviewWidget({
    super.key,
    required this.videoPath,
    required this.onClose,
    this.onShare,
    this.onEdit,
    this.onOpenGallery,
    this.onRetry,
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
                          if (widget.onRetry != null)
                            _buildPremiumActionButton(Icons.close, "X 종료", widget.onRetry!),
                          if (widget.onEdit != null)
                            _buildPremiumActionButton(Icons.auto_awesome, "편집", widget.onEdit!),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(24),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          '갤러리 앱에 저장되었습니다.\n저장 경로: 갤러리/2S_Vlog',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
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
