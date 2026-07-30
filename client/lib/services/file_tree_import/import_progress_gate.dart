bool shouldShowImportProgress({
  required int flattenedFileCount,
  required int maxFileBytes,
  required bool destIsLocal,
  int fileCountThreshold = 10,
  int byteThreshold = 5 * 1024 * 1024,
}) {
  if (!destIsLocal) {
    return true;
  }
  if (flattenedFileCount >= fileCountThreshold) {
    return true;
  }
  if (maxFileBytes >= byteThreshold) {
    return true;
  }
  return false;
}
