import 'hlc.dart';

/// One element's observed add/remove tags.
///
/// An element is present when it has at least one add tag that has not been
/// removed. `remove` moves the currently observed add tags into [removed], so
/// a concurrent add from another replica (a new tag) still survives.
final class OrSetEntry {
  const OrSetEntry({this.added = const {}, this.removed = const {}});

  final Set<String> added;
  final Set<String> removed;

  bool get contains => added.difference(removed).isNotEmpty;

  OrSetEntry addTag(String tag) {
    final trimmed = tag.trim();
    if (trimmed.isEmpty) return this;
    return OrSetEntry(added: {...added, trimmed}, removed: removed);
  }

  OrSetEntry removeObserved() {
    if (added.isEmpty) return this;
    return OrSetEntry(added: added, removed: {...removed, ...added});
  }

  OrSetEntry merge(OrSetEntry other) => OrSetEntry(
    added: {...added, ...other.added},
    removed: {...removed, ...other.removed},
  );

  Map<String, Object?> toJson() => {
    'a': added.toList()..sort(),
    'r': removed.toList()..sort(),
  };

  static OrSetEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final added = _stringSet(json['a']);
    final removed = _stringSet(json['r']);
    return OrSetEntry(added: added, removed: removed);
  }
}

/// Observed-remove set (OR-Set) keyed by string ids.
///
/// Typical use: workspace favourites. A concurrent add and remove resolves in
/// favour of the add, because the remove only tombstones the add tags it has
/// observed.
final class OrSet {
  const OrSet({this.entries = const {}});

  final Map<String, OrSetEntry> entries;

  Set<String> get values => {
    for (final entry in entries.entries)
      if (entry.value.contains) entry.key,
  };

  bool contains(String element) => entries[element.trim()]?.contains ?? false;

  int get tombstoneTagCount =>
      entries.values.fold(0, (sum, entry) => sum + entry.removed.length);

  OrSet add(String element, Hlc stamp) {
    final key = element.trim();
    if (key.isEmpty) return this;
    final current = entries[key] ?? const OrSetEntry();
    return OrSet(entries: {...entries, key: current.addTag(stamp.toWire())});
  }

  /// Removes every add tag currently observed for [element]. A replica that
  /// has not observed a concurrent add keeps that add alive on merge.
  OrSet remove(String element) {
    final key = element.trim();
    if (key.isEmpty) return this;
    final current = entries[key];
    if (current == null || current.added.isEmpty) return this;
    return OrSet(entries: {...entries, key: current.removeObserved()});
  }

  OrSet merge(OrSet other) {
    final merged = <String, OrSetEntry>{...entries};
    for (final entry in other.entries.entries) {
      final local = merged[entry.key];
      merged[entry.key] = local == null
          ? entry.value
          : local.merge(entry.value);
    }
    return OrSet(entries: merged);
  }

  Map<String, Object?> toJson() => {
    'elements': {
      for (final entry in entries.entries) entry.key: entry.value.toJson(),
    },
  };

  static OrSet fromJson(Object? json) {
    if (json is! Map) return const OrSet();
    final raw = json['elements'];
    if (raw is! Map) return const OrSet();
    final entries = <String, OrSetEntry>{};
    for (final entry in raw.entries) {
      final key = entry.key.toString().trim();
      if (key.isEmpty) continue;
      final parsed = OrSetEntry.fromJson(entry.value);
      if (parsed != null) entries[key] = parsed;
    }
    return OrSet(entries: entries);
  }
}

Set<String> _stringSet(Object? raw) {
  if (raw is! List) return const {};
  return {
    for (final item in raw)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  };
}
