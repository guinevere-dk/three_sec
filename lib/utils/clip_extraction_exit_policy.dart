bool shouldBlockClipExtractionExit({
  required bool isExporting,
  required bool hasActiveTrackedSaves,
}) {
  return isExporting || hasActiveTrackedSaves;
}
