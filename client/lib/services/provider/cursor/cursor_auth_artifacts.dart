import 'dart:convert';

/// Catalog of Cursor CLI auth files under an isolated fake `$HOME`.
///
/// Session tokens live in `$HOME/.config/cursor/auth.json`. `cli-config.json`
/// under `$HOME/.cursor/` carries profile metadata (`authInfo`) but is not
/// sufficient for `cursor-agent` to authenticate on its own.
abstract final class CursorAuthArtifacts {
  CursorAuthArtifacts._();

  /// Relative to `$HOME/.cursor/`.
  static const cursorDirRequired = <String>['cli-config.json'];

  /// Relative to `$HOME/.cursor/`.
  static const cursorDirOptional = <String>['agent-cli-state.json'];

  /// Relative to `$HOME/.config/cursor/`.
  static const configCursorRequired = <String>['auth.json'];

  /// Back-compat aliases used by older call sites.
  static const requiredForAuth = cursorDirRequired;
  static const optionalForAuth = cursorDirOptional;

  /// Written on every mixed launch; never copied from provider store.
  static const busGenerated = <String>[
    'rules/role.mdc',
    'hooks.json',
    'hooks/idle.sh',
    'mcp.json',
  ];

  static const _accessTokenKey = 'accessToken';
  static const _refreshTokenKey = 'refreshToken';
  static const _authIdKey = 'authId';
  static const _userIdKey = 'userId';
  static const _authInfoKey = 'authInfo';

  static bool isBusGenerated(String relativePath) =>
      busGenerated.contains(relativePath);

  static bool isCursorDirAuthArtifact(String relativeToCursorDir) {
    if (isBusGenerated(relativeToCursorDir)) return false;
    return cursorDirRequired.contains(relativeToCursorDir) ||
        cursorDirOptional.contains(relativeToCursorDir);
  }

  static bool isAuthArtifact(String relativePath) =>
      isCursorDirAuthArtifact(relativePath) ||
      configCursorRequired.contains(relativePath);

  /// True when [authJson] contains OAuth session tokens.
  static bool authJsonIndicatesLoggedIn(String authJson) {
    try {
      final decoded = jsonDecode(authJson);
      if (decoded is! Map) return false;
      final access = decoded[_accessTokenKey]?.toString().trim() ?? '';
      final refresh = decoded[_refreshTokenKey]?.toString().trim() ?? '';
      return access.isNotEmpty || refresh.isNotEmpty;
    } on Object {
      return false;
    }
  }

  /// Profile metadata only — not sufficient alone for [probe] ready state.
  static bool cliConfigIndicatesLoggedIn(String cliConfigJson) {
    try {
      final decoded = jsonDecode(cliConfigJson);
      if (decoded is! Map) return false;
      final authInfo = decoded[_authInfoKey];
      if (authInfo is! Map) return false;
      final authId = authInfo[_authIdKey]?.toString().trim() ?? '';
      final userId = authInfo[_userIdKey]?.toString().trim() ?? '';
      return authId.isNotEmpty || userId.isNotEmpty;
    } on Object {
      return false;
    }
  }
}
