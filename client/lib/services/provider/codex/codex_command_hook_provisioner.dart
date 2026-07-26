import '../../host/host_script_dialect.dart';
import '../../host/host_script_runner.dart';
import '../../io/filesystem.dart';

/// Writes a Codex hook script under [hooksDir] and returns its launch command.
final class CodexCommandHookProvisioner {
  CodexCommandHookProvisioner({
    required Filesystem fs,
    required HostScriptRunner runner,
  }) : _fs = fs,
       _runner = runner;

  final Filesystem _fs;
  final HostScriptRunner _runner;

  Future<String> provision({
    required String hooksDir,
    required String baseFileName,
    required String scriptBody,
  }) async {
    await _fs.ensureDir(hooksDir);
    final fileName = '$baseFileName${_runner.dialect.scriptExtension}';
    final path = _fs.pathContext.join(hooksDir, fileName);
    await _fs.writeString(path, scriptBody);
    return _runner.commandStringForScriptFile(path);
  }

  String hookToml({
    required String event,
    required String command,
    int timeoutSec = 30,
  }) {
    final escaped = _escapeTomlBasicString(command);
    return '''
[[hooks.$event]]

[[hooks.$event.hooks]]
type = "command"
command = "$escaped"
timeout = $timeoutSec
'''
        .trim();
  }

  static String _escapeTomlBasicString(String value) => value
      .replaceAll('\\', r'\\')
      .replaceAll('"', r'\"');
}
