import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Invariant I1 of the home-plane isolation spec: plane-derived state must be
/// instance state owned by the runtime, never a static cache.
const _guardedDirs = [
  'lib/repositories',
  'lib/services/storage',
  'lib/services/search',
];

// Coordination primitives keyed by path/id that self-clean when idle and
// hold no plane data. Add an entry only with a comment explaining why it is
// not a plane cache.
const _allowlist = {
  // Serializes concurrent writers per storage path; entries are removed
  // when the mutation finishes.
  'lib/repositories/managed_provider_storage_lock.dart:_tails',
  // Tracks in-flight provider-id deletions; entries are removed at idle.
  'lib/repositories/managed_provider_id_deletion_barrier.dart:_states',
  // Serializes read-modify-write per launch-profile index path; holds locks,
  // not profiles.
  'lib/repositories/launch_profile_index_store.dart:_mutationLocks',
  // Serializes read-modify-write per session index path; holds locks, not
  // session data.
  'lib/repositories/session_list_index_store.dart:_mutationLocks',
  // Serializes read-modify-write per workspace index path; holds locks, not
  // workspace data.
  'lib/repositories/workspace_index_store.dart:_mutationLocks',
  // Monotonic per-catalog-path revision counters used to reject stale
  // results; holds counters, not provider data.
  'lib/repositories/managed_provider_repository.dart:_values',
};

/// Declarations of static fields that can hold a mutable collection or a
/// plane-bound cache. `const` is deliberately not accepted: const values are
/// immutable and cannot be plane caches.
///
/// 1. Explicitly typed: `static [late] [final] Map<K, V>? _x = ...`, with or
///    without an initializer (a declaration ending in `;` is just as much a
///    cache the first load can populate). Newlines are allowed inside `<...>`
///    so wrapped generic types still match, while `{}`/`()` are not, which
///    stops the span at method parameter lists.
/// 2. Type-inferred: `static [late] [final] _x = <K, V>{...}` (or `[...]`),
///    `= {}` / `= []`, or `= Map<K, V>()` / `= PlaneSnapshotCache<T>()`,
///    none of which have the type token in pattern 1's position.
final _collectionDeclarations = [
  RegExp(
    r'^\s*static\s+(?:late\s+)?(?:final\s+)?'
    r'(?:Map|List|Set|HashMap|LinkedHashMap|SplayTreeMap|PlaneSnapshotCache)'
    r'\s*<[^=;{}()]*>\??\s+([A-Za-z_]\w*)\s*(?:=|;)',
    multiLine: true,
  ),
  RegExp(
    r'^\s*static\s+(?:late\s+)?(?:final\s+)?([A-Za-z_]\w*)\s*=\s*'
    r'(?:<[^;{}()]*>\s*[\{\[]'
    r'|(?:Map|List|Set|HashMap|LinkedHashMap|SplayTreeMap|PlaneSnapshotCache)'
    r'\s*<[^;{}()]*>\s*\('
    r'|[\{\[])',
    multiLine: true,
  ),
];

/// Field names declared by the static collection forms in [source].
List<String> _matchingFields(String source) => [
  for (final pattern in _collectionDeclarations)
    for (final match in pattern.allMatches(source)) match.group(1)!,
];

void main() {
  test('no static collection caches in plane-derived layers', () {
    final seen = <String>[];
    for (final dir in _guardedDirs) {
      for (final entity in Directory(dir).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        for (final field in _matchingFields(entity.readAsStringSync())) {
          seen.add('$path:$field');
        }
      }
    }

    // Self-check: the matcher must still see every allowlisted declaration.
    // Without this, a refactored regex or a renamed file would leave the guard
    // green while enforcing nothing; it also surfaces stale allowlist entries.
    expect(
      seen,
      containsAll(_allowlist),
      reason:
          'The static-collection matcher no longer sees allowlisted '
          'declarations. Fix the matcher (or prune the stale allowlist entry) '
          'instead of deleting this assertion.',
    );
    expect(
      _matchingFields('static final Map<String, int> _x = {};'),
      contains('_x'),
      reason: 'The static-collection matcher stopped matching typed fields.',
    );

    final violations =
        seen.where((id) => !_allowlist.contains(id)).toList()..sort();
    expect(
      violations,
      isEmpty,
      reason:
          'Plane-derived caches must be instance state owned by HomeRuntime. '
          'If the entry is coordination-only, add it to the allowlist with a '
          'reason.',
    );
  });

  group('static collection matcher', () {
    test('catches every form that can hold a plane cache', () {
      const samples = [
        // Nullable typed field.
        'static Map<String, int>? _cache = {};',
        // `late` in the modifier position.
        'static late final Map<String, int> _cache = {};',
        // Declaration without an initializer: the first load can still fill it.
        'static Map<String, int>? _cache;',
        'static late final Map<String, int> _cache;',
        // Type-inferred map, list and set initializers.
        'static final _cache = <String, int>{};',
        'static final _cache = <String>[];',
        'static final _cache = <String>{};',
        // Untyped literals.
        'static final _cache = {};',
        'static final _cache = [];',
        // Typed constructors without a static type annotation.
        'static final _cache = Map<String, int>();',
        'static final _cache = PlaneSnapshotCache<Workspace>();',
        // PlaneSnapshotCache is the cache type this plan introduces.
        'static final PlaneSnapshotCache<Workspace> _cache = '
            'PlaneSnapshotCache<Workspace>();',
        'static PlaneSnapshotCache<Workspace>? _cache;',
        // Explicit map implementations.
        'static HashMap<String, int> _cache = HashMap();',
        'static LinkedHashMap<String, int> _cache = LinkedHashMap();',
        'static SplayTreeMap<String, int> _cache = SplayTreeMap();',
        // Generic type wrapped across lines.
        'static final Map<\n    String,\n    int,\n  > _cache = {};',
      ];
      for (final sample in samples) {
        expect(_matchingFields(sample), isNotEmpty, reason: sample);
      }
    });

    test('ignores const collections and non-field declarations', () {
      const samples = [
        // Const collections are immutable; `static const` inferred included.
        'static const Map<String, int> _keys = {};',
        'static const List<String> _names = [];',
        "static const builtInTeamIds = {'a', 'b'};",
        // Statics that are not fields.
        'static Map<String, Object?> fn(String x) => {};',
        'static List<String> get names => [];',
        // Non-collection fields.
        'static final int _count = 0;',
        'static final String _pattern = r"x";',
      ];
      for (final sample in samples) {
        expect(_matchingFields(sample), isEmpty, reason: sample);
      }
    });
  });
}
