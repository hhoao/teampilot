import 'dart:convert';

import '../../utils/lock_pool.dart';
import '../cli/cli_data_layout.dart';
import '../io/filesystem.dart';

/// Allocates monotonic `{teamId}-{seq}` CLI runtime names per team.
class SessionTeamCounter {
  SessionTeamCounter({required Filesystem fs, required CliDataLayout layout})
    : _fs = fs,
      _layout = layout;

  final Filesystem _fs;
  final CliDataLayout _layout;
  static final _locks = LockPool();

  Future<String> nextCliTeamName(String teamId) async {
    final trimmed = teamId.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(teamId, 'teamId', 'must not be empty');
    }
    return _locks.synchronized(trimmed, () async {
      final path = _layout.teamSessionCounterFile(trimmed);
      var nextSeq = 0;
      final raw = await _fs.readString(path);
      if (raw != null && raw.trim().isNotEmpty) {
        try {
          final json = jsonDecode(raw);
          if (json is Map<String, Object?>) {
            final value = json['nextSeq'];
            if (value is int) {
              nextSeq = value;
            } else if (value is num) {
              nextSeq = value.toInt();
            }
          }
        } on Object {
          // ignore corrupt counter; restart from 0
        }
      }
      nextSeq += 1;
      await _fs.atomicWrite(
        path,
        jsonEncode(<String, Object?>{'nextSeq': nextSeq}),
      );
      return '$trimmed-$nextSeq';
    });
  }
}
