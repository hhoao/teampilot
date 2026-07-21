import '../opencode_native_session_id.dart';
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
    final dataDir = _dataDirFromEnv(ctx);
    final persisted = ctx.persistedNativeId?.trim() ?? '';
    if (dataDir.isEmpty) {
      return persisted.isEmpty ? null : persisted;
    }
    return resolveOpencodeNativeSessionId(
      fs: ctx.fs,
      dataDir: dataDir,
      persistedNativeId: ctx.persistedNativeId,
    );
  }

  static String _dataDirFromEnv(ResumeContext ctx) {
    final db = ctx.env['OPENCODE_DB']?.trim() ?? '';
    if (db.isEmpty || db == ':memory:') return '';
    return ctx.fs.pathContext.dirname(db);
  }
}
