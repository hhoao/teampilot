import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/app_paths.dart';

void main() {
  test('cursor usage paths live under the teampilot root', () {
    const paths = AppPaths('/root/teampilot');
    expect(paths.cursorUsageDir, '/root/teampilot/cursor_usage');
    expect(
      paths.cursorUsageAccountsFile,
      '/root/teampilot/cursor_usage/accounts.json',
    );
    expect(
      paths.cursorUsageCacheFile('abc'),
      '/root/teampilot/cursor_usage/cache/abc.json',
    );
  });
}
