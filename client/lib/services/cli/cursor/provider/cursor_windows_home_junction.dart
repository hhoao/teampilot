import '../../../io/filesystem.dart';
import '../../../storage/windows_cli_runtime_junction.dart';
import 'cursor_home_layout.dart';
import 'cursor_session_config_dir.dart';

/// Cursor-specific junction wrapper over [WindowsCliRuntimeJunction].
abstract final class CursorWindowsHomeJunction {
  static const _spec = WindowsCliRuntimeJunctionSpec(
    toolId: 'cursor',
    homeSegment: CursorSessionConfigDir.homeSegment,
    maxPathSuffixFromHome: 134,
    occupancyProbeRelativePath: CursorHomeLayout.cursorDirName,
  );

  static bool needsJunction(String canonicalHome) =>
      WindowsCliRuntimeJunction.needsJunction(_spec, canonicalHome);

  static String? defaultLocalAppDataRoot() =>
      WindowsCliRuntimeJunction.defaultLocalAppDataRoot();

  static String markerPathForCanonicalHome(String canonicalHome) =>
      WindowsCliRuntimeJunction.markerPathForCanonicalHome(canonicalHome);

  static Future<String> resolveAgentHome({
    required Filesystem fs,
    required String canonicalHome,
  }) =>
      WindowsCliRuntimeJunction.resolvePhysicalHome(
        fs: fs,
        canonicalHome: canonicalHome,
      );

  static Future<String?> resolveCursorConfigDir({
    required Filesystem fs,
    required Map<String, String> env,
  }) async {
    final path = fs.pathContext;
    final explicit = env['CURSOR_CONFIG_DIR']?.trim() ?? '';
    final home = env['HOME']?.trim() ?? '';

    late final String canonicalHome;
    late final String fallbackConfigDir;
    if (explicit.isNotEmpty) {
      fallbackConfigDir = path.normalize(path.absolute(explicit));
      canonicalHome = path.dirname(fallbackConfigDir);
    } else if (home.isNotEmpty) {
      canonicalHome = path.normalize(path.absolute(home));
      fallbackConfigDir = path.join(
        canonicalHome,
        CursorHomeLayout.cursorDirName,
      );
    } else {
      return null;
    }

    final stored =
        (await fs.readString(
          WindowsCliRuntimeJunction.markerPathForCanonicalHome(canonicalHome),
        ))?.trim() ??
        '';
    if (stored.isEmpty) return fallbackConfigDir;

    final agentHome = path.normalize(stored);
    return path.join(agentHome, CursorHomeLayout.cursorDirName);
  }

  static Future<String> ensureAgentHome({
    required Filesystem fs,
    required String canonicalHome,
    String? localAppDataRoot,
  }) =>
      WindowsCliRuntimeJunction.ensurePhysicalHome(
        fs: fs,
        spec: _spec,
        canonicalHome: canonicalHome,
        localAppDataRoot: localAppDataRoot,
      );

  static String physicalHomePath({
    required String localAppDataRoot,
    required String canonicalHome,
  }) =>
      WindowsCliRuntimeJunction.physicalHomePath(
        spec: _spec,
        localAppDataRoot: localAppDataRoot,
        canonicalHome: canonicalHome,
      );

  static Future<void> removeLinkedPhysicalHome({
    required Filesystem fs,
    required String canonicalHome,
    String? localAppDataRoot,
  }) =>
      WindowsCliRuntimeJunction.removeLinkedPhysicalHome(
        fs: fs,
        spec: _spec,
        canonicalHome: canonicalHome,
        localAppDataRoot: localAppDataRoot,
      );

  static Future<void> removeLinkedPhysicalHomesUnder({
    required Filesystem fs,
    required String scanRoot,
  }) =>
      WindowsCliRuntimeJunction.removeLinkedPhysicalHomesUnder(
        fs: fs,
        scanRoot: scanRoot,
      );
}
