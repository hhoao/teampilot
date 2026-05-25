import 'claude_hook_shell.dart';
import '../io/filesystem.dart';

/// Deploys the team-lead self-target guard hook into a member Claude config dir.
class TeamLeadHookProvisioner {
  TeamLeadHookProvisioner({
    required Filesystem fs,
    required Future<String> Function(ClaudeHookShell shell) loadHookScript,
  }) : _fs = fs,
       _loadHookScript = loadHookScript;

  final Filesystem _fs;
  final Future<String> Function(ClaudeHookShell shell) _loadHookScript;

  static const shFileName = 'teampilot-deny-team-lead-self-message.sh';
  static const ps1FileName = 'teampilot-deny-team-lead-self-message.ps1';

  static String fileNameFor(ClaudeHookShell shell) => switch (shell) {
    ClaudeHookShell.bash => shFileName,
    ClaudeHookShell.powershell => ps1FileName,
  };

  Future<String> provisionMemberToolDir(
    String memberToolDir,
    ClaudeHookShell shell,
  ) async {
    final hooksDir = _fs.pathContext.join(memberToolDir, 'hooks');
    await _fs.ensureDir(hooksDir);
    final dest = _fs.pathContext.join(hooksDir, fileNameFor(shell));
    final script = await _loadHookScript(shell);
    await _fs.writeString(dest, script);
    return dest;
  }

  String hookCommandForPath(String scriptPath, ClaudeHookShell shell) =>
      ClaudeHookShellResolver.hookCommandForPath(scriptPath, shell);
}
