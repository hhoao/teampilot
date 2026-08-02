import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/router/android_shell_chrome.dart';

void main() {
  group('isHubDetailPath', () {
    test('treats library section paths as hub detail', () {
      expect(AndroidShellChrome.isHubDetailPath('/skills/installed'), isTrue);
      expect(AndroidShellChrome.isHubDetailPath('/plugins/installed'), isTrue);
      expect(AndroidShellChrome.isHubDetailPath('/extensions/installed'), isTrue);
      expect(AndroidShellChrome.isHubDetailPath('/mcp/discovery'), isTrue);
    });

    test('keeps config and team-config detail paths', () {
      expect(AndroidShellChrome.isHubDetailPath('/config/layout'), isTrue);
      expect(AndroidShellChrome.isHubDetailPath('/team-config/skills'), isTrue);
    });

    test('library roots are not hub detail', () {
      expect(AndroidShellChrome.isHubDetailPath('/skills'), isFalse);
      expect(AndroidShellChrome.isHubDetailPath('/plugins'), isFalse);
    });
  });

  group('isLibrarySectionPath', () {
    test('includes library roots and section paths', () {
      expect(AndroidShellChrome.isLibrarySectionPath('/skills'), isTrue);
      expect(AndroidShellChrome.isLibrarySectionPath('/skills/discovery'), isTrue);
      expect(AndroidShellChrome.isLibrarySectionPath('/plugins/marketplaces'), isTrue);
      expect(AndroidShellChrome.isLibrarySectionPath('/extensions/installed'), isTrue);
      expect(AndroidShellChrome.isLibrarySectionPath('/mcp/registries'), isTrue);
    });

    test('excludes MCP form paths', () {
      expect(AndroidShellChrome.isLibrarySectionPath('/mcp/add'), isFalse);
      expect(AndroidShellChrome.isLibrarySectionPath('/mcp/edit/server-1'), isFalse);
    });

    test('excludes config and providers paths', () {
      expect(AndroidShellChrome.isLibrarySectionPath('/config/layout'), isFalse);
      expect(AndroidShellChrome.isLibrarySectionPath('/providers/claude'), isFalse);
      expect(AndroidShellChrome.isLibrarySectionPath('/team-config/mcp'), isFalse);
    });
  });
}
