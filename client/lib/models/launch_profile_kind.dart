/// Discriminator for [LaunchProfile]. Only team identities remain; Simple
/// launch is a session mode, not a profile kind.
enum LaunchProfileKind {
  team('team');

  const LaunchProfileKind(this.value);

  final String value;

  /// Decodes a persisted kind. Unknown / legacy `personal` values throw —
  /// callers that scan disk should skip those records.
  static LaunchProfileKind decode(Object? raw) {
    final normalized = raw?.toString().trim().toLowerCase() ?? '';
    if (normalized == team.value || normalized.isEmpty) {
      return LaunchProfileKind.team;
    }
    throw FormatException('Unknown LaunchProfileKind: $raw');
  }
}
