import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../managers/video_manager.dart';
import '../managers/user_status_manager.dart';

class ClipExtractorScreen extends StatefulWidget {
  final File videoFile;
  final String targetAlbum;

  const ClipExtractorScreen({
    super.key,
    required this.videoFile,
    required this.targetAlbum,
  });

  @override
  State<ClipExtractorScreen> createState() => _ClipExtractorScreenState();
}

class _ClipExtractorScreenState extends State<ClipExtractorScreen> {
  static const MethodChannel _platform = MethodChannel('com.dk.three_sec/video_engine');

  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isExporting = false;

  // 선택된 구간 리스트 (시작 시간 ms)
  // 종료 시간은 자동으로 start + 3000ms
  final List<int> _selectedSegments = [];
  
  // 썸네일 캐시는 복잡하므로 일단 심플한 타임스탬프 UI로 간다.

  @override
  void initState() {
    super.initState();
    _initVideoPlayer();
  }

  Future<void> _initVideoPlayer() async {
    _controller = VideoPlayerController.file(widget.videoFile)
      ..initialize().then((_) {
        setState(() {
          _isInitialized = true;
          _isPlaying = true;
        });
        _controller.play();
        _controller.addListener(_videoListener);
      });
  }

  void _videoListener() {
    final isPlaying = _controller.value.isPlaying;
    if (isPlaying != _isPlaying) {
      if (mounted) setState(() => _isPlaying = isPlaying);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_videoListener);
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _isPlaying = false;
      } else {
        _controller.play();
        _isPlaying = true;
      }
    });
  }

  void _addCurrentSegment() {
    final currentMs = _controller.value.position.inMilliseconds;
    final totalMs = _controller.value.duration.inMilliseconds;
    
    // 비디오 끝부분 예외 처리 (3초 미만 남았을 때)
    // 네이티브 엔진에서 처리하겠지만, UI에서도 시작점은 total - 3000 안쪽이어야 안전
    int startMs = currentMs;
    if (startMs > totalMs - 3000) {
      startMs = totalMs - 3000;
      if (startMs < 0) startMs = 0; // 영상 자체가 3초 미만인 경우
    }

    setState(() {
      _selectedSegments.add(startMs);
      // UX: 추가 후 잠시 멈춤? 아니면 계속 재생? -> 계속 재생이 자연스러움
      // 추가되었다는 피드백(햅틱)
      HapticFeedback.mediumImpact();
    });
    
    // 토스트 등으로 알림
    Fluttertoast.showToast(
      msg: "3초 구간 추가됨 (${_formatDuration(Duration(milliseconds: startMs))})",
      gravity: ToastGravity.CENTER,
    );
  }

  void _removeSegment(int index) {
    setState(() {
      _selectedSegments.removeAt(index);
    });
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
  }

  Future<void> _extractClips() async {
    if (_selectedSegments.isEmpty) return;

    setState(() => _isExporting = true);
    
    final videoManager = Provider.of<VideoManager>(context, listen: false);
    final userStatusManager = UserStatusManager();
    final docDir = await videoManager.getAppDocDir(); // public method 필요하지만, 없으면 standard way 사용
    final outputDir = "${docDir.path}/clips"; // 임시 폴더
    
    // 디렉토리 생성 및 정리
    final dir = Directory(outputDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);

    // 세그먼트 데이터 준비
    final segmentsPayload = _selectedSegments.map((startMs) {
      return {
        'start': startMs,
        'end': startMs + 3000, 
      };
    }).toList();

    try {
      print('[ClipExtractor] 🎥 클립 추출 시작: ${segmentsPayload.length}개 구간');
      
      final result = await _platform.invokeMethod('extractClips', {
        'inputPath': widget.videoFile.path,
        'outputDir': outputDir,
        'segments': segmentsPayload,
        'quality': '1080p', // 추출은 원본 화질 유지하되 인코딩은 1080p로 통일 (속도 위해)
        'enableNoiseSuppression': false,
        'userTier': userStatusManager.currentTier.toString().split('.').last,
      });

      if (result != null) {
        // 결과는 생성된 파일 경로들의 리스트 (JSON String or List)
        // 네이티브 구현상 List<String> 반환 예상됨 (확인 필요) 혹은 성공 메시지일 수 있음.
        // MainActivity.kt의 extractClips를 보면 결과를 알 수 있음.
        // 현재 MainActivity 구현은 result.success("SUCCESS") 또는 경로 리스트일 것임.
        // 일반적인 3S 패턴상 파일들을 특정 폴더에 떨구고 "SUCCESS"만 줄 수도 있음.
        
        // 하지만 videoManager 로직에 태워야 하므로, 생성된 파일들을 찾아서 등록해야 함.
        // 가정: outputDir에 파일들이 생성됨. 이름을 알 수 없으니 폴더 스캔 또는 네이티브가 리턴해주길 기대.
        // 네이티브 코드가 반환값을 명시적으로 안주면 폴더를 스캔해서 최근 생성된 파일을 가져와야 함.
        
        // 여기서는 안전하게 outputDir의 파일들을 가져와서 이동시킴.
        final List<FileSystemEntity> files = dir.listSync();
        // 방금 생성된 파일들만 골라내기 위해 타임스탬프 체크 등을 할 수 있으나, 
        // 일단 outputDir를 전용으로 썼으므로 있는거 다 가져옴.
        
        int successCount = 0;
        for (var file in files) {
          if (file is File && file.path.endsWith('.mp4')) {
             // 비디오 매니저를 통해 정식 앨범으로 이동 및 등록
             await videoManager.saveExtractedClip(file.path, widget.targetAlbum);
             successCount++;
          }
        }
        
        // 임시 폴더 정리 (선택적)
        // await dir.delete(recursive: true); 
        
        Fluttertoast.showToast(msg: "$successCount개 클립 저장 완료!");
        
        if (mounted) {
          Navigator.pop(context, true); // true = 갱신 필요
        }
      }
    } catch (e) {
      print('[ClipExtractor] ✗ 추출 실패: $e');
      Fluttertoast.showToast(msg: "클립 추출 실패: $e");
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('원하는 장면 담기', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: _selectedSegments.isEmpty || _isExporting ? null : _extractClips,
            child: Text(
              _isExporting ? "저장 중..." : "완료 (${_selectedSegments.length})",
              style: TextStyle(
                color: _selectedSegments.isEmpty ? Colors.grey : Colors.blueAccent,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 1. 비디오 프리뷰 (중앙)
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(_controller),
                      // 재생 오버레이
                      if (!_isPlaying)
                        Container(
                          color: Colors.black26,
                          child: const Icon(Icons.play_circle_fill, color: Colors.white70, size: 60),
                        ),
                      GestureDetector(
                        onTap: _togglePlayPause,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          // 투명 터치 영역
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // 2. 컨트롤 컨트롤 (슬라이더 + 시간)
            // 2. 컨트롤 컨트롤 (슬라이더 + 시간)
            ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, VideoPlayerValue value, child) {
                final duration = value.duration.inMilliseconds.toDouble();
                final position = value.position.inMilliseconds.toDouble();

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        _formatDuration(value.position),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2.0,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
                            activeTrackColor: Colors.blueAccent,
                            inactiveTrackColor: Colors.grey,
                            thumbColor: Colors.white,
                          ),
                          child: Slider(
                            value: position.clamp(0.0, duration),
                            min: 0.0,
                            max: duration,
                            onChanged: (newValue) {
                              _controller.seekTo(Duration(milliseconds: newValue.toInt()));
                            },
                          ),
                        ),
                      ),
                      Text(
                        _formatDuration(value.duration),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                );
              },
            ),
            
            const SizedBox(height: 10),
            
            // 3. 메인 버튼 (Add Clip) - 예쁜 아이콘 버튼
            Center(
              child: SizedBox(
                width: 70, 
                height: 70,
                child: FloatingActionButton(
                  onPressed: _addCurrentSegment,
                  backgroundColor: Colors.white,
                  elevation: 4,
                  shape: const CircleBorder(),
                  child: const Icon(Icons.add_a_photo_outlined, color: Colors.black, size: 32),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // 4. 선택된 세그먼트 리스트 (가로 스크롤)
            SizedBox(
              height: 80,
              child: _selectedSegments.isEmpty
                  ? const Center(
                      child: Text(
                        "위 버튼을 눌러 3초 장면을 담아보세요",
                        style: TextStyle(color: Colors.white38),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: _selectedSegments.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final startTime = Duration(milliseconds: _selectedSegments[index]);
                        return Stack(
                          children: [
                            Container(
                              width: 100,
                              decoration: BoxDecoration(
                                color: Colors.grey[900],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white24),
                              ),
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.movie, color: Colors.white54),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatDuration(startTime),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: GestureDetector(
                                onTap: () => _removeSegment(index),
                                child: const Icon(Icons.cancel, color: Colors.redAccent, size: 20),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
