import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/codebuddy/provider/codebuddy_region.dart';

void main() {
  test('maps login domains to the cloud they belong to', () {
    expect(
      CodebuddyRegion.forAuthDomain('www.codebuddy.ai'),
      CodebuddyRegion.external,
    );
    expect(
      CodebuddyRegion.forAuthDomain('WWW.CodeBuddy.CN'),
      CodebuddyRegion.internal,
    );
    expect(
      CodebuddyRegion.forAuthDomain('www.workbuddy.cn'),
      CodebuddyRegion.internal,
    );
    expect(CodebuddyRegion.forAuthDomain('copilot.example.com'), isNull);
    expect(CodebuddyRegion.forAuthDomain(null), isNull);
    expect(CodebuddyRegion.forAuthDomain('  '), isNull);
  });

  test('cached region path is the CLI localStorage entry for its key', () {
    expect(
      CodebuddyRegion.cacheEntryPath(p.Context(style: p.Style.posix), '/cfg'),
      '/cfg/local_storage/entry_3bab4ce61838088127d444e4cc042d6d.info',
    );
  });
}
