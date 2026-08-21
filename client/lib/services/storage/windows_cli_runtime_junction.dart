import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../io/filesystem.dart';

/// Per-CLI knobs for [WindowsCliRuntimeJunction].
final class WindowsCliRuntimeJunctionSpec {
  const WindowsCliRuntimeJunctionSpec({
    required this.toolId,
    required this.homeSegment,
    required this.maxPathSuffixFromHome,
    this.occupancyProbeRelativePath,
  });

  final String toolId;
  final String homeSegment;

  /// Longest relative path a CLI may append under [homeSegment] on Windows.
  final int maxPathSuffixFromHome;

  /// When migrating, skip copy if this path already exists under physical home.
  final String? occupancyProbeRelativePath;
}

/// Windows-only junction helper for isolated CLI runtime homes that would
/// exceed `MAX_PATH` under the canonical TeamPilot session tree.
///
/// Physical layout:
/// `%LOCALAPPDATA%/com.hhoa.teampilot/cli-runtime-homes/{toolId}/{hash}/{homeSegment}`
abstract final class WindowsCliRuntimeJunction {
  static const runtimeHomesDirName = 'cli-runtime-homes';
  static const junctionMarkerFileName = 'runtime-home';

  static const _windowsMaxPath = 260;

  static bool needsJunction(
    WindowsCliRuntimeJunctionSpec spec,
    String canonicalHome,
  ) {
    if (!Platform.isWindows) return false;
    final home = canonicalHome.trim();
    if (home.isEmpty) return false;
    return home.length + 1 + spec.maxPathSuffixFromHome > _windowsMaxPath;
  }

  static String? defaultLocalAppDataRoot() {
    if (!Platform.isWindows) return null;
    final local = Platform.environment['LOCALAPPDATA']?.trim() ?? '';
    if (local.isEmpty) return null;
    return p.join(local, 'com.hhoa.teampilot');
  }

  static String markerPathForCanonicalHome(
    String canonicalHome, {
    p.Context? pathContext,
  }) {
    final ctx = pathContext ?? p.context;
    return ctx.join(ctx.dirname(canonicalHome), junctionMarkerFileName);
  }

  static Future<String> resolvePhysicalHome({
    required Filesystem fs,
    required String canonicalHome,
  }) async {
    final canonical = fs.pathContext.normalize(
      fs.pathContext.absolute(canonicalHome.trim()),
    );
    final stored =
        (await fs.readString(
          markerPathForCanonicalHome(canonical, pathContext: fs.pathContext),
        ))?.trim() ??
        '';
    if (stored.isNotEmpty) {
      return fs.pathContext.normalize(stored);
    }
    return canonical;
  }

  static Future<String> ensurePhysicalHome({
    required Filesystem fs,
    required WindowsCliRuntimeJunctionSpec spec,
    required String canonicalHome,
    String? localAppDataRoot,
  }) async {
    final canonical = fs.pathContext.normalize(
      fs.pathContext.absolute(canonicalHome.trim()),
    );
    if (!needsJunction(spec, canonical)) {
      await fs.ensureDir(canonical);
      await _removeMarkerIfPresent(fs, canonical);
      return canonical;
    }

    final localRoot = (localAppDataRoot ?? defaultLocalAppDataRoot())?.trim();
    if (localRoot == null || localRoot.isEmpty) {
      await fs.ensureDir(canonical);
      return canonical;
    }

    final physical = physicalHomePath(
      spec: spec,
      localAppDataRoot: localRoot,
      canonicalHome: canonical,
      pathContext: fs.pathContext,
    );
    await fs.ensureDir(physical);
    await _migrateCanonicalDirectoryIfNeeded(
      fs: fs,
      spec: spec,
      canonicalHome: canonical,
      physicalHome: physical,
    );
    await _ensureJunction(fs: fs, linkPath: canonical, target: physical);
    await fs.atomicWrite(
      markerPathForCanonicalHome(canonical, pathContext: fs.pathContext),
      '$physical\n',
    );
    return physical;
  }

  static String physicalHomePath({
    required WindowsCliRuntimeJunctionSpec spec,
    required String localAppDataRoot,
    required String canonicalHome,
    p.Context? pathContext,
  }) {
    final ctx = pathContext ?? p.context;
    final digest = sha256.convert(utf8.encode(canonicalHome.toLowerCase()));
    final key = digest.toString().substring(0, 16);
    return ctx.join(
      localAppDataRoot,
      runtimeHomesDirName,
      spec.toolId.trim(),
      key,
      spec.homeSegment.trim(),
    );
  }

  static Future<void> removeLinkedPhysicalHome({
    required Filesystem fs,
    required WindowsCliRuntimeJunctionSpec spec,
    required String canonicalHome,
    String? localAppDataRoot,
  }) async {
    if (!Platform.isWindows) return;
    final canonical = fs.pathContext.normalize(
      fs.pathContext.absolute(canonicalHome.trim()),
    );
    final marker = markerPathForCanonicalHome(
      canonical,
      pathContext: fs.pathContext,
    );
    final stored = (await fs.readString(marker))?.trim() ?? '';
    if (stored.isNotEmpty) {
      await _removePhysicalTree(fs, stored);
    } else {
      final localRoot = (localAppDataRoot ?? defaultLocalAppDataRoot())?.trim();
      if (localRoot != null && localRoot.isNotEmpty) {
        final physical = physicalHomePath(
          spec: spec,
          localAppDataRoot: localRoot,
          canonicalHome: canonical,
          pathContext: fs.pathContext,
        );
        await _removePhysicalTree(fs, physical);
      }
    }
    await _removeMarkerIfPresent(fs, canonical);
  }

  static Future<void> removeLinkedPhysicalHomesUnder({
    required Filesystem fs,
    required String scanRoot,
  }) async {
    if (!Platform.isWindows) return;
    final stat = await fs.stat(scanRoot);
    if (!stat.exists) return;
    for (final marker in await _collectMarkerFiles(fs, scanRoot)) {
      final stored = (await fs.readString(marker))?.trim() ?? '';
      if (stored.isNotEmpty) {
        await _removePhysicalTree(fs, stored);
      }
      try {
        await fs.removeRecursive(marker);
      } on Object {
        // best effort
      }
    }
  }

  static Future<void> _removePhysicalTree(Filesystem fs, String physicalHome) {
    return () async {
      try {
        await fs.removeRecursive(physicalHome);
      } on Object {
        // best effort
      }
      try {
        await fs.removeRecursive(fs.pathContext.dirname(physicalHome));
      } on Object {
        // best effort
      }
    }();
  }

  static Future<List<String>> _collectMarkerFiles(
    Filesystem fs,
    String root,
  ) async {
    final found = <String>[];
    final stack = <String>[root];
    while (stack.isNotEmpty) {
      final dir = stack.removeLast();
      final entries = await fs.listDir(dir);
      for (final entry in entries) {
        final path = fs.pathContext.join(dir, entry.name);
        if (entry.isDirectory) {
          stack.add(path);
          continue;
        }
        if (entry.name == junctionMarkerFileName) {
          found.add(path);
        }
      }
    }
    return found;
  }

  static Future<void> _migrateCanonicalDirectoryIfNeeded({
    required Filesystem fs,
    required WindowsCliRuntimeJunctionSpec spec,
    required String canonicalHome,
    required String physicalHome,
  }) async {
    final canonicalStat = await fs.stat(canonicalHome);
    if (!canonicalStat.exists || !canonicalStat.isDirectory) return;
    if (await _isJunctionTo(fs, canonicalHome, physicalHome)) return;

    final probe = spec.occupancyProbeRelativePath?.trim() ?? '';
    if (probe.isNotEmpty) {
      final physicalProbe = fs.pathContext.join(physicalHome, probe);
      if ((await fs.stat(physicalProbe)).exists) {
        await fs.removeRecursive(canonicalHome);
        return;
      }
    }

    await fs.copyTree(source: canonicalHome, destination: physicalHome);
    await fs.removeRecursive(canonicalHome);
  }

  static Future<void> _ensureJunction({
    required Filesystem fs,
    required String linkPath,
    required String target,
  }) async {
    if (await _isJunctionTo(fs, linkPath, target)) return;
    final stat = await fs.stat(linkPath);
    if (stat.exists) {
      await fs.removeRecursive(linkPath);
    }
    final linked = await fs.createSymlink(target: target, linkPath: linkPath);
    if (!linked) {
      throw StateError('runtime home junction failed: $linkPath -> $target');
    }
  }

  static Future<bool> _isJunctionTo(
    Filesystem fs,
    String linkPath,
    String target,
  ) async {
    final stat = await fs.stat(linkPath);
    if (!stat.exists) return false;
    final normalizedTarget = fs.pathContext.normalize(
      fs.pathContext.absolute(target),
    );
    if (stat.isSymlink) {
      final existing = await fs.readSymlinkTarget(linkPath);
      if (existing == null) return false;
      return fs.pathContext.normalize(fs.pathContext.absolute(existing)) ==
          normalizedTarget;
    }
    if (Platform.isWindows && stat.isDirectory) {
      final resolved = await fs.resolveSymlink(linkPath);
      if (resolved == null) return false;
      return fs.pathContext.normalize(resolved) == normalizedTarget;
    }
    return false;
  }

  static Future<void> _removeMarkerIfPresent(
    Filesystem fs,
    String canonicalHome,
  ) async {
    final marker = markerPathForCanonicalHome(
      canonicalHome,
      pathContext: fs.pathContext,
    );
    final stat = await fs.stat(marker);
    if (stat.exists) {
      await fs.removeRecursive(marker);
    }
  }
}
