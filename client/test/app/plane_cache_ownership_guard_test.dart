import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Invariant I1 of the home-plane isolation spec: plane-derived state must be
/// instance state owned by the runtime, never a static cache.
void main() {
  test('no static collection caches in plane-derived layers', () {
    const guardedDirs = [
      'lib/repositories',
      'lib/services/storage',
      'lib/services/search',
    ];

    // Coordination primitives keyed by path/id that self-clean when idle and
    // hold no plane data. Add an entry only with a comment explaining why it is
    // not a plane cache.
    const allowlist = {
      // Serializes concurrent writers per storage path; entries are removed
      // when the mutation finishes.
      'lib/repositories/managed_provider_storage_lock.dart:_tails',
      // Tracks in-flight provider-id deletions; entries are removed at idle.
      'lib/repositories/managed_provider_id_deletion_barrier.dart:_states',
    };

    final declaration = RegExp(
      r'^\s*static\s+(?:final\s+)?(?:Map|List|Set)<[^=;\n]*>'
      r'\s+([A-Za-z_]\w*)\s*=',
      multiLine: true,
    );

    final violations = <String>[];
    for (final dir in guardedDirs) {
      for (final entity in Directory(dir).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final text = entity.readAsStringSync();
        for (final match in declaration.allMatches(text)) {
          final id =
              '${entity.path.replaceAll(r'\', '/')}:${match.group(1)}';
          if (!allowlist.contains(id)) violations.add(id);
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Plane-derived caches must be instance state owned by HomeRuntime. '
          'If the entry is coordination-only, add it to the allowlist with a '
          'reason.',
    );
  });
}
