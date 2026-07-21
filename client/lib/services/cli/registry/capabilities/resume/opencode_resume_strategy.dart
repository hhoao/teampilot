import '../session_resume_capability.dart';

/// `postCaptured` strategy for opencode. opencode generates `ses_*` ids; we
/// isolate the session via absolute `OPENCODE_DB` (see the config profile), so
/// the SQLite / legacy `storage/session/**/<id>.json` tree is unambiguous. We
/// capture the id and resume with `--session <id>`.
final class OpencodeResumeStrategy implements SessionResumeCapability {
  const OpencodeResumeStrategy();

  @override
  ResumeBinding get binding => ResumeBinding.postCaptured;

  @override
  Future<String?> detectNativeId(ResumeContext ctx) async {
    final persisted = ctx.persistedNativeId?.trim() ?? '';
    if (persisted.isNotEmpty) return persisted;

    final dataDir = _dataDirFromEnv(ctx);
    if (dataDir.isEmpty) return null;
    final path = ctx.fs.pathContext;
    final sessionDir = path.join(dataDir, 'storage', 'session');

    var bestName = '';
    try {
      final entries = await ctx.fs.listDirRecursive(sessionDir);
      for (final e in entries) {
        if (e.isDirectory) continue;
        final name = path.basename(e.name);
        if (!name.startsWith('ses_') || !name.endsWith('.json')) continue;
        if (e.name.compareTo(bestName) > 0) bestName = e.name;
      }
    } on Object {
      return null;
    }
    if (bestName.isEmpty) return null;
    final name = path.basename(bestName);
    return name.substring(0, name.length - '.json'.length);
  }

  static String _dataDirFromEnv(ResumeContext ctx) {
    final db = ctx.env['OPENCODE_DB']?.trim() ?? '';
    if (db.isEmpty || db == ':memory:') return '';
    return ctx.fs.pathContext.dirname(db);
  }
}
