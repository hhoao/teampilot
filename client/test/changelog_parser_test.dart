import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/changelog_parser.dart';

void main() {
  test('parseMarkdownContent splits version sections', () {
    final entries = ChangelogData.parseMarkdownContent('''
## 1.2.0
- Fix crash
- Improve UI

## 1.1.0
- Initial release
''');

    expect(entries, hasLength(2));
    expect(entries.first.version, '1.2.0');
    expect(entries.first.items, contains('Fix crash'));
    expect(entries.last.version, '1.1.0');
  });
}
