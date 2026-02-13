import 'dart:io';
import 'dart:async';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../managers/video_manager.dart';
import '../models/edit_command.dart';
import '../managers/user_status_manager.dart';
import '../models/vlog_project.dart';

// ?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺
// ?뱷 ?곗씠??紐⑤뜽
// ?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺

class SubtitleModel {
  String text;
  double dx;
  double dy;
  double fontSize;
  Color textColor;
  Color? backgroundColor;
  int? startTimeMs;  // ?쒖떆 ?쒖옉 ?쒓컙 (ms)
  int? endTimeMs;    // ?쒖떆 醫낅즺 ?쒓컙 (ms)

  SubtitleModel({
    required this.text,
    required this.dx,
    required this.dy,
    this.fontSize = 18.0,
    this.textColor = Colors.white,
    this.backgroundColor,
    this.startTimeMs,
    this.endTimeMs,
  });

  // Copy helper for Undo/Redo
  SubtitleModel copy() {
    return SubtitleModel(
      text: text,
      dx: dx,
      dy: dy,
      fontSize: fontSize,
      textColor: textColor,
      backgroundColor: backgroundColor,
      startTimeMs: startTimeMs,
      endTimeMs: endTimeMs,
    );
  }
}

class StickerModel {
  String imagePath;
  double dx;
  double dy;
  double scale;
  int? startTimeMs;
  int? endTimeMs;

  StickerModel({
    required this.imagePath,
    required this.dx,
    required this.dy,
    this.scale = 1.0,
    this.startTimeMs,
    this.endTimeMs,
  });

  // Copy helper for Undo/Redo
  StickerModel copy() {
    return StickerModel(
      imagePath: imagePath,
      dx: dx,
      dy: dy,
      scale: scale,
      startTimeMs: startTimeMs,
      endTimeMs: endTimeMs,
    );
  }
}

enum FilterPreset { none, grayscale, warm, cool }

// ?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺
// ??Editor State Snapshot Command
// ?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺

class EditorState {
  final List<SubtitleModel> subtitles;
  final List<StickerModel> stickers;
  final FilterPreset filter;
  final double filterOpacity;
  // Audio State
  final String? bgmPath;
  final double videoVolume;
  final double bgmVolume;

  EditorState({
    required this.subtitles,
    required this.stickers,
    required this.filter,
    required this.filterOpacity,
    this.bgmPath,
    this.videoVolume = 1.0,
    this.bgmVolume = 0.5,
  });

  EditorState copy() {
    return EditorState(
      subtitles: subtitles.map((e) => e.copy()).toList(),
      stickers: stickers.map((e) => e.copy()).toList(),
      filter: filter,
      filterOpacity: filterOpacity,
      bgmPath: bgmPath,
      videoVolume: videoVolume,
      bgmVolume: bgmVolume,
    );
  }
}

class StateChangeCommand implements EditCommand {
  final EditorState oldState;
  final EditorState newState;
  final VoidCallback onStateRestored;

  StateChangeCommand(this.oldState, this.newState, this.onStateRestored);

  @override
  void execute() {
    // Redo logic is handled by the manager restoring newState, 
    // but in this pattern, 'execute' is called initially.
    // Since we apply changes immediately in UI, this might be a no-op 
    // or we can force restore newState.
    onStateRestored();
  }

  @override
  void undo() {
    // Restore old state
    // We need a way to pass this back to the widget. 
    // The callback approach helps.
    // Actually, simple way: we will store the 'apply' function.
    // But here 'undo' needs to update the State object in the Widget.
    // Code below handles this via callback.
  }
}

// ?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺
// ?뼢截?Video Edit Screen
// ?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺

class VideoEditScreen extends StatefulWidget {
  final VlogProject project;

  const VideoEditScreen({
    super.key,
    required this.project,
  });

  @override
  State<VideoEditScreen> createState() => _VideoEditScreenState();
}

class _VideoEditScreenState extends State<VideoEditScreen> {
  static const MethodChannel _platform = MethodChannel('com.dk.three_sec/video_engine');

  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isMissingFile = false;
  
  // Editor State
  List<SubtitleModel> _subtitles = [];
  List<StickerModel> _stickers = [];
  FilterPreset _selectedFilter = FilterPreset.none;
  double _filterOpacity = 0.7;
  
  // Gesture Temp State
  double _tempBaseScale = 1.0;
  double _tempBaseFontSize = 18.0;
  
  // Audio State
  VideoPlayerController? _bgmController;
  String? _bgmPath;
  double _videoVolume = 1.0;
  double _bgmVolume = 0.5;
  
  // Command Pattern Manager
  final CommandManager _commandManager = CommandManager();
  
  // Clips Management
  List<ClipModel> _clips = [];
  int _currentClipIndex = 0;
  
  // State for Snapshot
  EditorState get _currentState => EditorState(
    subtitles: _subtitles,
    stickers: _stickers,
    filter: _selectedFilter,
    filterOpacity: _filterOpacity,
    bgmPath: _bgmPath,
    videoVolume: _videoVolume,
    bgmVolume: _bgmVolume,
  );

  // ?ㅽ떚而??먯뀑 寃쎈줈
  final List<String> _stickerAssets = [
    'assets/stickers/heart.png',
    'assets/stickers/star.png',
    'assets/stickers/smile.png',
    'assets/stickers/fire.png',
    'assets/stickers/thumbs_up.png',
    'assets/stickers/sparkles.png',
  ];

  List<Duration> _clipDurations = [];
  Duration _totalDuration = Duration.zero;
  VideoPlayerController? _nextController; // Preloader

  @override
  void initState() {
    super.initState();
    _initClips();
    _preloadDurations();
    // Initialize Undo/Redo Manager with initial state
    // ...
  }

  Future<void> _preloadDurations() async {
    _clipDurations.clear();
    _totalDuration = Duration.zero;

    // Ensure _clips aligns with paths
    if (_clips.isEmpty && widget.project.videoPaths.isNotEmpty) {
       _clips = widget.project.videoPaths.map((path) => ClipModel(
          path: path,
          id: path,
          endTime: Duration.zero,
          totalDuration: Duration.zero,
       )).toList();
    }

    for (int i = 0; i < widget.project.videoPaths.length; i++) {
      final path = widget.project.videoPaths[i];
      final file = File(path);
      if (await file.exists()) {
        final controller = VideoPlayerController.file(file);
        await controller.initialize();
        final duration = controller.value.duration;
        _clipDurations.add(duration);
        _totalDuration += duration;
        
        // Sync ClipModel metadata immediately
        if (i < _clips.length) {
          _clips[i].totalDuration = duration;
          _clips[i].endTime = duration;
        }
        
        await controller.dispose();
      } else {
        _clipDurations.add(Duration.zero);
      }
    }
    if (mounted) setState(() {}); // Update UI with total duration
  }
  
  Future<void> _preloadNextClip() async {
    final nextIndex = _currentClipIndex + 1;
    if (nextIndex >= _clips.length) return;

    final nextClip = _clips[nextIndex];
    final file = File(nextClip.path);
    if (!await file.exists()) return;

    // Dispose old next controller if it exists and points to a different file
    if (_nextController != null && _nextController!.dataSource != 'file://${file.path}') {
      await _nextController!.dispose();
      _nextController = null;
    }

    if (_nextController == null) {
      _nextController = VideoPlayerController.file(file);
      await _nextController!.initialize();
      // Ready for switch
    }
  }
  
  void _attachListeners(VideoPlayerController controller, ClipModel clip) {
    controller.addListener(_videoListener);
    
    // Continuous Playback & Trim Listener
    controller.addListener(() {
      if (!_isInitialized || _controller != controller) return; // Safety check
      final pos = controller.value.position;
      
      // Trim: Start Constraint
      if (pos < clip.startTime) {
         controller.seekTo(clip.startTime);
         return;
      }
      
      // End of Clip Logic
      if (pos >= clip.endTime) {
         if (_currentClipIndex < _clips.length - 1) {
            final nextIndex = _currentClipIndex + 1;
            
            // Seamless Switch using Preloader
            if (_nextController != null && _nextController!.value.isInitialized) {
               // 1. Swap Controllers
               final oldController = _controller;
               _controller = _nextController;
               _nextController = null;
               
               // 2. Update Index
               _currentClipIndex = nextIndex;
               final nextClip = _clips[nextIndex];
               
               // 3. Attach Listeners to New Controller
               _attachListeners(_controller!, nextClip);
               
               // 4. Play Immediately
               _controller!.play();
               // Ensure we start at startTime (if not 0)
               if (nextClip.startTime > Duration.zero) {
                  _controller!.seekTo(nextClip.startTime);
               }

               // 5. Dispose Old & Trigger Next Preload
               oldController?.removeListener(_videoListener);
               oldController?.dispose();
               
               setState(() {});
               _preloadNextClip();
            } else {
               // Fallback to standard load
               _controller!.pause();
               _loadClip(nextIndex);
            }
         } else {
            // End of Timeline
            controller.pause();
            setState(() => _isPlaying = false);
         }
      }
    });
  }

  Future<void> _initClips() async {
    final videoManager = Provider.of<VideoManager>(context, listen: false);
    
    _clips = widget.project.videoPaths.map((path) => ClipModel(
        path: path,
        id: path, // Use path as ID for simplicity
        endTime: Duration.zero,
        totalDuration: Duration.zero,
      )).toList();
    
    if (_clips.isNotEmpty) {
      await _loadClip(_currentClipIndex);
    }
  }

  Future<void> _loadClip(int index, {Duration? seekTo}) async {
    if (index < 0 || index >= _clips.length) return;
    
    bool reused = false;
    final clip = _clips[index];

    // Check Preloader Reuse
    if (_nextController != null && 
        _nextController!.value.isInitialized &&
        _nextController!.dataSource == 'file://${clip.path}') {
        
        _controller?.dispose();
        _controller = _nextController;
        _nextController = null;
        reused = true;
    } else {
        _controller?.dispose();
        _controller = null;
        _isInitialized = false;
        setState(() {}); // Show loader

        final file = File(clip.path);
        // Safety Net
        if (!await file.exists()) {
          setState(() { _isMissingFile = true; _isInitialized = false; });
          return;
        }

        _controller = VideoPlayerController.file(file);
        await _controller!.initialize();
    }
    
    // Update metadata if needed
    if (clip.totalDuration == Duration.zero) {
      clip.totalDuration = _controller!.value.duration;
      clip.endTime = clip.totalDuration;
    }

    // Attach Listeners (Refactored)
    _attachListeners(_controller!, clip);

    setState(() {
      _currentClipIndex = index;
      _isInitialized = true;
      _isPlaying = true; 
    });
    
    if (!reused) {
        if (seekTo != null) {
          await _controller!.seekTo(seekTo);
        } else {
          await _controller!.seekTo(clip.startTime);
        }
    }
    
    await _controller!.play();
    _preloadNextClip(); // Start preloading next
  }

  double _calculateGlobalPosition() {
    if (_controller == null || !_isInitialized || _clipDurations.isEmpty) return 0.0;
    double globalPos = 0.0;
    for (int i = 0; i < _currentClipIndex; i++) {
       if (i < _clipDurations.length) globalPos += _clipDurations[i].inMilliseconds;
    }
    globalPos += _controller!.value.position.inMilliseconds;
    return globalPos;
  }

  void _seekToGlobalPosition(double value) {
     double accumulated = 0.0;
     for (int i = 0; i < _clipDurations.length; i++) {
        final duration = _clipDurations[i].inMilliseconds;
        if (value <= accumulated + duration + 100) { // Slight buffer
           // Target is in this clip
           final seekPos = Duration(milliseconds: (value - accumulated).toInt());
           if (i != _currentClipIndex) {
              _loadClip(i, seekTo: seekPos);
           } else {
              _controller!.seekTo(seekPos);
           }
           return;
        }
        accumulated += duration;
     }
  }

  void _videoListener() {
    if (_controller == null || !_isInitialized) return;
    final isPlaying = _controller!.value.isPlaying;
    if (isPlaying != _isPlaying) {
      setState(() => _isPlaying = isPlaying);
      // Sync BGM Playback state
      if (isPlaying) {
        _bgmController?.play();
      } else {
        _bgmController?.pause();
      }
    }
    

  }

  Future<void> _initBgmController(String path) async {
    final file = File(path);
    if (!await file.exists()) return;

    final prevController = _bgmController;
    _bgmController = VideoPlayerController.file(file);
    await _bgmController!.initialize();
    await _bgmController!.setVolume(_bgmVolume);
    await _bgmController!.setLooping(true); // Always loop BGM as requested

    if (_isPlaying) {
      _bgmController!.play();
    }
    
    // Sync position with video? 
    // _bgmController!.seekTo(_controller!.value.position);

    prevController?.dispose();
    setState(() {});
  }
  
  void _updateVolumes() {
    _controller?.setVolume(_videoVolume);
    _bgmController?.setVolume(_bgmVolume);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _bgmController?.dispose();
    super.dispose();
  }
  
  // ?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺
  // ??Undo/Redo Logic
  // ?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺


  
  void _executeStateChange(EditorState newState) {
    final oldState = _currentState; // Capture current state
    
    final command = _GenericStateCommand(
      oldState: oldState,
      newState: newState,
      onRestore: (state) {
        setState(() {
           _subtitles = state.subtitles;
           _stickers = state.stickers;
           _selectedFilter = state.filter;
           _filterOpacity = state.filterOpacity;
           
           _bgmPath = state.bgmPath;
           _videoVolume = state.videoVolume;
           _bgmVolume = state.bgmVolume;
           
           // Restore controllers
           if (_bgmPath != null && (_bgmController == null || _bgmController!.dataSource != 'file://${_bgmPath!}')) {
              _initBgmController(_bgmPath!);
           } else if (_bgmPath == null) {
              _bgmController?.dispose();
              _bgmController = null;
           }
           _updateVolumes();
        });
      }
    );
    
    _commandManager.execute(command);
    
    // Apply new state immediately
    setState(() {
       _subtitles = newState.subtitles;
       _stickers = newState.stickers;
       _selectedFilter = newState.filter;
       _filterOpacity = newState.filterOpacity;
       
       // Apply Audio State
       if (_bgmPath != newState.bgmPath) {
         _bgmPath = newState.bgmPath;
         if (_bgmPath != null) {
           _initBgmController(_bgmPath!);
         } else {
           _bgmController?.dispose();
           _bgmController = null;
         }
       }
       
       if (_videoVolume != newState.videoVolume || _bgmVolume != newState.bgmVolume) {
          _videoVolume = newState.videoVolume;
          _bgmVolume = newState.bgmVolume;
          _updateVolumes();
       }
    });
  }

  void _undo() {
    setState(() {
      _commandManager.undo();
      if (_isInitialized && _controller != null) {
         // Refresh video controller if needed (e.g. trim undo)
         // TrimCommand undo updates the model, the player listener needs to know?
         // We might need to reload current clip logic if duration changed
         final clip = _clips[_currentClipIndex];
         _controller!.seekTo(clip.startTime);
      }
    });
    Fluttertoast.showToast(msg: "Undo");
  }

  void _redo() {
    setState(() {
      _commandManager.redo();
       if (_isInitialized && _controller != null) {
         final clip = _clips[_currentClipIndex];
         _controller!.seekTo(clip.startTime);
      }
    });
    Fluttertoast.showToast(msg: "Redo");
  }

  // ?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺
  // ?귨툘 Trimmer UI
  // ?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺


  
  // Correct Trimmer Implementation
  void _openTrimmerModal() {
    if (_clips.isEmpty || !_isInitialized) return;
    final clip = _clips[_currentClipIndex];
    final oldStart = clip.startTime;
    final oldEnd = clip.endTime;
    
    double tempStart = oldStart.inMilliseconds.toDouble();
    double tempEnd = oldEnd.inMilliseconds.toDouble();
    final maxDuration = clip.totalDuration.inMilliseconds.toDouble();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return Container(
              height: 250,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text("Trim Clip", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(Duration(milliseconds: tempStart.toInt())), style: const TextStyle(color: Colors.white)),
                      Text(_formatDuration(Duration(milliseconds: tempEnd.toInt())), style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                  RangeSlider(
                    values: RangeValues(tempStart, tempEnd),
                    min: 0,
                    max: maxDuration,
                    activeColor: Colors.amber,
                    inactiveColor: Colors.white24,
                    onChanged: (values) {
                      if (values.end - values.start < 1000) return; // Min 1 sec
                      setStateModal(() {
                        tempStart = values.start;
                        tempEnd = values.end;
                      });
                      // Preview seek
                      _controller!.seekTo(Duration(milliseconds: tempStart.toInt()));
                    },
                  ),
                  const Spacer(),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                    onPressed: () {
                      Navigator.pop(ctx, RangeValues(tempStart, tempEnd));
                    },
                    child: const Text("Apply Trim"),
                  )
                ],
              ),
            );
          }
        );
      }
    ).then((result) {
      if (result is RangeValues) {
        final newStart = Duration(milliseconds: result.start.toInt());
        final newEnd = Duration(milliseconds: result.end.toInt());
        
        if (newStart != oldStart || newEnd != oldEnd) {
           final cmd = TrimCommand(clip, newStart, newEnd);
           _commandManager.execute(cmd);
           setState(() {}); // Update UI
           _controller!.seekTo(newStart);
        }
      } else {
        // Cancelled, ensure preview is reset ?
        // Clip wasn't modified yet, so just seek back
        _controller!.seekTo(oldStart);
      }
    });
  }

  String _formatDuration(Duration d) {
    return "${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
  }

  // ?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺
  // ?렓 UI Build
  // ?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Stack(
          children: [
            // Middle Preview
            _buildPreviewSection(),

            // Top Header Overlay
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildHeader(),
            ),

            // Bottom Controls Overlay
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomControls(),
            ),
            
            // Progress Overlay
            _buildVideoProgressOverlay(),
            
            // Overlays (Stickers/Subtitles) - Positioning logic needs care.
            // Assuming they are full screen absolute positioned for now or relative to stack
            // If they are interactive drag, they need stack context.
            ..._stickers.map((s) => _buildStickerWidget(s)),
            ..._subtitles.map((s) => _buildSubtitleWidget(s)),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      height: 160,
      color: const Color(0xFFF8F9FA),
      child: Column(
        children: [
          _buildTimelineSection(),
          Expanded(child: _buildGlassToolbar()), // Use remaining space
        ],
      ),
    );
  }

  Widget _buildPreviewSection() {
    if (_isMissingFile) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.error_outline, color: Colors.red, size: 60),
            SizedBox(height: 16),
            Text("File Missing", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    
    return Positioned(
      top: 60,
      left: 0,
      right: 0,
      bottom: 160, 
      child: GestureDetector(
        onTap: _togglePlayPause,
        child: Container(
          color: const Color(0xFFF8F9FA),
          child: Center(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Filter Layer
                  ColorFiltered(
                    colorFilter: _getFilterMatrix(),
                    child: VideoPlayer(_controller!),
                  ),
                  
                  if (!_isPlaying)
                    Container(
                      color: Colors.black26,
                      child: const Center(
                        child: Icon(Icons.play_arrow, color: Colors.white, size: 64),
                      ),
                    ),
                  

                ],
              ),
            ),
          ),
        ),
      ),
    );
  }




  Widget _buildVideoProgressOverlay() {
    if (_controller == null || !_isInitialized) return const SizedBox.shrink();

    return ValueListenableBuilder(
      valueListenable: _controller!,
      builder: (context, VideoPlayerValue value, child) {
        final globalPos = _calculateGlobalPosition();
        final totalMs = _totalDuration.inMilliseconds.toDouble();
        final globalDuration = _totalDuration; // Fix missing variable
        
        return Positioned(
          bottom: 180, 
          left: 60, // Reduced width
          right: 60, // Reduced width
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Time Labels
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   Text(
                      _formatDuration(Duration(milliseconds: globalPos.toInt())),
                      style: const TextStyle(
                        color: Colors.white, 
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(blurRadius: 2, color: Colors.black)]
                      ),
                   ),
                   Text(
                      _formatDuration(globalDuration),
                      style: const TextStyle(
                        color: Colors.white, 
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(blurRadius: 2, color: Colors.black)]
                      ),
                   ),
                ],
              ),
              const SizedBox(height: 4),
              // Slider
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  value: globalPos.clamp(0.0, globalDuration.inMilliseconds.toDouble()),
                  min: 0.0,
                  max: globalDuration.inMilliseconds > 0 ? globalDuration.inMilliseconds.toDouble() : 1.0,
                  onChanged: (val) {
                    _seekToGlobalPosition(val);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  ColorFilter _getFilterMatrix() {
    switch (_selectedFilter) {
      case FilterPreset.grayscale:
        return const ColorFilter.matrix(<double>[
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      case FilterPreset.warm:
        return ColorFilter.mode(Colors.orangeAccent.withAlpha(50), BlendMode.overlay);
      case FilterPreset.cool:
        return ColorFilter.mode(Colors.blueAccent.withAlpha(50), BlendMode.overlay);
      default:
        return const ColorFilter.mode(Colors.transparent, BlendMode.dst);
    }
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.black54, Colors.transparent],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.undo, color: _commandManager.canUndo ? Colors.white : Colors.grey),
                onPressed: _commandManager.canUndo ? _undo : null,
              ),
              IconButton(
                icon: Icon(Icons.redo, color: _commandManager.canRedo ? Colors.white : Colors.grey),
                onPressed: _commandManager.canRedo ? _redo : null,
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                onPressed: _handleExport,
                child: const Text("Export", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGlassToolbar() {
    return Container(
      height: 60,
      decoration: const BoxDecoration(
        color: Colors.transparent, 
        border: Border(bottom: BorderSide(color: Colors.black12)), // Light Border
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _buildToolbarItem(Icons.cut, "Trim", _openTrimmerModal), // Trimmer Connected!
          _buildToolbarItem(Icons.text_fields, "Text", () => _showAdvancedCaptionDialog()),
          _buildToolbarItem(Icons.emoji_emotions_outlined, "Sticker", _showStickerLibrary),
          _buildToolbarItem(Icons.filter_vintage, "Filter", _showFilterDialog),
          _buildToolbarItem(Icons.speed, "Speed", _showSpeedMenu),
          _buildToolbarItem(Icons.volume_up, "Sound", _showSoundMenu),
        ],
      ),
    );
  }

  Widget _buildToolbarItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.black87, size: 24), // Dark Icon
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.black87, fontSize: 10)), // Dark Text
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineSection() {
    return SizedBox(
      height: 90,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: _clips.length,
        onReorder: (oldIndex, newIndex) {
          setState(() {
            if (oldIndex < newIndex) newIndex -= 1;
            final item = _clips.removeAt(oldIndex);
            _clips.insert(newIndex, item);
          });
        },
        itemBuilder: (context, index) {
          final clip = _clips[index];
          final isSelected = index == _currentClipIndex;
          return GestureDetector(
            key: ValueKey(clip.id),
            onTap: () async {
              if (_currentClipIndex != index) {
                await _loadClip(index);
                _controller!.play();
              }
            },
            child: Container(
              width: 70, // Updated size
              height: 70, // Explicit height constraint (though constrained by parent ListView, but container handles contents)
              margin: const EdgeInsets.only(right: 8, top: 10, bottom: 10), // Adding margin for better spacing
              decoration: BoxDecoration(
                border: isSelected ? Border.all(color: Colors.blue, width: 3) : null,
                borderRadius: BorderRadius.circular(12),
                color: Colors.grey[300], // Light placeholder color
                boxShadow: [
                   if (isSelected) BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 8, spreadRadius: 2)
                ]
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(9), // Inner radius checks out (12 - 3 border)
                    child: FutureBuilder<Uint8List?>(
                      future: Provider.of<VideoManager>(context, listen: false).getThumbnail(clip.path),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data != null) {
                          return Image.memory(snapshot.data!, fit: BoxFit.cover);
                        }
                        return const Center(child: Icon(Icons.movie, color: Colors.black26));
                      },
                    ),
                  ),
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        "${(clip.endTime.inSeconds - clip.startTime.inSeconds)}s",
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺
  // ?렜 ?대? 濡쒖쭅 (Export & Utils)
  // ?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;
    setState(() {
      if (_isPlaying) {
        _controller!.pause();
        _bgmController?.pause();
      } else {
        _controller!.play();
        _bgmController?.play();
      }
    });
  }

  // 'Done' 버튼 클릭 시 호출
  // 'Done' / 'Export' 버튼 클릭 시 호출
  void _handleExport() {
    // Safety Net: Check all files before export dialog
    for (final path in widget.project.videoPaths) {
      if (!File(path).existsSync()) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text("Error", style: TextStyle(color: Colors.redAccent)),
            content: const Text("원본 파일이 손상되어 내보낼 수 없습니다.\n(Source file missing)", style: TextStyle(color: Colors.white)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context), 
                child: const Text("OK"),
              )
            ],
          )
        );
        return;
      }
    }
    _showExportDialog();
  }

  void _showExportDialog() {
    final userStatus = Provider.of<UserStatusManager>(context, listen: false);
    String selectedQuality = widget.project.quality; // Use project quality

    // 등급에 따른 초기값 조정 (옵션)
    if (!userStatus.isStandardOrAbove() && selectedQuality != '720p') {
      selectedQuality = '720p';
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: const Text("Export Quality", style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                   _buildQualityOption("720p (Basic)", "720p", selectedQuality, true, (val) {
                     setStateDialog(() => selectedQuality = val);
                     _updateProjectQuality(val);
                   }),
                   _buildQualityOption("1080p (Standard)", "1080p", selectedQuality, userStatus.isStandardOrAbove(), (val) {
                     setStateDialog(() => selectedQuality = val);
                     _updateProjectQuality(val);
                   }),
                   _buildQualityOption("4K (Premium)", "4k", selectedQuality, userStatus.isPremium(), (val) {
                     setStateDialog(() => selectedQuality = val);
                     _updateProjectQuality(val);
                   }),
                ],
              ),
              actions: [
                 TextButton(
                   onPressed: () => Navigator.pop(context), 
                   child: const Text("Cancel", style: TextStyle(color: Colors.white54))
                 ),
                 ElevatedButton(
                   style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                   onPressed: () {
                     Navigator.pop(context);
                     _performNativeExport(selectedQuality);
                   },
                   child: const Text("Export"),
                 )
              ],
            );
          }
        );
      }
    );
  }

  void _updateProjectQuality(String newQuality) {
    if (widget.project.quality != newQuality) {
      widget.project.quality = newQuality;
      Provider.of<VideoManager>(context, listen: false).saveProject(widget.project);
    }
  }

  Widget _buildQualityOption(String label, String value, String groupValue, bool enabled, Function(String) onChanged) {
    return ListTile(
      title: Text(label, style: TextStyle(color: enabled ? Colors.white : Colors.white24)),
      leading: Radio<String>(
        value: value,
        groupValue: groupValue,
        activeColor: Colors.blueAccent,
        fillColor: MaterialStateProperty.resolveWith((states) => enabled ? (states.contains(MaterialState.selected) ? Colors.blueAccent : Colors.white) : Colors.white24),
        onChanged: enabled ? (v) => onChanged(v!) : null,
      ),
      trailing: enabled ? null : const Icon(Icons.lock, size: 16, color: Colors.white24),
      onTap: enabled ? () => onChanged(value) : null,
    );
  }

  Future<void> _performNativeExport(String quality) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        backgroundColor: Colors.black87,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
             CircularProgressIndicator(color: Colors.blueAccent),
             SizedBox(height: 20),
             Text("Rendering Vlog... 🎬", style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );

    try {
      final videoManager = Provider.of<VideoManager>(context, listen: false);
      
      // Sync State to Project before Export
      widget.project.videoPaths = _clips.map((c) => c.path).toList();
      widget.project.bgmPath = _currentState.bgmPath;
      widget.project.bgmVolume = _currentState.bgmVolume;
      widget.project.quality = quality;
      // AudioConfig sync (Clip Volumes) - Not fully implemented in EditorState yet, assuming default or need to map
      // widget.project.audioConfig = ...; 

      await videoManager.saveProject(widget.project);

      final resultPath = await videoManager.exportVlog(
        videoPaths: widget.project.videoPaths,
        audioConfig: widget.project.audioConfig,
        bgmPath: widget.project.bgmPath,
        bgmVolume: widget.project.bgmVolume,
        quality: widget.project.quality,
      );

      if (!mounted) return;
      Navigator.pop(context); // Close Loader

      if (resultPath != null) {
        Fluttertoast.showToast(msg: "Vlog Saved Successfully! 🎉");
        Navigator.pop(context, true); // Return success
      } else {
        Fluttertoast.showToast(msg: "Export Failed. Please try again.");
      }

    } catch (e) {
      if (mounted) Navigator.pop(context);
      Fluttertoast.showToast(msg: "Error: $e");
    }
  }

  void _showSoundMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(20),
              height: 350,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Audio Mixing", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  
                  // Add Music Button
                  Row(
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.music_note),
                        label: Text(_bgmPath == null ? "Add Music" : "Change Music"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white10,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () async {
                          final result = await FilePicker.platform.pickFiles(type: FileType.audio);
                          if (result != null && result.files.single.path != null) {
                             final path = result.files.single.path!;
                             
                             // Update State via Command

                             // But copy doesn't allow changing fields easily as they are final and copy() takes args.
                             // Actually copy() args are optional? Check EditorState.
                             // No, copy() implementation above maps fields.
                             
                             // We need to construct new state manually or update copy() to support overrides better.
                             // Let's use manual construction provided _currentState access.
                             final newState = EditorState(
                               subtitles: _currentState.subtitles,
                               stickers: _currentState.stickers,
                               filter: _currentState.filter,
                               filterOpacity: _currentState.filterOpacity,
                               bgmPath: path,
                               videoVolume: _currentState.videoVolume,
                               bgmVolume: _currentState.bgmVolume,
                             );
                             
                             _executeStateChange(newState);
                             setModalState(() {}); // Refresh modal UI
                          }
                        },
                      ),
                      if (_bgmPath != null)
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                          onPressed: () {
                             final newState = EditorState(
                               subtitles: _currentState.subtitles,
                               stickers: _currentState.stickers,
                               filter: _currentState.filter,
                               filterOpacity: _currentState.filterOpacity,
                               bgmPath: null,
                               videoVolume: _currentState.videoVolume,
                               bgmVolume: _currentState.bgmVolume,
                             );
                             _executeStateChange(newState);
                             setModalState(() {});
                          },
                        )
                    ],
                  ),
                  if (_bgmPath != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        "Current: ${_bgmPath!.split('/').last}", 
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                        maxLines: 1, overflow: TextOverflow.ellipsis
                      ),
                    ),
                  
                  const SizedBox(height: 30),
                  
                  // Video Volume
                  const Text("Original Sound", style: TextStyle(color: Colors.white)),
                  Slider(
                    value: _videoVolume,
                    min: 0.0,
                    max: 1.0,
                    activeColor: Colors.blueAccent,
                    onChanged: (val) {
                      setModalState(() => _videoVolume = val);
                      _updateVolumes(); // Live preview
                    },
                    onChangeEnd: (val) {
                       // Commit to undo stack
                       final newState = EditorState(
                         subtitles: _currentState.subtitles,
                         stickers: _currentState.stickers,
                         filter: _currentState.filter,
                         filterOpacity: _currentState.filterOpacity,
                         bgmPath: _currentState.bgmPath,
                         videoVolume: val,
                         bgmVolume: _currentState.bgmVolume,
                       );
                       _executeStateChange(newState);
                    },
                  ),
                  
                  // BGM Volume
                  const Text("BGM Volume", style: TextStyle(color: Colors.white)),
                  Slider(
                    value: _bgmVolume,
                    min: 0.0,
                    max: 1.0,
                    activeColor: Colors.purpleAccent,
                    onChanged: (val) {
                      setModalState(() => _bgmVolume = val);
                      _updateVolumes();
                    },
                    onChangeEnd: (val) {
                       final newState = EditorState(
                         subtitles: _currentState.subtitles,
                         stickers: _currentState.stickers,
                         filter: _currentState.filter,
                         filterOpacity: _currentState.filterOpacity,
                         bgmPath: _currentState.bgmPath,
                         videoVolume: _currentState.videoVolume,
                         bgmVolume: val,
                       );
                       _executeStateChange(newState);
                    },
                  ),
                ],
              ),
            );
          }
        );
      }
    );
  }
  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      builder: (context) {
        return Container(
          height: 150,
          padding: const EdgeInsets.all(20),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: FilterPreset.values.map((filter) {
              return GestureDetector(
                onTap: () {
                  // final newState = _currentState.copy(); // Unused
                  // We need to construct new state.
                  final nextState = EditorState(
                    subtitles: _currentState.subtitles,
                    stickers: _currentState.stickers,
                    filter: filter,
                    filterOpacity: _currentState.filterOpacity
                  );
                  _executeStateChange(nextState);
                  Navigator.pop(context);
                },
                child: Container(
                  width: 80,
                  margin: const EdgeInsets.only(right: 10),
                  color: _selectedFilter == filter ? Colors.blue : Colors.grey[800],
                  child: Center(
                    child: Text(filter.name, style: const TextStyle(color: Colors.white)),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }
    );
  }
  
  // Reuse existing methods via StateChangeCommand wrapper logic...
  // For brevity, I'll need to adapt _showAdvancedCaptionDialog similarly.
  Future<void> _showAdvancedCaptionDialog({SubtitleModel? editing}) async {
    final controller = TextEditingController(text: editing?.text ?? '');
    
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(editing == null ? "Add Subtitle" : "Edit Subtitle", style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller, 
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: "Enter text", hintStyle: TextStyle(color: Colors.white54)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text("Confirm")),
        ],
      )
    );
    
    if (result != null && result.isNotEmpty) {
       List<SubtitleModel> nextSubs = List.from(_subtitles);
       
       if (editing != null) {
         // Update existing
         final index = nextSubs.indexWhere((s) => s.text == editing.text && s.dx == editing.dx); // Weak ID, but ok for now
         if (index != -1) {
           nextSubs[index] = editing.copy()..text = result;
         }
       } else {
         // Add new
         nextSubs.add(SubtitleModel(text: result, dx: 0.5, dy: 0.5));
       }
       
       final nextState = EditorState(
         subtitles: nextSubs,
         stickers: _stickers,
         filter: _selectedFilter,
         filterOpacity: _filterOpacity,
       );
       _executeStateChange(nextState);
    }
  }

  void _showStickerLibrary() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: 300,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4, crossAxisSpacing: 10, mainAxisSpacing: 10
            ),
            itemCount: _stickerAssets.length,
            itemBuilder: (context, index) {
              final asset = _stickerAssets[index];
              return GestureDetector(
                onTap: () {
                   Navigator.pop(context);
                   _addSticker(asset);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24)
                  ),
                  child: Image.asset(asset, fit: BoxFit.contain),
                ),
              );
            }
          ),
        );
      }
    );
  }
  
  void _addSticker(String assetPath) {
     final nextStickers = List<StickerModel>.from(_stickers)
       ..add(StickerModel(imagePath: assetPath, dx: 0.5, dy: 0.5));
       
     final nextState = EditorState(
         subtitles: _subtitles,
         stickers: nextStickers,
         filter: _selectedFilter,
         filterOpacity: _filterOpacity,
     );
     _executeStateChange(nextState);
  }
  
  // Overlay Widgets (Keep existing logic)
  void _showSpeedMenu() {
    if (!_isInitialized || _controller == null) return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      builder: (ctx) {
        return Container(
          height: 180,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Playback Speed", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [0.5, 1.0, 1.5, 2.0].map((speed) {
                  final isSelected = (_controller!.value.playbackSpeed - speed).abs() < 0.1;
                  return ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSelected ? Colors.amber : Colors.grey[800],
                      foregroundColor: isSelected ? Colors.black : Colors.white,
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(20),
                    ),
                    onPressed: () {
                      _controller!.setPlaybackSpeed(speed);
                      Navigator.pop(ctx);
                      setState(() {});
                    },
                    child: Text("${speed}x", style: const TextStyle(fontWeight: FontWeight.bold)),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      }
    );
  }

  // Overlay Widgets
  Widget _buildStickerWidget(StickerModel sticker) {
     return Positioned(
       left: sticker.dx * MediaQuery.of(context).size.width,
       top: sticker.dy * MediaQuery.of(context).size.height,
       child: GestureDetector(
         onScaleStart: (details) {
           _tempBaseScale = sticker.scale;
         },
         onScaleUpdate: (details) {
           setState(() {
             // Handle Movement
             final screenW = MediaQuery.of(context).size.width;
             final screenH = MediaQuery.of(context).size.height;
             
             sticker.dx += details.focalPointDelta.dx / screenW;
             sticker.dy += details.focalPointDelta.dy / screenH;
             
             // Handle Scaling (Pinch)
             if (details.scale != 1.0) {
                sticker.scale = _tempBaseScale * details.scale;
             }
           });
         },
         child: Image.asset(sticker.imagePath, width: 100 * sticker.scale),
       ),
     );
  }
  
  Widget _buildSubtitleWidget(SubtitleModel subtitle) {
     return Positioned(
       left: subtitle.dx * MediaQuery.of(context).size.width,
       top: subtitle.dy * MediaQuery.of(context).size.height,
       child: GestureDetector(
         onScaleStart: (details) {
            _tempBaseFontSize = subtitle.fontSize;
         },
         onScaleUpdate: (details) {
            setState(() {
               final screenW = MediaQuery.of(context).size.width;
               final screenH = MediaQuery.of(context).size.height;
               
               subtitle.dx += details.focalPointDelta.dx / screenW;
               subtitle.dy += details.focalPointDelta.dy / screenH;
               
               if (details.scale != 1.0) {
                 subtitle.fontSize = _tempBaseFontSize * details.scale;
               }
            });
         },
         child: Text(subtitle.text, style: TextStyle(
           color: subtitle.textColor, 
           fontSize: subtitle.fontSize,
           backgroundColor: subtitle.backgroundColor
         )),
      ),
    );
  }
}

class _GenericStateCommand implements EditCommand {
  final EditorState oldState;
  final EditorState newState;
  final Function(EditorState) onRestore;

  _GenericStateCommand({required this.oldState, required this.newState, required this.onRestore});

  @override
  void execute() {
    onRestore(newState);
  }

  @override
  void undo() {
    onRestore(oldState);
  }
}

