import 'dart:async';
import 'dart:io';
// import 'dart:ui'; (Removed)

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../utils/haptics.dart';
import '../managers/video_manager.dart';

class CaptureScreen extends StatefulWidget {
  final GlobalKey recordButtonKey;
  
  const CaptureScreen({
    super.key,
    required this.recordButtonKey,
  });

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> with TickerProviderStateMixin {
  late CameraController _controller;
  // late Future<void> _initializeControllerFuture; (Removed unused)
  
  bool _isRecording = false;
  int _remainingTime = 3;
  Timer? _recordingTimer;
  Offset? _tapPosition;
  late AnimationController _focusAnimController;
  
  double _exposureOffset = 0.0;
  double _minExposure = 0.0;
  double _maxExposure = 0.0;
  bool _showExposureSlider = false;
  Timer? _exposureTimer;
  
  int _cameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;

  Future<void> _toggleFlash() async {
    if (!_controller.value.isInitialized) return;
    
    final newMode = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    try {
      await _controller.setFlashMode(newMode);
      setState(() => _flashMode = newMode);
      hapticFeedback();
    } catch (e) {
      debugPrint("Flash Toggle Error: $e");
    }
  }
  
  late VideoManager videoManager;
  
  @override
  void initState() {
    super.initState();
    _focusAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _initCamera();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    videoManager = Provider.of<VideoManager>(context, listen: false);
  }
  
  void _initCamera() {
    if (cameras.isEmpty) return;
    _controller = CameraController(
      cameras[_cameraIndex],
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: Platform.isAndroid 
          ? ImageFormatGroup.jpeg 
          : ImageFormatGroup.bgra8888,
    );
    
    _controller.initialize().then((_) async {
      await _controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      _minExposure = await _controller.getMinExposureOffset();
      _maxExposure = await _controller.getMaxExposureOffset();
      
      if (mounted) {
        setState(() {});
      }
    }).catchError((e) {
      debugPrint("카메라 초기화 실패: $e");
    });
  }
  
  Future<void> _toggleCamera() async {
    if (cameras.length <= 1) return;
    _cameraIndex = ((_cameraIndex + 1) % cameras.length).toInt();
    await _controller.dispose();
    _initCamera();
  }
  
  Future<void> _startRecording() async {
    try {
      await _controller.setExposureMode(ExposureMode.locked);
      await _controller.startVideoRecording();
      setState(() {
        _isRecording = true;
        _remainingTime = 3;
      });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_remainingTime > 1 && mounted) {
          setState(() => _remainingTime--);
        } else if (mounted) {
          _stopRecording();
          timer.cancel();
        }
      });
    } catch (e) {
      debugPrint("녹화 시작 실패: $e");
    }
  }
  
  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    _recordingTimer?.cancel();
    try {
      final video = await _controller.stopVideoRecording();
      await _controller.setExposureMode(ExposureMode.auto);
      await videoManager.saveRecordedVideo(video);
    } catch (e) {
      debugPrint("녹화 종료 실패: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isRecording = false;
          _remainingTime = 3;
        });
      }
    }
  }
  
  Future<void> _handleFocus(TapDownDetails d, BoxConstraints c) async {
    final Offset localPosition = d.localPosition;
    final double x = localPosition.dx / c.maxWidth;
    final double y = localPosition.dy / c.maxHeight;
    await _controller.setFocusPoint(Offset(x, y));
    await _controller.setExposurePoint(Offset(x, y));
    setState(() {
      _tapPosition = localPosition;
      _showExposureSlider = true;
    });
    _focusAnimController.forward(from: 0.0);
    _startExposureTimer();
  }
  
  void _startExposureTimer() {
    _exposureTimer?.cancel();
    _exposureTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showExposureSlider = false);
    });
  }
  
  @override
  void dispose() {
    _recordingTimer?.cancel();
    _exposureTimer?.cancel();
    _focusAnimController.dispose();
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Colors.white)));
    }
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // 9:16 Aspect Ratio Calculation
          // User requested "Maintain 9:16 ratio".
          
          // Determine scaling to cover 9:16 area or full screen
          // For now, we allow full screen preview but overlays will guide the 9:16 safe area if needed.
          // User requested "Maintain 9:16 ratio".
          
          return GestureDetector(
            onTapDown: (d) => _handleFocus(d, constraints),
            child: Stack(
              children: [
                // 1. Camera Preview (Centered, 9:16)
                Center(
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: CameraPreview(_controller),
                  ),
                ),
                
                // 2. Focus & Exposure Overlays (Existing Logic)
                if (_tapPosition != null && _showExposureSlider) ...[
                   Positioned(
                    left: _tapPosition!.dx - 35,
                    top: _tapPosition!.dy - 35,
                    child: AnimatedBuilder(
                      animation: _focusAnimController,
                      builder: (context, child) => Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.yellow, width: 2),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: _tapPosition!.dx + 45,
                    top: _tapPosition!.dy - 60,
                    child: SizedBox(
                      height: 120,
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                            activeTrackColor: Colors.yellow,
                            inactiveTrackColor: Colors.white30,
                            thumbColor: Colors.yellow,
                          ),
                          child: Slider(
                            value: _exposureOffset,
                            min: _minExposure,
                            max: _maxExposure,
                            onChanged: (v) async {
                              setState(() => _exposureOffset = v);
                              await _controller.setExposureOffset(v);
                              _startExposureTimer();
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ],

                // 3. UI Overlays
                SafeArea(
                  child: Column(
                    children: [
                      // --- Top Control Bar ---
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Flash Control
                            IconButton(
                              icon: Icon(
                                _flashMode == FlashMode.torch ? Icons.flash_on : Icons.flash_off, 
                                color: _flashMode == FlashMode.torch ? Colors.amber : Colors.white
                              ), 
                              onPressed: _toggleFlash,
                            ),
                            // Album Dropdown (Moved to Top Center or near top)
                            _buildAlbumDropdown(),
                            // Settings Button
                            IconButton(
                              icon: const Icon(Icons.settings, color: Colors.white),
                              onPressed: () {
                                // TODO: Open Settings
                                hapticFeedback();
                              },
                            ),
                          ],
                        ),
                      ),
                      
                      const Spacer(),
                      
                      // --- Bottom Controls ---
                      
                      // Zoom Controls
                      if (!_isRecording)
                        Padding(
                           padding: const EdgeInsets.only(bottom: 24),
                           child: Row(
                             mainAxisAlignment: MainAxisAlignment.center,
                             children: [
                               _buildZoomButton(0.5),
                               const SizedBox(width: 16),
                               _buildZoomButton(1.0, isSelected: true), // Default for now
                               const SizedBox(width: 16),
                               _buildZoomButton(3.0),
                             ],
                           ),
                        ),
                        
                      // Timer (if recording)
                      if (_isRecording)
                         Padding(
                           padding: const EdgeInsets.only(bottom: 16),
                           child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.red.withAlpha(204),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                "00:0$_remainingTime",
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Courier'),
                              ),
                           ),
                         ),

                      // Shutter Area (Centered)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 30),
                        child: SizedBox(
                          width: double.infinity,
                          height: 100, // Sufficient height for shutter button
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                               // Shutter Content
                               GestureDetector(
                                 onTap: () {
                                   hapticFeedback();
                                   if (_isRecording) {
                                     _stopRecording();
                                   } else {
                                     _startRecording();
                                   }
                                 },
                                 child: ShutterRing(
                                   isRecording: _isRecording,
                                   key: widget.recordButtonKey,
                                 ),
                               ),

                               // Camera Switch (Positioned Right)
                               Positioned(
                                 right: 32,
                                 child: IconButton(
                                   icon: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 32),
                                   onPressed: _toggleCamera,
                                 ),
                               ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildZoomButton(double zoom, {bool isSelected = false}) {
    return GestureDetector(
      onTap: () {
        // TODO: Implement Zoom Logic
        hapticFeedback();
      },
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: isSelected ? Colors.yellow.withAlpha(204) : Colors.black45,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1),
        ),
        alignment: Alignment.center,
        child: Text(
          "${zoom}x",
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildAlbumDropdown() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black45, // Fixed deprecated withOpacity
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white30),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: videoManager.clipAlbums.contains(videoManager.currentAlbum) &&
                  videoManager.currentAlbum != "휴지통"
              ? videoManager.currentAlbum
              : "일상", // Default safely
          dropdownColor: Colors.black.withAlpha(204),
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 16),
          onChanged: (v) {
            setState(() => videoManager.currentAlbum = v!);
            hapticFeedback();
          },
          items: videoManager.clipAlbums
              .where((a) => a != "휴지통")
              .map((a) => DropdownMenuItem(
                    value: a,
                    child: Text(a),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

// --- New Shutter Ring Widget ---

class ShutterRing extends StatefulWidget {
  final bool isRecording;
  
  const ShutterRing({super.key, required this.isRecording});

  @override
  State<ShutterRing> createState() => _ShutterRingState();
}

class _ShutterRingState extends State<ShutterRing> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.6).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(ShutterRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording != oldWidget.isRecording) {
      if (widget.isRecording) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
             // Outer Ring
             Container(
               width: 80, height: 80,
               decoration: BoxDecoration(
                 shape: BoxShape.circle,
                 border: Border.all(color: Colors.white, width: 5),
               ),
             ),
             // Inner Circle/Square
             Container(
               width: 70 * _scaleAnim.value, 
               height: 70 * _scaleAnim.value,
               decoration: BoxDecoration(
                 color: widget.isRecording ? Colors.red : Colors.white,
                 borderRadius: BorderRadius.circular(widget.isRecording ? 8 : 35),
               ),
             ),
          ],
        );
      },
    );
  }
}
