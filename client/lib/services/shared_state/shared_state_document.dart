import 'hlc.dart';

/// Merges one raw JSON section. Implementations must be commutative,
/// associative, and idempotent: the store may re-apply them after a conflict.
typedef SharedStateSectionMerge =
    Object? Function(Object? local, Object? remote);

/// Per-section merge policy for [SharedStateDocument.merge].
///
/// Unknown sections fall back to a stamp comparison (`t` field) and otherwise
/// keep the remote value, which is the safest choice for a section this client
/// does not understand.
final class SharedStateMergeRegistry {
  const SharedStateMergeRegistry([this.mergers = const {}]);

  final Map<String, SharedStateSectionMerge> mergers;

  Object? mergeSection(String key, Object? local, Object? remote) {
    final merger = mergers[key];
    if (merger != null) return merger(local, remote);
    return _mergeByStamp(local, remote);
  }
}

Object? _mergeByStamp(Object? local, Object? remote) {
  final localStamp = _stampOf(local);
  final remoteStamp = _stampOf(remote);
  if (localStamp == null) return remote;
  if (remoteStamp == null) return local;
  return remoteStamp.compareTo(localStamp) > 0 ? remote : local;
}

Hlc? _stampOf(Object? value) {
  if (value is! Map) return null;
  return Hlc.fromJson(value['t']);
}

/// The shared-state envelope stored in the home plane.
///
/// Sections are raw JSON so a client that does not understand a newer domain
/// can carry it through a read-modify-write unchanged. [merge] never drops a
/// section; per-domain rules live in [SharedStateMergeRegistry].
final class SharedStateDocument {
  const SharedStateDocument({
    required this.schemaVersion,
    required this.revision,
    required this.updatedAt,
    required this.sections,
  });

  static const currentSchemaVersion = 1;

  final int schemaVersion;

  /// Write token. A new value is generated for every successful write; it is
  /// how the store detects that another writer slipped in between read/write.
  final String revision;
  final Hlc updatedAt;
  final Map<String, Object?> sections;

  static SharedStateDocument empty() => const SharedStateDocument(
    schemaVersion: currentSchemaVersion,
    revision: '',
    updatedAt: Hlc.zero,
    sections: {},
  );

  T? section<T>(String key) {
    final value = sections[key];
    return value is T ? value : null;
  }

  SharedStateDocument withSection(String key, Object? value) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return this;
    return copyWith(sections: {...sections, trimmed: value});
  }

  SharedStateDocument withoutSection(String key) {
    final trimmed = key.trim();
    if (!sections.containsKey(trimmed)) return this;
    return copyWith(
      sections: {
        for (final entry in sections.entries)
          if (entry.key != trimmed) entry.key: entry.value,
      },
    );
  }

  SharedStateDocument copyWith({
    int? schemaVersion,
    String? revision,
    Hlc? updatedAt,
    Map<String, Object?>? sections,
  }) => SharedStateDocument(
    schemaVersion: schemaVersion ?? this.schemaVersion,
    revision: revision ?? this.revision,
    updatedAt: updatedAt ?? this.updatedAt,
    sections: sections ?? this.sections,
  );

  SharedStateDocument merge(
    SharedStateDocument other,
    SharedStateMergeRegistry registry,
  ) {
    final keys = {...sections.keys, ...other.sections.keys};
    final merged = <String, Object?>{};
    for (final key in keys) {
      final local = sections[key];
      final remote = other.sections[key];
      if (local == null && remote != null) {
        merged[key] = remote;
      } else if (remote == null && local != null) {
        merged[key] = local;
      } else {
        merged[key] = registry.mergeSection(key, local, remote);
      }
    }
    return SharedStateDocument(
      schemaVersion: other.schemaVersion > schemaVersion
          ? other.schemaVersion
          : schemaVersion,
      revision: other.revision,
      updatedAt: updatedAt.max(other.updatedAt),
      sections: merged,
    );
  }

  Map<String, Object?> toJson() => {
    'schema': schemaVersion,
    'revision': revision,
    't': updatedAt.toJson(),
    'sections': sections,
  };

  static SharedStateDocument? fromJson(Object? json) {
    if (json is! Map) return null;
    final schema = json['schema'];
    final revision = json['revision'];
    final sectionsRaw = json['sections'];
    final sections = <String, Object?>{};
    if (sectionsRaw is Map) {
      for (final entry in sectionsRaw.entries) {
        final key = entry.key.toString().trim();
        if (key.isNotEmpty) sections[key] = entry.value;
      }
    }
    return SharedStateDocument(
      schemaVersion: schema is num ? schema.toInt() : currentSchemaVersion,
      revision: revision is String ? revision : '',
      updatedAt: Hlc.fromJson(json['t']) ?? Hlc.zero,
      sections: sections,
    );
  }
}
