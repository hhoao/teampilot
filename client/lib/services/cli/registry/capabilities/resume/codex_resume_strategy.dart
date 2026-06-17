import '../session_resume_capability.dart';

/// `postCaptured` strategy for codex. codex generates its own session id and
/// cannot be told ours, but `$CODEX_HOME` is isolated per session, so its
/// `sessions/**/rollout-*.jsonl` tree holds exactly this session's rollout. We
/// capture the uuid embedded in the rollout filename and resume with
/// `codex resume <uuid>`.
final class CodexResumeStrategy implements SessionResumeCapability {
  const CodexResumeStrategy();

  static final _rolloutId = RegExp(
    r'rollout-.*-([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}'
    r'-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\.jsonl$',
  );

  @override
  ResumeBinding get binding => ResumeBinding.postCaptured;

  @override
  Future<String?> detectNativeId(ResumeContext ctx) async {
    // A previously captured id is authoritative.
    final persisted = ctx.persistedNativeId?.trim() ?? '';
    if (persisted.isNotEmpty) return persisted;

    final home = ctx.env['CODEX_HOME']?.trim() ?? '';
    if (home.isEmpty) return null;
    final sessionsDir = ctx.fs.pathContext.join(home, 'sessions');
    final basename = ctx.fs.pathContext.basename;

    var bestName = '';
    try {
      final entries = await ctx.fs.listDirRecursive(sessionsDir);
      for (final e in entries) {
        if (e.isDirectory) continue;
        if (!_rolloutId.hasMatch(basename(e.name))) continue;
        // Lexicographic max over timestamp-prefixed names == newest. The
        // isolated home normally holds a single rollout anyway.
        if (e.name.compareTo(bestName) > 0) bestName = e.name;
      }
    } on Object {
      return null;
    }
    if (bestName.isEmpty) return null;
    return _rolloutId.firstMatch(basename(bestName))?.group(1);
  }
}
