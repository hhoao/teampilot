import 'package:flutter/foundation.dart';

/// How a project is opened: simple/personal mode, or as a specific team.
/// Encoded on the project route as `?as=personal` or `?as=team:<teamId>`.
@immutable
class LaunchIdentity {
  const LaunchIdentity._(this.teamId);

  /// Simple mode — no team. [teamId] is empty.
  static const personal = LaunchIdentity._('');

  /// Team mode for [teamId] (must be non-empty).
  const LaunchIdentity.team(this.teamId);

  /// Stable team id, or empty string for personal.
  final String teamId;

  bool get isPersonal => teamId.isEmpty;

  String encode() => isPersonal ? 'personal' : 'team:$teamId';

  /// Parses the `?as=` query value. Returns null when absent or malformed.
  static LaunchIdentity? decode(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    if (value == 'personal') return LaunchIdentity.personal;
    const prefix = 'team:';
    if (value.startsWith(prefix)) {
      final id = value.substring(prefix.length).trim();
      if (id.isEmpty) return null;
      return LaunchIdentity.team(id);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LaunchIdentity &&
          runtimeType == other.runtimeType &&
          teamId == other.teamId;

  @override
  int get hashCode => teamId.hashCode;

  @override
  String toString() => 'LaunchIdentity(${encode()})';
}
