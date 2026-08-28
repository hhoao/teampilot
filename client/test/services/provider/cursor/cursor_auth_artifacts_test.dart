import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_auth_artifacts.dart';

void main() {
  test('requiredForAuth includes cli-config.json', () {
    expect(CursorAuthArtifacts.requiredForAuth, contains('cli-config.json'));
  });

  test('optional cursor-dir artifacts include statsig-cache.json', () {
    expect(
      CursorAuthArtifacts.cursorDirOptional,
      contains('statsig-cache.json'),
    );
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

  test('authJsonTokensEqual compares access and refresh tokens', () {
    expect(
      CursorAuthArtifacts.authJsonTokensEqual(
        '{"accessToken":"at1","refreshToken":"rt1"}',
        '{"accessToken":"at1","refreshToken":"rt1","extra":true}',
      ),
      isTrue,
    );
    expect(
      CursorAuthArtifacts.authJsonTokensEqual(
        '{"accessToken":"at1","refreshToken":"rt1"}',
        '{"accessToken":"at-b","refreshToken":"rt-b"}',
      ),
      isFalse,
    );
  });

  test('cliConfigAuthInfoEqual compares account identity', () {
    expect(
      CursorAuthArtifacts.cliConfigAuthInfoEqual(
        '{"authInfo":{"userId":"u1","authId":"a1"},"model":"x"}',
        '{"authInfo":{"userId":"u1","authId":"a1"}}',
      ),
      isTrue,
    );
    expect(
      CursorAuthArtifacts.cliConfigAuthInfoEqual(
        '{"authInfo":{"userId":"u1","authId":"a1"}}',
        '{"authInfo":{"userId":"u-b","authId":"a-b"}}',
      ),
      isFalse,
    );
  });
}
