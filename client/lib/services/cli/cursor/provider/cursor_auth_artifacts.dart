import 'dart:convert';

/// Catalog of Cursor CLI auth files under an isolated fake `$HOME`.
///
/// Session tokens live in `$HOME/.cursor/auth.json` on macOS (file store) or
/// `$HOME/.config/cursor/auth.json` on Linux/Windows (and on Windows also
/// `%APPDATA%\Cursor\auth.json` from Cursor IDE). `cli-config.json`
/// under `$HOME/.cursor/` carries profile metadata (`authInfo`) but is not
/// sufficient for `cursor-agent` to authenticate on its own.
abstract final class CursorAuthArtifacts {
  CursorAuthArtifacts._();

  /// Relative to `$HOME/.cursor/`.
  static const cursorDirRequired = <String>['cli-config.json'];

  /// Relative to `$HOME/.cursor/`.
  static const cursorDirOptional = <String>[
    'agent-cli-state.json',
    'statsig-cache.json',
  ];

  /// Written into isolated `$HOME/.cursor/agent-cli-state.json` so
  /// `cursor-agent` does not re-print the "`agent` vs `cursor-agent`" tip on
  /// every TeamPilot session (each session uses a fresh fake HOME).
  static const agentCliStateVersion = 1;
  static const hasShownAgentCommandTipKey = 'hasShownAgentCommandTip';

  /// Relative to `$HOME/.config/cursor/` (or `%APPDATA%\Cursor\` on Windows IDE).
  static const configCursorRequired = <String>['auth.json'];

  /// Back-compat aliases used by older call sites.
  static const requiredForAuth = cursorDirRequired;
  static const optionalForAuth = cursorDirOptional;

  /// Written on every mixed launch; never copied from provider store.
  static const busGenerated = <String>[
    'rules/role.mdc',
    'hooks.json',
    'hooks/teampilot-http-teampilot-bus-idle-stop-stop.sh',
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

  /// True when both blobs carry the same OAuth access/refresh tokens.
  static bool authJsonTokensEqual(String a, String b) {
    try {
      final decodedA = jsonDecode(a);
      final decodedB = jsonDecode(b);
      if (decodedA is! Map || decodedB is! Map) return false;
      return (decodedA[_accessTokenKey]?.toString() ?? '') ==
              (decodedB[_accessTokenKey]?.toString() ?? '') &&
          (decodedA[_refreshTokenKey]?.toString() ?? '') ==
              (decodedB[_refreshTokenKey]?.toString() ?? '');
    } on Object {
      return false;
    }
  }

  /// True when both `cli-config.json` blobs name the same Cursor account.
  static bool cliConfigAuthInfoEqual(String a, String b) {
    try {
      final decodedA = jsonDecode(a);
      final decodedB = jsonDecode(b);
      if (decodedA is! Map || decodedB is! Map) return false;
      final infoA = decodedA[_authInfoKey];
      final infoB = decodedB[_authInfoKey];
      if (infoA is! Map || infoB is! Map) return identical(infoA, infoB);
      return (infoA[_authIdKey]?.toString().trim() ?? '') ==
              (infoB[_authIdKey]?.toString().trim() ?? '') &&
          (infoA[_userIdKey]?.toString().trim() ?? '') ==
              (infoB[_userIdKey]?.toString().trim() ?? '');
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
