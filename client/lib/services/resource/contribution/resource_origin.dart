/// Where a resource contribution came from.
enum ResourceOriginKind {
  managed,
  team,
  expert,
  workspace,
  plugin,
  extension,
  catalog,
  cliBuiltIn,
}

/// Stable provenance attached to one resource contribution.
class ContributionOrigin {
  const ContributionOrigin({
    required this.providerId,
    required this.kind,
    this.sourceId,
  });

  final String providerId;
  final ResourceOriginKind kind;
  final String? sourceId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContributionOrigin &&
          providerId == other.providerId &&
          kind == other.kind &&
          sourceId == other.sourceId;

  @override
  int get hashCode => Object.hash(providerId, kind, sourceId);

  @override
  String toString() =>
      'ContributionOrigin(providerId: $providerId, kind: $kind, '
      'sourceId: $sourceId)';
}
