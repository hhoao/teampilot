import 'log_helpers.dart';

bool logLineMatchesLevel(String line, String level) {
  final upper = line.toUpperCase();
  return switch (level) {
    'DEBUG' => upper.contains('DEBUG'),
    'INFO' => upper.contains('INFO') || upper.contains('[BOOT]'),
    'WARNING' => upper.contains('WARNING') || upper.contains('WARN'),
    'ERROR' => upper.contains('ERROR') || upper.contains('EXCEPTION'),
    _ => true,
  };
}

List<String> filterLogLines({
  required List<String> rawLines,
  required bool compactView,
  required String searchText,
  required String selectedLevel,
}) {
  var filtered = List<String>.from(rawLines);
  if (compactView) {
    filtered = filtered.where((l) => !isLogDecorationLine(l)).toList();
  }
  if (searchText.isNotEmpty) {
    final q = searchText.toLowerCase();
    filtered = filtered.where((l) => l.toLowerCase().contains(q)).toList();
  }
  if (selectedLevel != 'ALL') {
    filtered = filtered
        .where((l) => logLineMatchesLevel(l, selectedLevel))
        .toList();
  }
  return filtered;
}

const kLogViewerLevels = ['ALL', 'DEBUG', 'INFO', 'WARNING', 'ERROR'];
