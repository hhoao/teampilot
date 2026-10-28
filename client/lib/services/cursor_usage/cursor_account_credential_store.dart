import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/cursor_usage_account.dart';
import '../../repositories/ssh_credential_store.dart';

/// Cursor hashes the JWT `sub` into a stable account id; the same formula is
/// used by `CursorUsageAuthResolver`, so discovered and manual entries merge.
String cursorAccountIdFor(String sub) =>
    sha256.convert(utf8.encode(sub)).toString().substring(0, 16);

/// Parses any of the three paste shapes:
/// `WorkosCursorSessionToken=user_x%3A%3A<jwt>`, `user_x::<jwt>`, or `<jwt>`.
/// Returns null when the token is malformed or already inside the 60s guard.
CursorAccountCredentials? parseCursorSessionToken(String raw, {int? nowMs}) {
  var value = raw.trim();
  if (value.isEmpty) return null;
  const prefix = 'WorkosCursorSessionToken=';
  if (value.toLowerCase().startsWith(prefix.toLowerCase())) {
    value = value.substring(prefix.length);
  }
  try {
    value = Uri.decodeComponent(value);
  } on FormatException {
    // Malformed percent-encoding: keep the raw value and let the JWT parse fail.
  } on ArgumentError {
    // Not percent-encoded; keep the raw value.
  }
  final separator = value.indexOf('::');
  var token = separator >= 0 ? value.substring(separator + 2) : value;
  token = token.trim();
  final parts = token.split('.');
  if (parts.length != 3) return null;
  final Map<String, Object?> claims;
  try {
    final decoded = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (decoded is! Map) return null;
    claims = Map<String, Object?>.from(decoded);
  } on Object {
    return null;
  }
  final exp = (claims['exp'] as num?)?.toInt();
  final sub = claims['sub']?.toString().trim() ?? '';
  if (exp == null || sub.isEmpty) return null;
  final clock = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  if (exp * 1000 <= clock + 60000) return null;
  final userId = sub.split('|').where((part) => part.isNotEmpty).last;
  if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(userId)) return null;
  return CursorAccountCredentials(
    accountId: cursorAccountIdFor(sub),
    userId: userId,
    token: token,
    expiresAtMs: exp * 1000,
  );
}

final class CursorAccountCredentialStore {
  CursorAccountCredentialStore({
    required SecureKeyValueStore store,
    DateTime Function()? now,
  }) : _store = store,
       _now = now ?? DateTime.now;

  static const namespace = 'teampilot.cursor_usage.v1';

  final SecureKeyValueStore _store;
  final DateTime Function() _now;

  String _key(String accountId) => '$namespace.$accountId.token';

  Future<CursorAccountCredentials?> read(String accountId) async {
    final raw = await _store.read(_key(accountId));
    if (raw == null || raw.isEmpty) return null;
    return parseCursorSessionToken(raw, nowMs: _now().millisecondsSinceEpoch);
  }

  Future<void> write(CursorAccountCredentials credentials) =>
      _store.write(_key(credentials.accountId), credentials.token);

  Future<void> delete(String accountId) => _store.delete(_key(accountId));
}
