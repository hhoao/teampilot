import '../session_resume_capability.dart';

/// `postCaptured` strategy for opencode. opencode generates `ses_*` ids; we
/// isolate `$OPENCODE_DATA_DIR` per session (see the config profile), so
/// `storage/session/**/<id>.json` holds exactly this session's record. We
/// capture the id (filename without `.json`) and resume with `--session <id>`.
final class OpencodeResumeStrategy implements SessionResumeCapability {
  const OpencodeResumeStrategy();

  @override
  ResumeBinding get binding => ResumeBinding.postCaptured;

  @override
  Future<String?> detectNativeId(ResumeContext ctx) async {
    final persisted = ctx.persistedNativeId?.trim() ?? '';
    if (persisted.isNotEmpty) return persisted;

    final dataDir = ctx.env['OPENCODE_DATA_DIR']?.trim() ?? '';
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
}
