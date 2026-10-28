import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../../../io/filesystem.dart';
import 'cursor_home_layout.dart';

@immutable
class CursorUsageAuth extends Equatable {
  const CursorUsageAuth({
    required this.token,
    required this.account,
    required this.userId,
    required this.expiresAtMs,
    required this.modifiedAtMs,
  });

  final String token;
  final String account;
  final String userId;
  final int expiresAtMs;
  final int modifiedAtMs;

  String get cookie => 'WorkosCursorSessionToken=$userId%3A%3A$token';

  @override
  List<Object?> get props => [
    token,
    account,
    userId,
    expiresAtMs,
    modifiedAtMs,
  ];
}

/// Resolves a live Cursor OAuth token from the app's isolated provider homes,
/// then from global Cursor auth files.
///
/// Cursor's dashboard usage is account-level. TeamPilot may have several
/// provider homes; the longest-lived unexpired token wins so an old, expired
/// provider cannot shadow the account currently in use.
final class CursorUsageAuthResolver {
  CursorUsageAuthResolver({
    required Filesystem fs,
    required String basePath,
    required String home,
    CursorHomeLayout? layout,
    DateTime Function()? now,
  }) : _fs = fs,
       _basePath = basePath,
       _home = home,
       _layout = layout ?? CursorHomeLayout(pathContext: fs.pathContext),
       _now = now ?? DateTime.now;

  final Filesystem _fs;
  final String _basePath;
  final String _home;
  final CursorHomeLayout _layout;
  final DateTime Function() _now;

  Future<CursorUsageAuth?> resolve() async {
    final candidates = await _candidatePaths();
    CursorUsageAuth? best;
    for (final path in candidates) {
      final auth = await _readAuth(path);
      if (auth == null) continue;
      if (best == null ||
          auth.modifiedAtMs > best.modifiedAtMs ||
          (auth.modifiedAtMs == best.modifiedAtMs &&
              auth.expiresAtMs > best.expiresAtMs)) {
        best = auth;
      }
    }
    return best;
  }

  Future<List<String>> _candidatePaths() async {
    final path = _fs.pathContext;
    final out = <String>[];
    final seen = <String>{};
    final providersRoot = path.join(_basePath, 'providers', 'cursor');
    if ((await _fs.stat(providersRoot)).isDirectory) {
      final entries = await _fs.listDir(providersRoot);
      entries.sort((a, b) => a.name.compareTo(b.name));
      for (final entry in entries) {
        if (!entry.isDirectory) continue;
        final home = path.join(providersRoot, entry.name, 'home');
        final auth = _layout.authJson(home);
        if (seen.add(auth)) out.add(auth);
      }
    }
    for (final candidate in _layout.globalAuthJsonCandidates(_home)) {
      if (seen.add(candidate)) out.add(candidate);
    }
    return out;
  }

  Future<CursorUsageAuth?> _readAuth(String path) async {
    final stat = await _fs.stat(path);
    if (!stat.isFile) return null;
    final raw = await _fs.readString(path);
    if (raw == null || raw.trim().isEmpty) return null;
    Map<String, Object?> json;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      json = Map<String, Object?>.from(decoded);
    } on Object {
      return null;
    }
    final token = json['accessToken']?.toString().trim() ?? '';
    if (token.isEmpty) return null;
    final claims = _claims(token);
    if (claims == null) return null;
    final expiresAtMs = (claims['exp'] as num?)?.toInt() ?? 0;
    final nowMs = _now().millisecondsSinceEpoch;
    if (expiresAtMs * 1000 <= nowMs + 60000) return null;
    final sub = claims['sub']?.toString().trim() ?? '';
    if (sub.isEmpty) return null;
    final userId = sub.split('|').where((part) => part.isNotEmpty).last;
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(userId)) return null;
    return CursorUsageAuth(
      token: token,
      account: sha256.convert(utf8.encode(sub)).toString().substring(0, 16),
      userId: userId,
      expiresAtMs: expiresAtMs * 1000,
      modifiedAtMs: stat.mtime?.millisecondsSinceEpoch ?? 0,
    );
  }

  Map<String, Object?>? _claims(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final decoded = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final json = jsonDecode(decoded);
      if (json is! Map) return null;
      return Map<String, Object?>.from(json);
    } on Object {
      return null;
    }
  }
}
