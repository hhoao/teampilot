import 'io/filesystem.dart';

/// Deploys the RTK Claude hook script into a member tool config directory.
class RtkHookProvisioner {
  RtkHookProvisioner({
    required Filesystem fs,
    required Future<String> Function() loadHookScript,
  }) : _fs = fs,
       _loadHookScript = loadHookScript;

  final Filesystem _fs;
  final Future<String> Function() _loadHookScript;

  static const hookFileName = 'rtk-rewrite.sh';

  /// Writes `hooks/rtk-rewrite.sh` and returns its absolute path.
  Future<String> provisionMemberToolDir(String memberToolDir) async {
    final hooksDir = _fs.pathContext.join(memberToolDir, 'hooks');
    await _fs.ensureDir(hooksDir);
    final dest = _fs.pathContext.join(hooksDir, hookFileName);
    final script = await _loadHookScript();
    await _fs.writeString(dest, script);
    return dest;
  }

  String hookCommandForPath(String scriptPath) {
    final escaped = scriptPath.replaceAll('"', r'\"');
    return 'bash "$escaped"';
  }
}
