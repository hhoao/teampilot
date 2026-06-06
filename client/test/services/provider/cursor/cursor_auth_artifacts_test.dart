import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider/cursor/cursor_auth_artifacts.dart';

void main() {
  test('requiredForAuth includes cli-config.json', () {
    expect(CursorAuthArtifacts.requiredForAuth, contains('cli-config.json'));
  });

  test('configCursorRequired includes auth.json', () {
    expect(CursorAuthArtifacts.configCursorRequired, contains('auth.json'));
  });

  test('busGenerated paths are not auth artifacts', () {
    for (final path in CursorAuthArtifacts.busGenerated) {
      expect(CursorAuthArtifacts.isAuthArtifact(path), isFalse);
    }
  });

  test('authJsonIndicatesLoggedIn reads OAuth tokens', () {
    const loggedIn = '''
{"accessToken":"at1","refreshToken":"rt1"}
''';
    const loggedOut = '''
{"accessToken":"","refreshToken":""}
''';
    expect(CursorAuthArtifacts.authJsonIndicatesLoggedIn(loggedIn), isTrue);
    expect(CursorAuthArtifacts.authJsonIndicatesLoggedIn(loggedOut), isFalse);
  });

  test('cliConfigIndicatesLoggedIn reads authInfo', () {
    const loggedIn = '''
{"authInfo":{"userId":"u1","authId":"a1"}}
''';
    const loggedOut = '''
{"authInfo":{}}
''';
    expect(CursorAuthArtifacts.cliConfigIndicatesLoggedIn(loggedIn), isTrue);
    expect(CursorAuthArtifacts.cliConfigIndicatesLoggedIn(loggedOut), isFalse);
  });
}
