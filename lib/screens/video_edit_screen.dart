import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:fluttertoast/fluttertoast.dart';

class SubtitleModel {
  String text;
  double dx;
  double dy;
  final double fontSize;

  SubtitleModel({
    required this.text,
    required this.dx,
    required this.dy,
    this.fontSize = 18.0,
  });
}

class StickerModel {
  String emoji;
  double dx;
  double dy;
  double scale;

  StickerModel({
    required this.emoji,
    required this.dx,
    required this.dy,
    this.scale = 1.0,
  });
}

enum FilterPreset { none, grayscale, warm, cool }

class VideoEditScreen extends StatefulWidget {
  final File? videoFile;
  final String? targetAlbum;

  const VideoEditScreen({
    super.key,
    this.videoFile,
    this.targetAlbum,
  });

  @override
  State<VideoEditScreen> createState() => _VideoEditScreenState();
}

class _VideoEditScreenState extends State<VideoEditScreen> {
  static const MethodChannel _platform = MethodChannel('com.dk.three_sec/video_engine');

  late VideoPlayerController _controller;
  bool _isInitialized = false;
  final List<SubtitleModel> _subtitles = [];
  final List<StickerModel> _stickers = [];
  FilterPreset _selectedFilter = FilterPreset.none;
  double _filterOpacity = 0.7;

  @override
  void initState() {
    super.initState();
    _initVideoPlayer();
  }

  Future<void> _initVideoPlayer() async {
    if (widget.videoFile != null) {
      _controller = VideoPlayerController.file(widget.videoFile!)
        ..initialize().then((_) {
          setState(() => _isInitialized = true);
          _controller.play();
          _controller.setLooping(true);
        });
      return;
    }

    _controller = VideoPlayerController.networkUrl(
      Uri.parse('https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4'),
    )..initialize().then((_) {
        setState(() => _isInitialized = true);
        _controller.play();
        _controller.setLooping(true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _showCaptionDialog({SubtitleModel? editing}) async {
    final controller = TextEditingController(text: editing?.text ?? '');
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text('자막 입력', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: '내용을 입력하세요',
            hintStyle: TextStyle(color: Colors.white54),
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('확인'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      if (editing != null) {
        setState(() => editing.text = result);
      } else {
        setState(() => _subtitles.add(SubtitleModel(text: result, dx: 0.5, dy: 0.8)));
      }
    }
  }

  void _addSticker() {
    setState(() => _stickers.add(StickerModel(emoji: '✨', dx: 0.2, dy: 0.2, scale: 1.2)));
  }

  void _applyFilter(FilterPreset preset, double opacity) {
    setState(() {
      _selectedFilter = preset;
      _filterOpacity = opacity;
    });
  }

  Future<void> _showFilterDialog() async {
    FilterPreset tempPreset = _selectedFilter;
    double tempOpacity = _filterOpacity;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Colors.black,
          title: const Text('필터 선택', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...FilterPreset.values.map((preset) {
                final label = switch (preset) {
                  FilterPreset.none => '기본',
                  FilterPreset.grayscale => '흑백',
                  FilterPreset.warm => '따뜻한 톤',
                  FilterPreset.cool => '차가운 톤',
                };

                return RadioListTile<FilterPreset>(
                  activeColor: Colors.white,
                  title: Text(label, style: const TextStyle(color: Colors.white)),
                  value: preset,
                  groupValue: tempPreset,
                  onChanged: (value) => setState(() => tempPreset = value!),
                );
              }),
              const SizedBox(height: 12),
              const Text('불투명도', style: TextStyle(color: Colors.white70)),
              Slider(
                value: tempOpacity,
                min: 0.3,
                max: 1.0,
                activeColor: Colors.white,
                inactiveColor: Colors.white24,
                onChanged: (value) => setState(() => tempOpacity = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('적용'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      _applyFilter(tempPreset, tempOpacity);
    }
  }

  ColorFilter? _colorFilterForPreset(FilterPreset preset) {
    return switch (preset) {
      FilterPreset.grayscale => const ColorFilter.matrix(<double>[
          0.2126, 0.7152, 0.0722, 0, 0, //
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]),
      FilterPreset.warm => const ColorFilter.matrix(<double>[
          1.1, 0.1, 0.0, 0, 0, //
          0.0, 0.9, 0.2, 0, 0,
          0.0, 0.1, 0.9, 0, 0,
          0, 0, 0, 1, 0,
        ]),
      FilterPreset.cool => const ColorFilter.matrix(<double>[
          0.9, 0.0, 0.2, 0, 0, //
          0.0, 0.9, 0.1, 0, 0,
          0.0, 0.1, 1.1, 0, 0,
          0, 0, 0, 1, 0,
        ]),
      _ => null,
    };
  }

  Future<void> _commitEdits() async {
    final subtitlePayload = _subtitles.map((subtitle) {
      return {
        'text': subtitle.text,
        'dx': subtitle.dx,
        'dy': subtitle.dy,
        'fontSize': subtitle.fontSize,
      };
    }).toList();

    final stickerPayload = _stickers.map((sticker) {
      return {
        'emoji': sticker.emoji,
        'dx': sticker.dx,
        'dy': sticker.dy,
        'scale': sticker.scale,
      };
    }).toList();

    try {
      await _platform.invokeMethod('applyEdits', {
        'subtitles': subtitlePayload,
        'stickers': stickerPayload,
        'filter': _selectedFilter.name,
        'filterOpacity': _filterOpacity,
      });
      Fluttertoast.showToast(msg: "편집 내용이 적용되었습니다.", backgroundColor: Colors.black87, textColor: Colors.white);
    } catch (e) {
      Fluttertoast.showToast(msg: "적용 실패: $e", backgroundColor: Colors.redAccent, textColor: Colors.white);
    }
  }

  void _updateSubtitle(SubtitleModel subtitle, DragUpdateDetails details, BoxConstraints constraints) {
    final dx = details.delta.dx / constraints.maxWidth;
    final dy = details.delta.dy / constraints.maxHeight;
    setState(() {
      subtitle.dx = (subtitle.dx + dx).clamp(0.05, 0.95);
      subtitle.dy = (subtitle.dy + dy).clamp(0.05, 0.95);
    });
  }

  void _updateSticker(StickerModel sticker, DragUpdateDetails details, BoxConstraints constraints) {
    final dx = details.delta.dx / constraints.maxWidth;
    final dy = details.delta.dy / constraints.maxHeight;
    setState(() {
      sticker.dx = (sticker.dx + dx).clamp(0.05, 0.95);
      sticker.dy = (sticker.dy + dy).clamp(0.05, 0.95);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildPreviewSection(),
            Expanded(child: _buildTimelineSection()),
            _buildBottomActionBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewSection() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _isInitialized
              ? LayoutBuilder(
                  builder: (_, constraints) {
                    return Stack(
                      children: [
                        Opacity(
                          opacity: _filterOpacity,
                          child: ColorFiltered(
                            colorFilter: _colorFilterForPreset(_selectedFilter) ??
                                const ColorFilter.matrix(<double>[
                                  1, 0, 0, 0, 0, //
                                  0, 1, 0, 0, 0,
                                  0, 0, 1, 0, 0,
                                  0, 0, 0, 1, 0,
                                ]),
                            child: VideoPlayer(_controller),
                          ),
                        ),
                        ..._subtitles.map((subtitle) {
                          final left = subtitle.dx * constraints.maxWidth;
                          final top = subtitle.dy * constraints.maxHeight;
                          return Positioned(
                            left: left - 8,
                            top: top - 8,
                            child: GestureDetector(
                              onPanUpdate: (details) => _updateSubtitle(subtitle, details, constraints),
                              onTap: () => _showCaptionDialog(editing: subtitle),
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 240),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.85),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: Text(
                                  subtitle.text,
                                  style: TextStyle(color: Colors.white, fontSize: subtitle.fontSize),
                                ),
                              ),
                            ),
                          );
                        }),
                        ..._stickers.map((sticker) {
                          final left = sticker.dx * constraints.maxWidth;
                          final top = sticker.dy * constraints.maxHeight;
                          return Positioned(
                            left: left - 20,
                            top: top - 20,
                            child: GestureDetector(
                              onPanUpdate: (details) => _updateSticker(sticker, details, constraints),
                              child: Text(
                                sticker.emoji,
                                style: TextStyle(fontSize: 26 * sticker.scale),
                              ),
                            ),
                          );
                        }),
                      ],
                    );
                  },
                )
              : const Center(child: CircularProgressIndicator(color: Colors.white54)),
        ),
      ),
    );
  }

  Widget _buildTimelineSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              "타임라인",
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: 5,
              itemBuilder: (context, index) => ListTile(
                leading: Container(
                  width: 60,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(Icons.movie, color: Colors.white54, size: 20),
                ),
                title: Text('클립 ${index + 1}', style: const TextStyle(color: Colors.white)),
                trailing: const Icon(Icons.drag_handle, color: Colors.white54),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: const BoxDecoration(
        color: Colors.black,
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMenuButton(Icons.content_cut, '컷 편집', () {}),
              _buildMenuButton(Icons.text_fields, '자막', () => _showCaptionDialog()),
              _buildMenuButton(Icons.emoji_emotions, '스티커', _addSticker),
              _buildMenuButton(Icons.filter_b_and_w, '필터', _showFilterDialog),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _commitEdits,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(44),
            ),
            child: const Text('편집 내용 병합'),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}
