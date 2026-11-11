import 'log_helpers.dart';

List<String> filterLogLines({
  required List<String> rawLines,
  required bool compactView,
  required String searchText,
}) {
  var filtered = List<String>.from(rawLines);
  if (compactView) {
    filtered = filtered.where((l) => !isLogDecorationLine(l)).toList();
  }
  if (searchText.isNotEmpty) {
    final q = searchText.toLowerCase();
    filtered = filtered.where((l) => l.toLowerCase().contains(q)).toList();
  }
  return filtered;
}

List<String> logViewerLevels({required bool includeDebug}) {
  return ['ALL', if (includeDebug) 'DEBUG', 'INFO', 'WARNING', 'ERROR'];
}
