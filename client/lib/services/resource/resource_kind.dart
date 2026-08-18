/// The three kinds of linkable resource a CLI session can consume.
enum ResourceKind { skill, plugin, mcp }

/// One enabled resource, resolved to its canonical on-disk source.
class ResourceRef {
  const ResourceRef({
    required this.id,
    required this.linkName,
    required this.sourceDir,
  });

  /// Catalog id (used for diagnostics / warnings).
  final String id;

  /// Basename to create under `<configDir>/<kindSubdir>/`.
  final String linkName;

  /// Absolute path to the canonical install to link to
  /// (e.g. `<teampilotRoot>/skills/installed/<dir>`).
  final String sourceDir;

  ResourceRef copyWith({String? id, String? linkName, String? sourceDir}) =>
      ResourceRef(
        id: id ?? this.id,
        linkName: linkName ?? this.linkName,
        sourceDir: sourceDir ?? this.sourceDir,
      );

  @override
  bool operator ==(Object other) =>
      other is ResourceRef &&
      other.id == id &&
      other.linkName == linkName &&
      other.sourceDir == sourceDir;

  @override
  int get hashCode => Object.hash(id, linkName, sourceDir);
}

/// Effective enabled resources for one launch scope, grouped by kind.
class EffectiveResourceSet {
  const EffectiveResourceSet(this.byKind);

  /// Creates a desired set with immutable per-kind lists for assembler and
  /// materializer facades that already own their selection logic.
  factory EffectiveResourceSet.immutable(
    Map<ResourceKind, Iterable<ResourceRef>> byKind,
  ) => EffectiveResourceSet({
    for (final entry in byKind.entries)
      entry.key: List<ResourceRef>.unmodifiable(entry.value),
  });

  final Map<ResourceKind, List<ResourceRef>> byKind;

  List<ResourceRef> of(ResourceKind kind) => byKind[kind] ?? const [];
}
