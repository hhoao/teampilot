import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../io/filesystem.dart';
import 'hlc.dart';
import 'shared_state_document.dart';

/// Thrown when the shared-state file exists but cannot be parsed.
///
/// Callers should not silently overwrite a corrupt document: that would turn
/// one bad write into data loss for every device.
final class SharedStateFormatException implements Exception {
  const SharedStateFormatException(this.path, this.cause);

  final String path;
  final Object cause;

  @override
  String toString() => 'SharedStateFormatException($path): $cause';
}

/// Thrown when [SharedStateStore.update] cannot converge after its retries.
final class SharedStateConflictException implements Exception {
  const SharedStateConflictException(this.path, this.attempts);

  final String path;
  final int attempts;

  @override
  String toString() =>
      'SharedStateConflictException($path): conflict after $attempts attempts';
}

/// Reads, merges, and writes one shared-state document in the home plane.
///
/// This is optimistic concurrency, not a distributed lock: every write gets a
/// fresh [SharedStateDocument.revision], then the store re-reads and retries
/// when another device wrote in between. Mutations are re-applied to the latest
/// merged document, so they must be idempotent (CRDT add/remove/set operations).
final class SharedStateStore {
  SharedStateStore({
    required Filesystem fs,
    required String path,
    required HlcClock clock,
    SharedStateMergeRegistry? mergeRegistry,
    String Function()? revisionFactory,
  }) : _fs = fs,
       _path = path,
       _clock = clock,
       _mergeRegistry = mergeRegistry ?? const SharedStateMergeRegistry(),
       _revisionFactory = revisionFactory ?? _defaultRevision;

  static const _uuid = Uuid();

  final Filesystem _fs;
  final String _path;
  final HlcClock _clock;
  final SharedStateMergeRegistry _mergeRegistry;
  final String Function() _revisionFactory;

  String get path => _path;

  static String _defaultRevision() => _uuid.v4();

  /// Raw JSON currently on disk, or null when the file is missing/empty.
  ///
  /// Domain stores use this to detect a pre-shared-state legacy payload before
  /// [read] treats it as an empty document.
  Future<Object?> readJson() async {
    final text = await _fs.readString(_path);
    if (text == null || text.trim().isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException catch (error) {
      throw SharedStateFormatException(_path, error);
    }
  }

  Future<SharedStateDocument> read() async {
    final decoded = await readJson();
    if (decoded == null) return SharedStateDocument.empty();
    final document = SharedStateDocument.fromJson(decoded);
    if (document == null) {
      throw SharedStateFormatException(_path, 'document is not an object');
    }
    return document;
  }

  /// Applies [mutate] and writes the result, retrying on a concurrent writer.
  ///
  /// [mutate] is called again on every attempt with the latest merged document;
  /// keep it idempotent and side-effect free.
  Future<SharedStateDocument> update(
    SharedStateDocument Function(SharedStateDocument current) mutate, {
    int maxAttempts = 5,
  }) async {
    if (maxAttempts < 1) {
      throw ArgumentError.value(maxAttempts, 'maxAttempts');
    }
    var base = await read();
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final next = mutate(base);
      final revision = _revisionFactory();
      final written = next.copyWith(
        schemaVersion:
            next.schemaVersion < SharedStateDocument.currentSchemaVersion
            ? SharedStateDocument.currentSchemaVersion
            : next.schemaVersion,
        revision: revision,
        updatedAt: _clock.now(),
      );
      await _write(written);
      final observed = await read();
      if (observed.revision == revision) return written;
      // Another writer landed between our read and write. Merge its version
      // with ours, then re-apply [mutate] on the merged base.
      base = written.merge(observed, _mergeRegistry);
    }
    throw SharedStateConflictException(_path, maxAttempts);
  }

  Future<void> _write(SharedStateDocument document) async {
    final dir = _fs.pathContext.dirname(_path);
    if (dir.isNotEmpty && dir != '.') {
      await _fs.ensureDir(dir);
    }
    await _fs.atomicWrite(_path, jsonEncode(document.toJson()));
  }
}
