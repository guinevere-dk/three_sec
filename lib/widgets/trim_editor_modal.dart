
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/vlog_project.dart';
import '../managers/video_manager.dart';

class TrimEditorModal extends StatefulWidget {
  final VlogClip clip;
  final VideoManager videoManager;
  final VideoPlayerController controller;

  const TrimEditorModal({
    Key? key,
    required this.clip,
    required this.videoManager,
    required this.controller,
  }) : super(key: key);

  @override
  State<TrimEditorModal> createState() => _TrimEditorModalState();
}

class _TrimEditorModalState extends State<TrimEditorModal> {
  late Timer _timer;
  double _currentMs = 0;

  @override
  void initState() {
    super.initState();
    _currentMs = widget.controller.value.position.inMilliseconds.toDouble();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (mounted && widget.controller.value.isPlaying) {
        setState(() {
          _currentMs = widget.controller.value.position.inMilliseconds.toDouble();
        });
        
        // Loop Check
        if (_currentMs >= widget.clip.endTime.inMilliseconds) {
           widget.controller.pause();
           widget.controller.seekTo(widget.clip.startTime);
           // Auto-play loop? Let's keep it manual for now to be safe, or just seek.
        }
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.clip.originalDuration.inMilliseconds.toDouble();
    
    return Container(
      height: 300,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
           const Text("Trim Clip", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
           const SizedBox(height: 20),
           Expanded(
             child: LayoutBuilder(
               builder: (context, constraints) {
                 final double width = constraints.maxWidth;
                 if (totalMs <= 0 || width <= 0) return const SizedBox();

                 final double startMs = widget.clip.startTime.inMilliseconds.toDouble();
                 final double endMs = widget.clip.endTime.inMilliseconds.toDouble();
                 
                 final double startPx = (startMs / totalMs) * width;
                 final double endPx = (endMs / totalMs) * width;
                 final double currentPx = (_currentMs / totalMs) * width;
                 
                 return Stack(
                   alignment: Alignment.centerLeft,
                   children: [
                     // 1. Thumbnails Background
                     Positioned.fill(
                       child: TrimTimelineBackground(
                         clip: widget.clip,
                         totalDurationMs: totalMs.toInt(),
                         videoManager: widget.videoManager,
                       ),
                     ),

                     // 2. Dimmed Areas
                     Positioned(
                       left: 0,
                       width: startPx,
                       top: 0,
                       bottom: 0,
                       child: Container(color: Colors.black.withOpacity(0.6)),
                     ),
                     Positioned(
                       left: endPx,
                       width: width - endPx,
                       top: 0,
                       bottom: 0,
                       child: Container(color: Colors.black.withOpacity(0.6)),
                     ),

                     // 3. Selection Border
                     Positioned(
                       left: startPx,
                       width: endPx - startPx,
                       top: 0,
                       bottom: 0,
                       child: Container(
                         decoration: BoxDecoration(
                           border: Border.all(color: const Color(0xFFF2F20D), width: 2),
                           borderRadius: BorderRadius.circular(4),
                         ),
                       ),
                     ),

                     // 4. Left Handle
                     Positioned(
                       left: startPx - 20,
                       top: 0,
                       bottom: 0,
                       child: GestureDetector(
                         onHorizontalDragUpdate: (details) {
                            final newPx = (startPx + details.delta.dx).clamp(0.0, endPx - 20);
                            final newMs = (newPx / width) * totalMs;
                            setState(() {
                              widget.clip.startTime = Duration(milliseconds: newMs.toInt());
                            });
                            widget.controller.seekTo(widget.clip.startTime);
                         },
                         child: Container(
                           width: 40,
                           color: Colors.transparent,
                           alignment: Alignment.center,
                           child: Container(
                             width: 16,
                             height: 60,
                             decoration: const BoxDecoration(
                               color: Color(0xFFF2F20D),
                               borderRadius: BorderRadius.horizontal(left: Radius.circular(4)),
                             ),
                             child: const Icon(Icons.chevron_left, color: Colors.black, size: 16),
                           ),
                         ),
                       ),
                     ),

                     // 5. Right Handle
                     Positioned(
                       left: endPx - 20,
                       top: 0,
                       bottom: 0,
                       child: GestureDetector(
                         onHorizontalDragUpdate: (details) {
                            final newPx = (endPx + details.delta.dx).clamp(startPx + 20, width);
                            final newMs = (newPx / width) * totalMs;
                            setState(() {
                              widget.clip.endTime = Duration(milliseconds: newMs.toInt());
                            });
                             // Optional: preview end
                         },
                         child: Container(
                           width: 40,
                           color: Colors.transparent,
                           alignment: Alignment.center,
                           child: Container(
                             width: 16,
                             height: 60,
                             decoration: const BoxDecoration(
                               color: Color(0xFFF2F20D),
                               borderRadius: BorderRadius.horizontal(right: Radius.circular(4)),
                             ),
                             child: const Icon(Icons.chevron_right, color: Colors.black, size: 16),
                           ),
                         ),
                       ),
                     ),
                     
                     // 6. Scrubber (White Line)
                     Positioned(
                        left: currentPx - 10,
                        top: 0,
                        bottom: 0,
                        child: GestureDetector(
                          onHorizontalDragUpdate: (details) {
                             final newPx = (currentPx + details.delta.dx).clamp(0.0, width);
                             final newMs = (newPx / width) * totalMs;
                             
                             // Snap to start/end
                             double finalMs = newMs;
                             if ((newMs - startMs).abs() < (totalMs * 0.05)) finalMs = startMs;
                             if ((newMs - endMs).abs() < (totalMs * 0.05)) finalMs = endMs;
                             
                             setState(() {
                               _currentMs = finalMs;
                             });
                             widget.controller.seekTo(Duration(milliseconds: finalMs.toInt()));
                          },
                          child: Container(
                             width: 20,
                             color: Colors.transparent,
                             alignment: Alignment.center,
                             child: Container(
                               width: 2,
                               height: double.infinity,
                               color: Colors.white,
                               child: Align(
                                 alignment: Alignment.topCenter,
                                 child: Container(
                                   width: 6,
                                   height: 6,
                                   decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                 ),
                               ),
                             ),
                          )
                        )
                     )
                   ],
                 );
               }
             ),
           ),
           const SizedBox(height: 20),
           Row(
             mainAxisAlignment: MainAxisAlignment.end,
             children: [
               TextButton(
                 onPressed: () => Navigator.pop(context),
                 child: const Text("Done", style: TextStyle(color: Colors.blueAccent)),
               )
             ],
           )
        ],
      ),
    );
  }
}

// Isolated widget to handle thumbnail loading statefully
class TrimTimelineBackground extends StatefulWidget {
  final VlogClip clip;
  final int totalDurationMs;
  final VideoManager videoManager;

  const TrimTimelineBackground({
    Key? key, 
    required this.clip, 
    required this.totalDurationMs, 
    required this.videoManager
  }) : super(key: key);

  @override
  State<TrimTimelineBackground> createState() => _TrimTimelineBackgroundState();
}

class _TrimTimelineBackgroundState extends State<TrimTimelineBackground> {
  Future<List<Uint8List>>? _thumbnailsFuture;

  @override
  void initState() {
    super.initState();
    _loadThumbnails();
  }

  @override
  void didUpdateWidget(TrimTimelineBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clip.path != widget.clip.path) {
      _loadThumbnails();
    }
  }

  void _loadThumbnails() {
    setState(() {
      _thumbnailsFuture = widget.videoManager.getTimelineThumbnails(
        widget.clip.path, 
        widget.totalDurationMs, 
        3
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FutureBuilder<List<Uint8List>>(
          future: _thumbnailsFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Container(
                color: Colors.grey[300], 
                child: const Center(child: Icon(Icons.error, color: Colors.red))
              );
            }
            if (snapshot.hasData && snapshot.data!.isNotEmpty) {
              return Row(
                children: snapshot.data!.map((bytes) {
                  return Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(right: BorderSide(color: Colors.white.withOpacity(0.2), width: 0.5)),
                      ),
                      child: Image.memory(
                        bytes, 
                        fit: BoxFit.cover,
                        height: double.infinity,
                        width: double.infinity,
                      ),
                    ),
                  );
                }).toList(),
              );
            }
            return Row(
              children: List.generate(3, (index) {
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    color: Colors.grey[300],
                    child: const Center(
                       child: Icon(Icons.downloading, color: Colors.grey, size: 16),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}
