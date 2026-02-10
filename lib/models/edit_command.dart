
import 'package:flutter/material.dart';

/// 비파괴 편집을 위한 클립 모델
class ClipModel {
  final String path;
  final String id; // Unique ID for identifying clips
  Duration startTime;
  Duration endTime;
  Duration totalDuration;

  ClipModel({
    required this.path,
    required this.id,
    this.startTime = Duration.zero,
    required this.endTime,
    required this.totalDuration,
  });

  ClipModel copy() {
    return ClipModel(
      path: path,
      id: id,
      startTime: startTime,
      endTime: endTime,
      totalDuration: totalDuration,
    );
  }
}

/// Command Pattern Base Class
abstract class EditCommand {
  void execute();
  void undo();
}

/// Trim Command
class TrimCommand implements EditCommand {
  final ClipModel clip;
  final Duration newStartTime;
  final Duration newEndTime;
  
  final Duration _oldStartTime;
  final Duration _oldEndTime;

  TrimCommand(this.clip, this.newStartTime, this.newEndTime)
      : _oldStartTime = clip.startTime,
        _oldEndTime = clip.endTime;

  @override
  void execute() {
    clip.startTime = newStartTime;
    clip.endTime = newEndTime;
    debugPrint("[TrimCommand] Executed: ${clip.id} -> $newStartTime ~ $newEndTime");
  }

  @override
  void undo() {
    clip.startTime = _oldStartTime;
    clip.endTime = _oldEndTime;
    debugPrint("[TrimCommand] Undone: ${clip.id} -> $_oldStartTime ~ $_oldEndTime");
  }
}

/// Undo/Redo Manager adapting Command Pattern
class CommandManager {
  final List<EditCommand> _undoStack = [];
  final List<EditCommand> _redoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void execute(EditCommand command) {
    command.execute();
    _undoStack.add(command);
    _redoStack.clear();
    debugPrint("[CommandManager] Stack size: ${_undoStack.length}");
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    final command = _undoStack.removeLast();
    command.undo();
    _redoStack.add(command);
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    final command = _redoStack.removeLast();
    command.execute();
    _undoStack.add(command);
  }
}
