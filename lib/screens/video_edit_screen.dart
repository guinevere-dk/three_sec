import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
// 💡 중요: New FFmpeg 패키지 임포트
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

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
  
  // 편집 상태
  double _currentSliderValue = 0.0;
  List<double> _cutPoints = []; // 3초 구간 시작점들 (ms 단위)
  bool _isExporting = false;
  int _exportProgress = 0;

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

  // ✂️ 3초 구간 추가 로직
  void _addSegment() {
    final currentPos = _controller.value.position.inMilliseconds.toDouble();
    final maxDuration = _controller.value.duration.inMilliseconds.toDouble();
    
    // 영상 끝부분이라 3초가 안 되면 경고
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

  // 💾 FFmpeg 변환 및 저장
  Future<void> _exportClips() async {
    if (_cutPoints.isEmpty) return;
    
    setState(() {
      _isExporting = true;
      _isPlaying = false;
    });
    _controller.pause();

    final docDir = await getApplicationDocumentsDirectory();
    final saveDir = Directory(p.join(docDir.path, 'vlogs', widget.targetAlbum));
    if (!await saveDir.exists()) await saveDir.create(recursive: true);

    int successCount = 0;

    for (int i = 0; i < _cutPoints.length; i++) {
      setState(() => _exportProgress = i + 1);
      
      final startTime = _cutPoints[i] / 1000.0; // 초 단위 변환
      final fileName = "clip_${DateTime.now().millisecondsSinceEpoch}_$i.mp4";
      final outputPath = p.join(saveDir.path, fileName);

      // 💡 FFmpeg 명령어: 3초 자르기 + 표준 코덱 + 오디오 포함
      // -ss 앞에 배치하여 빠른 탐색 (Input seeking)
      final command = "-ss $startTime -t 3 -i \"${widget.videoFile.path}\" -c:v libx264 -c:a aac \"$outputPath\"";

      await FFmpegKit.execute(command).then((session) async {
        final returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode)) {
          successCount++;
        } else {
           print("FFmpeg Error: ${await session.getAllLogsAsString()}");
        }
      });
    }

    if (mounted) {
      setState(() => _isExporting = false);
      Navigator.pop(context, true); // 완료 신호 반환
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // 몰입감을 위한 블랙 테마
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
      body: _isExporting 
          ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(color: Colors.blueAccent),
                const SizedBox(height: 20),
                Text("${_cutPoints.length}개 중 $_exportProgress번째 영상 생성 중...", style: const TextStyle(color: Colors.white)),
              ],
            ))
          : Column(
        children: [
          // 1. 비디오 프리뷰 (화면 상단)
          Expanded(
            flex: 3,
            child: _isInitialized 
              ? Center(child: AspectRatio(aspectRatio: _controller.value.aspectRatio, child: VideoPlayer(_controller)))
              : const Center(child: CircularProgressIndicator(color: Colors.white24)),
          ),
          
          // 2. 편집 컨트롤 패널 (화면 하단)
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E), // 다크 그레이 배경
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // 타임라인 정보
                  if (_isInitialized) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(_controller.value.position), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        Text(_formatDuration(_controller.value.duration), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                    // 슬라이더
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
                          setState(() {
                            _currentSliderValue = value;
                          });
                          _controller.seekTo(Duration(milliseconds: value.toInt()));
                        },
                      ),
                    ),
                  ],
                  
                  const Spacer(),
                  
                  // 메인 컨트롤 버튼
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // 재생/정지
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
                      // ✂️ 3초 담기 버튼
                      GestureDetector(
                        onTap: _addSegment,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent,
                            borderRadius: BorderRadius.circular(30),
                          ),
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
                  
                  // 내가 담은 구간 리스트 (가로 스크롤)
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