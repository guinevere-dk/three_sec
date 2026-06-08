class MediaImportProcessingItem<T> {
  final T item;
  final int originalIndex;
  final int effectiveIndex;

  const MediaImportProcessingItem({
    required this.item,
    required this.originalIndex,
    required this.effectiveIndex,
  });
}

List<MediaImportProcessingItem<T>> orderMediaImportItemsForProcessing<T>(
  Iterable<T> pickerReturnedItems,
) {
  final indexedItems = pickerReturnedItems.toList(growable: false).asMap();
  var effectiveIndex = 0;
  return <MediaImportProcessingItem<T>>[
    for (final entry in indexedItems.entries)
      MediaImportProcessingItem<T>(
        item: entry.value,
        originalIndex: entry.key,
        effectiveIndex: effectiveIndex++,
      ),
  ];
}

List<int> orderImportedClipSegmentsForAlbumRegistration(
  Iterable<int> segmentStartMs,
) {
  final ordered = segmentStartMs.toList(growable: false)
    ..sort((a, b) => b.compareTo(a));
  return ordered;
}
