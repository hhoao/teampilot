/// Discriminator for [WorkspaceIdentity]: a solo personal setup or a team.
enum IdentityKind {
  personal('personal'),
  team('team');

  const IdentityKind(this.value);

  final String value;

  static IdentityKind decode(Object? raw) {
    final normalized = raw?.toString().trim().toLowerCase() ?? '';
    for (final kind in IdentityKind.values) {
      if (kind.value == normalized) return kind;
    }
    return IdentityKind.personal;
  }
}
