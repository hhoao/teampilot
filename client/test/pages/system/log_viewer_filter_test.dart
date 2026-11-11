import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/system/log_viewer_filter.dart';

void main() {
  test('filterLogLines does not drop other levels', () {
    final lines = [
      '2026-11-11 00:00:00.000 |  INFO 1 | a.dart:1:1 | hello',
      '2026-11-11 00:00:00.000 | ERROR 1 | a.dart:1:1 | boom',
    ];
    expect(
      filterLogLines(rawLines: lines, compactView: false, searchText: ''),
      lines,
    );
  });

  test('logViewerLevels hides DEBUG when includeDebug is false', () {
    expect(logViewerLevels(includeDebug: true), [
      'ALL',
      'DEBUG',
      'INFO',
      'WARNING',
      'ERROR',
    ]);
    expect(logViewerLevels(includeDebug: false), [
      'ALL',
      'INFO',
      'WARNING',
      'ERROR',
    ]);
  });
}
