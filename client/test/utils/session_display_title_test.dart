import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/session_display_title.dart';

void main() {
  test('trims and collapses whitespace', () {
    expect(
      deriveSessionTitleFromFirstPrompt('  fix   the   bug  '),
      'fix the bug',
    );
  });

  test('uses first line only', () {
    expect(
      deriveSessionTitleFromFirstPrompt('line one\nline two'),
      'line one',
    );
  });

  test('truncates with ellipsis', () {
    final long = 'a' * 60;
    expect(
      deriveSessionTitleFromFirstPrompt(long, maxLength: 10),
      '${'a' * 9}…',
    );
  });

  test('returns empty for blank input', () {
    expect(deriveSessionTitleFromFirstPrompt('   '), '');
  });
}
