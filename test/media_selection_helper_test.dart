import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:three_s/utils/media_selection_helper.dart';

void main() {
  test('clip grid hit test keeps lower edge inside current tile', () {
    const gridSize = Size(300, 600);
    const gridPadding = EdgeInsets.fromLTRB(8, 8, 8, 210);
    const columnCount = 3;
    const spacing = 3.0;
    final availableWidth =
        gridSize.width - gridPadding.left - gridPadding.right;
    final cellWidth =
        (availableWidth - spacing * (columnCount - 1)) / columnCount;
    const topPadding = 112.0;
    const scrollOffset = 0.0;

    final lowerEdgeIndex = MediaSelectionHelper.calculateGridIndex(
      localPosition: Offset(
        gridPadding.left + cellWidth / 2,
        topPadding + gridPadding.top + cellWidth - 0.5,
      ),
      gridSize: gridSize,
      columnCount: columnCount,
      childAspectRatio: 1,
      scrollOffset: scrollOffset,
      topPadding: topPadding,
      gridPadding: gridPadding,
      crossAxisSpacing: spacing,
      mainAxisSpacing: spacing,
    );

    final rowGapIndex = MediaSelectionHelper.calculateGridIndex(
      localPosition: Offset(
        gridPadding.left + cellWidth / 2,
        topPadding + gridPadding.top + cellWidth + spacing - 0.5,
      ),
      gridSize: gridSize,
      columnCount: columnCount,
      childAspectRatio: 1,
      scrollOffset: scrollOffset,
      topPadding: topPadding,
      gridPadding: gridPadding,
      crossAxisSpacing: spacing,
      mainAxisSpacing: spacing,
    );

    final nextRowIndex = MediaSelectionHelper.calculateGridIndex(
      localPosition: Offset(
        gridPadding.left + cellWidth / 2,
        topPadding + gridPadding.top + cellWidth + spacing + 0.5,
      ),
      gridSize: gridSize,
      columnCount: columnCount,
      childAspectRatio: 1,
      scrollOffset: scrollOffset,
      topPadding: topPadding,
      gridPadding: gridPadding,
      crossAxisSpacing: spacing,
      mainAxisSpacing: spacing,
    );

    expect(lowerEdgeIndex, 0);
    expect(rowGapIndex, 0);
    expect(nextRowIndex, 3);
  });
}
