import 'package:flutter/foundation.dart';

/// Which identity a directory is opened against. Encoded on the workspace route
/// as `?as=<profileId>`. Kind is resolved from the loaded identity record.
@immutable
class LaunchProfileRef {
  const LaunchProfileRef(this.profileId);

  final String profileId;

  String encode() => profileId;

  static LaunchProfileRef? decode(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    return LaunchProfileRef(value);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LaunchProfileRef &&
          runtimeType == other.runtimeType &&
          profileId == other.profileId;

  @override
  int get hashCode => profileId.hashCode;

  @override
  String toString() => 'LaunchProfileRef($profileId)';
}
