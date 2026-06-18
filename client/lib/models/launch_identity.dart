import 'package:flutter/foundation.dart';

/// Which identity a directory is opened against. Encoded on the workspace route
/// as `?as=<identityId>`. Kind is resolved from the loaded identity record.
@immutable
class LaunchIdentity {
  const LaunchIdentity(this.identityId);

  final String identityId;

  String encode() => identityId;

  static LaunchIdentity? decode(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    return LaunchIdentity(value);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LaunchIdentity &&
          runtimeType == other.runtimeType &&
          identityId == other.identityId;

  @override
  int get hashCode => identityId.hashCode;

  @override
  String toString() => 'LaunchIdentity($identityId)';
}
