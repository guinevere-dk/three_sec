import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
// ❌ FFmpeg 패키지 임포트 제거 완료
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:fluttertoast/fluttertoast.dart';

class VideoEditScreen extends StatefulWidget {
  final File videoFile;
  final String targetAlbum;

  const VideoEditScreen({super.key, required this.videoFile, required this.targetAlbum});

  @override
  State<VideoEditScreen> createState() => _VideoEditScreenState();
}

class _VideoEditScreenState extends State<VideoEditScreen> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  
  double _currentSliderValue = 0.0;
  List<double> _cutPoints = []; 
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.videoFile)
      ..initialize().then((_) {
        setState(() {
          _isInitialized = true;
        });
        _controller.play();
        _isPlaying = true;
      });
    
    _controller.addListener(() {
      if (!mounted) return;
      setState(() {
        _currentSliderValue = _controller.value.position.inMilliseconds.toDouble();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
  }

  void _addSegment() {
    final currentPos = _controller.value.position.inMilliseconds.toDouble();
    final maxDuration = _controller.value.duration.inMilliseconds.toDouble();
    
    if (currentPos + 3000 > maxDuration) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("남은 구간이 3초보다 짧습니다.")));
      return;
    }

    setState(() {
      _cutPoints.add(currentPos);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("구간 ${ _cutPoints.length } 추가됨"),
      duration: const Duration(milliseconds: 500),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // 💡 FFmpeg 의존성 제거됨
  Future<void> _exportClips() async {
    if (_cutPoints.isEmpty) return;
    
    // 현재는 빌드 정상화를 위해 기능 비활성화 (추후 Native Trimming 구현 예정)
    Fluttertoast.showToast(msg: "네이티브 편집 엔진 도입 준비 중입니다.");
    
    // 네이티브 편집 기능 구현 전까지는 저장을 막거나 원본을 저장하는 로직으로 대체 가능
    // Navigator.pop(context, true); 
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, 
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text("3초 구간 추출", style: TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          TextButton(
            onPressed: _cutPoints.isEmpty || _isExporting ? null : _exportClips,
            child: Text(
              _isExporting ? "저장 중..." : "완료 (${_cutPoints.length})", 
              style: TextStyle(color: _cutPoints.isEmpty ? Colors.grey : Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 16)
            ),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: _isInitialized 
              ? Center(child: AspectRatio(aspectRatio: _controller.value.aspectRatio, child: VideoPlayer(_controller)))
              : const Center(child: CircularProgressIndicator(color: Colors.white24)),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E), 
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  if (_isInitialized) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(_controller.value.position), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        Text(_formatDuration(_controller.value.duration), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.blueAccent,
                        inactiveTrackColor: Colors.white12,
                        thumbColor: Colors.white,
                        trackHeight: 4.0,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
                      ),
                      child: Slider(
                        value: _currentSliderValue,
                        min: 0.0,
                        max: _controller.value.duration.inMilliseconds.toDouble(),
                        onChanged: (value) {
                          setState(() { _currentSliderValue = value; });
                          _controller.seekTo(Duration(milliseconds: value.toInt()));
                        },
                      ),
                    ),
                  ],
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        iconSize: 56,
                        icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.white),
                        onPressed: () {
                          setState(() {
                            _isPlaying ? _controller.pause() : _controller.play();
                            _isPlaying = !_isPlaying;
                          });
                        },
                      ),
                      GestureDetector(
                        onTap: _addSegment,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          decoration: BoxDecoration(color: Colors.blueAccent, borderRadius: BorderRadius.circular(30)),
                          child: const Row(
                            children: [
                              Icon(Icons.movie_creation_outlined, color: Colors.white),
                              SizedBox(width: 8),
                              Text("3초 담기", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_cutPoints.isNotEmpty)
                    SizedBox(
                      height: 36,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _cutPoints.length,
                        itemBuilder: (context, index) => Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                          child: Text(
                            "구간 ${index + 1} (${_formatDuration(Duration(milliseconds: _cutPoints[index].toInt()))})", 
                            style: const TextStyle(color: Colors.white70, fontSize: 12)
                          ),
                        ),
                      ),
                    )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}