import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Metadata for one Cursor account. The session token is NOT part of this
/// class: it is rediscovered from the provider home on demand, so a list
/// render can never leak it through `toString` or equality.
@immutable
final class CursorUsageAccount extends Equatable {
  const CursorUsageAccount({
    required this.accountId,
    required this.userId,
    required this.label,
    this.enabled = true,
    this.expiresAtMs,
    this.owningUser,
    this.teamId = 0,
    this.providerId,
    this.providerName,
  });

  final String accountId;
  final String userId;
  final String label;
  final bool enabled;
  final int? expiresAtMs;
  final String? owningUser;
  final int teamId;

  /// Provider-home directory the token was discovered in. Null for manual
  /// accounts; display-only and never persisted.
  final String? providerId;

  /// Human name of [providerId] from the app provider catalog, resolved at
  /// list time. Falls back to null when the catalog has no such provider.
  final String? providerName;

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
    String? providerId,
    String? providerName,
  }) => CursorUsageAccount(
    accountId: accountId,
    userId: userId,
    label: label ?? this.label,
    enabled: enabled ?? this.enabled,
    expiresAtMs: expiresAtMs ?? this.expiresAtMs,
    owningUser: owningUser ?? this.owningUser,
    teamId: teamId ?? this.teamId,
    providerId: providerId ?? this.providerId,
    providerName: providerName ?? this.providerName,
  );

  Map<String, Object?> toJson() => {
    'accountId': accountId,
    'userId': userId,
    'label': label,
    'enabled': enabled,
    'expiresAtMs': expiresAtMs,
    'owningUser': owningUser,
    'teamId': teamId,
  };

  factory CursorUsageAccount.fromJson(Map<String, Object?> json) {
    return CursorUsageAccount(
      accountId: json['accountId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
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
    enabled,
    expiresAtMs,
    owningUser,
    teamId,
    providerId,
    providerName,
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
