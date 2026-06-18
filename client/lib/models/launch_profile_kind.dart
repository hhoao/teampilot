/// Discriminator for [LaunchProfile]: a solo personal setup or a team.
enum LaunchProfileKind {
  personal('personal'),
  team('team');

  const LaunchProfileKind(this.value);

  final String value;

  static LaunchProfileKind decode(Object? raw) {
    final normalized = raw?.toString().trim().toLowerCase() ?? '';
    for (final kind in LaunchProfileKind.values) {
      if (kind.value == normalized) return kind;
    }
    return LaunchProfileKind.personal;
  }
}
