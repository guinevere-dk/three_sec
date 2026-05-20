import 'package:flutter/material.dart';
import '../utils/haptics.dart';

/// 🎯 공용 미디어 선택 & 줌 헬퍼
/// Library와 Vlog 화면에서 공통으로 사용하는 매직 브러시 및 줌 로직

class MediaSelectionHelper {
  /// 2-3-5 줌 처리
  static int? handleZoomGesture({
    required ScaleUpdateDetails details,
    required int currentColumnCount,
    required bool isZoomingLocked,
    required Function(int newCount) onZoomChanged,
  }) {
    if (details.pointerCount <= 1) return null;
    if (isZoomingLocked) return null;

    double sensitivity = 0.07;
    double scaleDiff = details.scale - 1.0;

    if (scaleDiff.abs() > sensitivity) {
      int newCount = currentColumnCount;

      if (scaleDiff > 0) {
        // 줌인 (열 감소)
        if (currentColumnCount == 5) {
          newCount = 3;
        } else if (currentColumnCount == 3) {
          newCount = 2;
        }
      } else {
        // 줌아웃 (열 증가)
        if (currentColumnCount == 2) {
          newCount = 3;
        } else if (currentColumnCount == 3) {
          newCount = 5;
        }
      }

      if (newCount != currentColumnCount) {
        onZoomChanged(newCount);
        hapticFeedback();
        return newCount;
      }
    }

    return null;
  }

  /// 좌표를 그리드 인덱스로 변환
  static int calculateGridIndex({
    required Offset localPosition,
    required Size gridSize,
    required int columnCount,
    required double childAspectRatio,
    double scrollOffset = 0.0,
    double topPadding = 0.0,
    EdgeInsets gridPadding = EdgeInsets.zero,
    double crossAxisSpacing = 0.0,
    double mainAxisSpacing = 0.0,
  }) {
    final double availableWidth =
        gridSize.width - gridPadding.left - gridPadding.right;
    if (availableWidth <= 0 || columnCount <= 0) return -1;

    final double cellWidth =
        (availableWidth - (crossAxisSpacing * (columnCount - 1))) / columnCount;
    if (cellWidth <= 0) return -1;
    final double cellHeight = cellWidth / childAspectRatio;
    final double rowStride = cellHeight + mainAxisSpacing;
    final double colStride = cellWidth + crossAxisSpacing;

    final double relativeX = localPosition.dx - gridPadding.left;
    final double relativeY =
        localPosition.dy + scrollOffset - topPadding - gridPadding.top;

    if (relativeX < 0 || relativeX >= availableWidth) return -1;
    if (relativeY < 0) return -1;

    final int colIdx = (relativeX / colStride).floor().clamp(
      0,
      columnCount - 1,
    );
    final int rowIdx = (relativeY / rowStride).floor();
    final int idx = (rowIdx * columnCount) + colIdx;

    return idx;
  }

  static void startDragSelection({
    required Offset focalPoint,
    required GlobalKey gridKey,
    required int columnCount,
    required double childAspectRatio,
    required List<String> targetList,
    required dynamic currentSelection, // List<String> or Set<String>
    required Function(String item, bool isAdding) onSelectionChanged,
    required Function(int index, bool isAdding) onDragStarted,
    bool Function(String item)? canSelectItem,
    double scrollOffset = 0.0,
    double topPadding = 0.0,
    EdgeInsets gridPadding = EdgeInsets.zero,
    double crossAxisSpacing = 0.0,
    double mainAxisSpacing = 0.0,
  }) {
    final rb = gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (rb == null) return;

    final lp = rb.globalToLocal(focalPoint);
    final idx = calculateGridIndex(
      localPosition: lp,
      gridSize: rb.size,
      columnCount: columnCount,
      childAspectRatio: childAspectRatio,
      scrollOffset: scrollOffset,
      topPadding: topPadding,
      gridPadding: gridPadding,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: mainAxisSpacing,
    );

    if (idx >= 0 && idx < targetList.length) {
      final String item = targetList[idx];

      // 선택 불가능한 항목 체크
      if (canSelectItem != null && !canSelectItem(item)) {
        return;
      }

      // 현재 선택 상태 확인 (List와 Set 모두 지원)
      bool isCurrentlySelected;
      if (currentSelection is List<String>) {
        isCurrentlySelected = currentSelection.contains(item);
      } else if (currentSelection is Set<String>) {
        isCurrentlySelected = currentSelection.contains(item);
      } else {
        return;
      }

      bool isAdding = !isCurrentlySelected;

      bool stateChanged = false;
      if (isAdding && !isCurrentlySelected) {
        onSelectionChanged(item, true);
        stateChanged = true;
      } else if (!isAdding && isCurrentlySelected) {
        onSelectionChanged(item, false);
        stateChanged = true;
      }

      onDragStarted(idx, isAdding);

      if (stateChanged) {
        hapticFeedback();
      }
    }
  }

  /// 매직 브러시 업데이트 (범위 선택)
  static void updateDragSelection({
    required Offset focalPoint,
    required GlobalKey gridKey,
    required int columnCount,
    required double childAspectRatio,
    required List<String> targetList,
    required dynamic currentSelection, // List<String> or Set<String>
    required int dragStartIndex,
    required bool isDragAdding,
    bool Function(String item)? canSelectItem,
    double scrollOffset = 0.0,
    double topPadding = 0.0,
    EdgeInsets gridPadding = EdgeInsets.zero,
    double crossAxisSpacing = 0.0,
    double mainAxisSpacing = 0.0,
  }) {
    final rb = gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (rb == null) return;

    final lp = rb.globalToLocal(focalPoint);
    final currentIndex = calculateGridIndex(
      localPosition: lp,
      gridSize: rb.size,
      columnCount: columnCount,
      childAspectRatio: childAspectRatio,
      scrollOffset: scrollOffset,
      topPadding: topPadding,
      gridPadding: gridPadding,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: mainAxisSpacing,
    );

    if (currentIndex < 0 || currentIndex >= targetList.length) return;

    final int start = dragStartIndex < currentIndex
        ? dragStartIndex
        : currentIndex;
    final int end = dragStartIndex > currentIndex
        ? dragStartIndex
        : currentIndex;

    for (int i = start; i <= end; i++) {
      final String item = targetList[i];

      if (canSelectItem != null && !canSelectItem(item)) continue;

      bool isCurrentlySelected;
      if (currentSelection is List<String>) {
        isCurrentlySelected = currentSelection.contains(item);
      } else if (currentSelection is Set<String>) {
        isCurrentlySelected = currentSelection.contains(item);
      } else {
        continue;
      }

      if (isDragAdding && !isCurrentlySelected) {
        if (currentSelection is List<String>) {
          currentSelection.add(item);
        } else if (currentSelection is Set<String>) {
          currentSelection.add(item);
        }
      } else if (!isDragAdding && isCurrentlySelected) {
        if (currentSelection is List<String>) {
          currentSelection.remove(item);
        } else if (currentSelection is Set<String>) {
          currentSelection.remove(item);
        }
      }
    }
  }
}
