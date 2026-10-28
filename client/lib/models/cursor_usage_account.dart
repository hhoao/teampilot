import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

enum CursorAccountSource { discovered, manual }

/// Metadata for one Cursor account. The session token is NOT part of this
/// class: it lives in secure storage and is read on demand, so a list render
/// can never leak it through `toString` or equality.
@immutable
final class CursorUsageAccount extends Equatable {
  const CursorUsageAccount({
    required this.accountId,
    required this.userId,
    required this.label,
    required this.source,
    this.enabled = true,
    this.expiresAtMs,
    this.owningUser,
    this.teamId = 0,
    this.hasCredential = false,
  });

  final String accountId;
  final String userId;
  final String label;
  final CursorAccountSource source;
  final bool enabled;
  final int? expiresAtMs;
  final String? owningUser;
  final int teamId;
  final bool hasCredential;

  /// Expired when the token would die inside the next minute.
  bool isExpired(int nowMs) {
    final expires = expiresAtMs;
    return expires == null || expires <= nowMs + 60000;
  }

  CursorUsageAccount copyWith({
    String? label,
    bool? enabled,
    int? expiresAtMs,
    String? owningUser,
    int? teamId,
    bool? hasCredential,
    CursorAccountSource? source,
  }) => CursorUsageAccount(
    accountId: accountId,
    userId: userId,
    label: label ?? this.label,
    source: source ?? this.source,
    enabled: enabled ?? this.enabled,
    expiresAtMs: expiresAtMs ?? this.expiresAtMs,
    owningUser: owningUser ?? this.owningUser,
    teamId: teamId ?? this.teamId,
    hasCredential: hasCredential ?? this.hasCredential,
  );

  Map<String, Object?> toJson() => {
    'accountId': accountId,
    'userId': userId,
    'label': label,
    'source': source.name,
    'enabled': enabled,
    'expiresAtMs': expiresAtMs,
    'owningUser': owningUser,
    'teamId': teamId,
  };

  factory CursorUsageAccount.fromJson(Map<String, Object?> json) {
    final source = CursorAccountSource.values.firstWhere(
      (value) => value.name == json['source'],
      orElse: () => CursorAccountSource.manual,
    );
    return CursorUsageAccount(
      accountId: json['accountId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      source: source,
      enabled: json['enabled'] != false,
      expiresAtMs: (json['expiresAtMs'] as num?)?.toInt(),
      owningUser: json['owningUser']?.toString(),
      teamId: (json['teamId'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [
    accountId,
    userId,
    label,
    source,
    enabled,
    expiresAtMs,
    owningUser,
    teamId,
    hasCredential,
  ];
}

/// A resolvable credential. `cookie` is the only place the header is built.
@immutable
final class CursorAccountCredentials extends Equatable {
  const CursorAccountCredentials({
    required this.accountId,
    required this.userId,
    required this.token,
    required this.expiresAtMs,
  });

  final String accountId;
  final String userId;
  final String token;
  final int expiresAtMs;

  String get cookie => 'WorkosCursorSessionToken=$userId%3A%3A$token';

  @override
  List<Object?> get props => [accountId, userId, token, expiresAtMs];

  @override
  String toString() => 'CursorAccountCredentials($accountId)';
}
