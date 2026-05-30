import '../io/filesystem.dart';
import 'host_script_dialect.dart';
import 'host_script_runner.dart';

/// Writes a hook script under `hooks/` and returns its absolute path.
final class ScriptFileHookProvisioner {
  ScriptFileHookProvisioner({
    required Filesystem fs,
    required HostScriptRunner runner,
    required String baseFileName,
    required Future<String> Function(HostScriptDialect dialect) loadScript,
  }) : _fs = fs,
       _runner = runner,
       _baseFileName = baseFileName,
       _loadScript = loadScript;

  final Filesystem _fs;
  final HostScriptRunner _runner;
  final String _baseFileName;
  final Future<String> Function(HostScriptDialect dialect) _loadScript;

  HostScriptRunner get runner => _runner;

  String fileNameForDialect([HostScriptDialect? dialect]) =>
      _runner.hookFileName(_baseFileName);

  Future<String> provision(String memberToolDir) async {
    final dialect = _runner.dialect;
    final hooksDir = _fs.pathContext.join(memberToolDir, 'hooks');
    await _fs.ensureDir(hooksDir);
    final dest = _fs.pathContext.join(hooksDir, fileNameForDialect());
    final script = await _loadScript(dialect);
    await _fs.writeString(dest, script);
    return dest;
  }

  String commandForPath(String scriptPath) =>
      _runner.commandStringForScriptFile(scriptPath);
}
