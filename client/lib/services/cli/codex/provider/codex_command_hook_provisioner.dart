import '../../../host/host_execution_environment.dart';
import '../../../host/host_script_dialect.dart';
import '../../../host/host_script_runner.dart';
import '../../../io/filesystem.dart';

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
    String? commandWindows,
    int timeoutSec = 30,
  }) {
    final escaped = _escapeTomlBasicString(command);
    final windowsLine = commandWindows == null
        ? ''
        : 'command_windows = "${_escapeTomlBasicString(commandWindows)}"\n';
    return '''
[[hooks.$event]]

[[hooks.$event.hooks]]
type = "command"
command = "$escaped"
${windowsLine}timeout = $timeoutSec
'''
        .trim();
  }

  Future<({String command, String? commandWindows})> provisionHookCommands({
    required String hooksDir,
    required String baseFileName,
    required String scriptBody,
    required String windowsScriptBody,
  }) async {
    final env = _runner.environment;
    final bashRunner = HostScriptRunner(
      HostExecutionEnvironment(
        dialect: HostScriptDialect.bash,
        isWindowsHost: env.isWindowsHost,
        storageMode: env.storageMode,
      ),
    );
    final bashProvisioner = CodexCommandHookProvisioner(
      fs: _fs,
      runner: bashRunner,
    );
    final bashCommand = await bashProvisioner.provision(
      hooksDir: hooksDir,
      baseFileName: baseFileName,
      scriptBody: scriptBody,
    );

    if (_runner.dialect != HostScriptDialect.powershell) {
      return (command: bashCommand, commandWindows: null);
    }

    final windowsCommand = await provision(
      hooksDir: hooksDir,
      baseFileName: '$baseFileName-win',
      scriptBody: windowsScriptBody,
    );
    return (command: bashCommand, commandWindows: windowsCommand);
  }

  static String _escapeTomlBasicString(String value) => value
      .replaceAll('\\', r'\\')
      .replaceAll('"', r'\"');
}
