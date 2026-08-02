import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/router/app_router.dart';

void main() {
  group('libraryRootRedirect', () {
    test('redirects in-scope library roots to installed section', () {
      expect(libraryRootRedirect('/skills'), '/skills/installed');
      expect(libraryRootRedirect('/plugins'), '/plugins/installed');
      expect(libraryRootRedirect('/mcp'), '/mcp/installed');
      expect(libraryRootRedirect('/extensions'), '/extensions/installed');
    });

    test('ignores non-library roots', () {
      expect(libraryRootRedirect('/config'), isNull);
      expect(libraryRootRedirect('/skills/installed'), isNull);
      expect(libraryRootRedirect('/home-v2'), isNull);
    });
  });
}
