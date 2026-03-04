import 'package:flutter/material.dart';
import 'package:three_s/models/vlog_project.dart';

/// Command Pattern Base Class
abstract class EditCommand {
  void execute();
  void undo();
}

/// Trim Command
class TrimCommand implements EditCommand {
  final VlogClip clip;
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
    debugPrint("[TrimCommand] Executed: ${clip.path} -> $newStartTime ~ $newEndTime");
  }

  @override
  void undo() {
    clip.startTime = _oldStartTime;
    clip.endTime = _oldEndTime;
    debugPrint("[TrimCommand] Undone: ${clip.path} -> $_oldStartTime ~ $_oldEndTime");
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
