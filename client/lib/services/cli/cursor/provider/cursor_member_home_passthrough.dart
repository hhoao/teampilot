import 'dart:io';

import '../../../io/filesystem.dart';
import '../../../io/local_filesystem.dart';
import 'cursor_home_layout.dart';

/// Runs a POSIX mirror script (local `/bin/sh` or a test double).
typedef CursorHomeLocalScriptRunner = Future<void> Function(String script);

/// Mirrors the work-plane user's real `$HOME` into a cursor member fake HOME.
///
/// Cursor reads plugins/MCP/skills from `$HOME/.cursor`, so the PTY still uses
/// a fake [memberHomeRoot]. Tooling invoked by the agent (rustup, pub, …) also
/// resolves paths under `$HOME`; symlinking everything except the isolated
/// cursor dirs sends those writes back to the real home without a toolchain
/// env whitelist.
///
/// Prefer [buildRemoteMirrorScript] on SSH/Termux work planes (one remote
/// `find`+`ln` round-trip) instead of [mirror] over SFTP. Local POSIX uses
/// in-process `dart:io` symlinks (or `localScriptRunner` in tests) so a large
/// `$HOME` does not fork `ln`/`readlink` per entry on the UI isolate.
///
/// Before linking, member-home passthrough entries are reconciled:
/// - entity orphans move to the real home path via [Filesystem.rename] when the
///   destination does not exist yet (falling back to delete + symlink);
/// - stale or mis-pointing symlinks are removed.
final class CursorMemberHomePassthrough {
  CursorMemberHomePassthrough({
    required Filesystem fs,
    CursorHomeLayout? layout,
    CursorHomeLocalScriptRunner? localScriptRunner,
  }) : _fs = fs,
       _layout = layout ?? CursorHomeLayout(pathContext: fs.pathContext),
       _localScriptRunner = localScriptRunner;

  final Filesystem _fs;
  final CursorHomeLayout _layout;
  final CursorHomeLocalScriptRunner? _localScriptRunner;

  /// POSIX `sh` script that performs the same mirror as [mirror] in one remote
  /// exec (list + link). Empty when homes are missing or identical.
  static String buildRemoteMirrorScript({
    required String realHomeRoot,
    required String memberHomeRoot,
  }) {
    final realHome = realHomeRoot.trim();
    final memberHome = memberHomeRoot.trim();
    if (realHome.isEmpty || memberHome.isEmpty || realHome == memberHome) {
      return '';
    }

    final real = _shellQuote(realHome);
    final member = _shellQuote(memberHome);
    final cursor = _shellQuote(CursorHomeLayout.cursorDirName);
    final config = _shellQuote(CursorHomeLayout.configDirName);
    final configCursor = _shellQuote(CursorHomeLayout.configCursorDirName);

    // Portable sh: one find pass on real home, reconcile+link helpers inline.
    // Skips `.cursor` entirely; `.config/cursor` stays an isolated real dir.
    return '''
set -e
real_home=$real
member_home=$member
mkdir -p -- "\$member_home/.config/cursor"

link_passthrough() {
  src=\$1
  dst=\$2
  if [ -L "\$dst" ]; then
    cur=\$(readlink -- "\$dst" 2>/dev/null || readlink "\$dst" 2>/dev/null || true)
    if [ "\$cur" = "\$src" ]; then
      return 0
    fi
    rm -rf -- "\$dst"
  elif [ -e "\$dst" ]; then
    if [ -e "\$src" ]; then
      rm -rf -- "\$dst"
    else
      mkdir -p -- "\$(dirname -- "\$src")"
      if ! mv -- "\$dst" "\$src" 2>/dev/null; then
        rm -rf -- "\$dst"
      fi
    fi
  fi
  ln -sfn -- "\$src" "\$dst"
}

# Reconcile existing member-home passthrough entries.
if [ -d "\$member_home" ]; then
  find "\$member_home" -mindepth 1 -maxdepth 1 ! -name $cursor -print 2>/dev/null | while IFS= read -r path; do
    [ -n "\$path" ] || continue
    base=\$(basename -- "\$path")
    if [ "\$base" = $config ]; then
      if [ -d "\$path" ]; then
        find "\$path" -mindepth 1 -maxdepth 1 ! -name $configCursor -print 2>/dev/null | while IFS= read -r cpath; do
          [ -n "\$cpath" ] || continue
          cbase=\$(basename -- "\$cpath")
          link_passthrough "\$real_home/.config/\$cbase" "\$cpath"
        done
      fi
      continue
    fi
    link_passthrough "\$real_home/\$base" "\$path"
  done
fi

# Mirror from real home.
if [ -d "\$real_home" ]; then
  find "\$real_home" -mindepth 1 -maxdepth 1 ! -name $cursor -print 2>/dev/null | while IFS= read -r path; do
    [ -n "\$path" ] || continue
    base=\$(basename -- "\$path")
    if [ "\$base" = $config ]; then
      mkdir -p -- "\$member_home/.config/cursor"
      if [ -d "\$path" ]; then
        find "\$path" -mindepth 1 -maxdepth 1 ! -name $configCursor -print 2>/dev/null | while IFS= read -r cpath; do
          [ -n "\$cpath" ] || continue
          cbase=\$(basename -- "\$cpath")
          link_passthrough "\$cpath" "\$member_home/.config/\$cbase"
        done
      fi
      continue
    fi
    link_passthrough "\$path" "\$member_home/\$base"
  done
fi
''';
  }

  static String _shellQuote(String value) =>
      "'${value.replaceAll("'", "'\"'\"'")}'";

  Future<bool> _tryRunMirrorScript(String script) async {
    final runner = _localScriptRunner;
    if (runner == null) return false;
    try {
      await runner(script);
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> mirror({
    required String realHomeRoot,
    required String memberHomeRoot,
  }) async {
    final ctx = _fs.pathContext;
    final realHome = ctx.normalize(ctx.absolute(realHomeRoot.trim()));
    final memberHome = ctx.normalize(ctx.absolute(memberHomeRoot.trim()));
    if (realHome.isEmpty || memberHome.isEmpty || realHome == memberHome) {
      return;
    }

    if (_localScriptRunner != null) {
      final script = buildRemoteMirrorScript(
        realHomeRoot: realHomeRoot,
        memberHomeRoot: memberHomeRoot,
      );
      if (script.isNotEmpty && await _tryRunMirrorScript(script)) {
        return;
      }
    } else if (!Platform.isWindows && _fs is LocalFilesystem) {
      _mirrorViaDartIo(realHome: realHome, memberHome: memberHome);
      return;
    }

    await _fs.ensureDir(memberHome);
    await _fs.ensureDir(_layout.configCursorDir(memberHome));

    await _reconcileMemberHome(
      realHomeRoot: realHome,
      memberHomeRoot: memberHome,
    );

    final realStat = await _fs.stat(realHome);
    if (!realStat.exists || !realStat.isDirectory) return;

    for (final entry in await _fs.listDir(realHome)) {
      final name = entry.name.trim();
      if (name.isEmpty || name == CursorHomeLayout.cursorDirName) continue;
      if (name == CursorHomeLayout.configDirName) {
        await _mirrorConfigChildren(
          realHomeRoot: realHome,
          memberHomeRoot: memberHome,
        );
        continue;
      }
      await _linkPassthrough(
        source: ctx.join(realHome, name),
        linkPath: ctx.join(memberHome, name),
      );
    }
  }

  void _mirrorViaDartIo({
    required String realHome,
    required String memberHome,
  }) {
    Directory(memberHome).createSync(recursive: true);
    Directory(_layout.configCursorDir(memberHome)).createSync(recursive: true);

    _reconcileChildrenIo(
      realDir: realHome,
      memberDir: memberHome,
      skip: {CursorHomeLayout.cursorDirName},
      nestedConfig: true,
    );
    _linkChildrenIo(
      realDir: realHome,
      memberDir: memberHome,
      skip: {CursorHomeLayout.cursorDirName},
      nestedConfig: true,
    );
  }

  void _reconcileChildrenIo({
    required String realDir,
    required String memberDir,
    required Set<String> skip,
    required bool nestedConfig,
  }) {
    final member = Directory(memberDir);
    if (!member.existsSync()) return;
    final ctx = _fs.pathContext;
    for (final entity in member.listSync(followLinks: false)) {
      final name = ctx.basename(entity.path);
      if (name.isEmpty || skip.contains(name)) continue;
      if (nestedConfig && name == CursorHomeLayout.configDirName) {
        _reconcileChildrenIo(
          realDir: ctx.join(realDir, name),
          memberDir: ctx.join(memberDir, name),
          skip: {CursorHomeLayout.configCursorDirName},
          nestedConfig: false,
        );
        continue;
      }
      _reconcileEntryIo(
        realSource: ctx.join(realDir, name),
        memberLink: ctx.join(memberDir, name),
      );
    }
  }

  void _linkChildrenIo({
    required String realDir,
    required String memberDir,
    required Set<String> skip,
    required bool nestedConfig,
  }) {
    final real = Directory(realDir);
    if (!real.existsSync()) return;
    Directory(memberDir).createSync(recursive: true);
    if (nestedConfig) {
      Directory(_layout.configCursorDir(memberDir)).createSync(recursive: true);
    }
    final ctx = _fs.pathContext;
    for (final entity in real.listSync(followLinks: false)) {
      final name = ctx.basename(entity.path);
      if (name.isEmpty || skip.contains(name)) continue;
      if (nestedConfig && name == CursorHomeLayout.configDirName) {
        _linkChildrenIo(
          realDir: ctx.join(realDir, name),
          memberDir: ctx.join(memberDir, name),
          skip: {CursorHomeLayout.configCursorDirName},
          nestedConfig: false,
        );
        continue;
      }
      _linkEntryIo(
        source: ctx.join(realDir, name),
        linkPath: ctx.join(memberDir, name),
      );
    }
  }

  void _reconcileEntryIo({
    required String realSource,
    required String memberLink,
  }) {
    final type = FileSystemEntity.typeSync(memberLink, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;

    if (type == FileSystemEntityType.link) {
      if (_ioLinkPointsTo(source: realSource, linkPath: memberLink)) return;
      _deleteIo(memberLink);
      return;
    }

    if (_ioExists(realSource)) {
      _deleteIo(memberLink);
    } else if (!_tryPromoteIo(
      memberEntity: memberLink,
      realDestination: realSource,
    )) {
      _deleteIo(memberLink);
    }
    _linkEntryIo(source: realSource, linkPath: memberLink);
  }

  bool _tryPromoteIo({
    required String memberEntity,
    required String realDestination,
  }) {
    if (_ioExists(realDestination)) return false;
    try {
      final parent = _fs.pathContext.dirname(realDestination);
      if (parent.isNotEmpty) {
        Directory(parent).createSync(recursive: true);
      }
      switch (FileSystemEntity.typeSync(memberEntity, followLinks: false)) {
        case FileSystemEntityType.directory:
          Directory(memberEntity).renameSync(realDestination);
        case FileSystemEntityType.link:
          Link(memberEntity).renameSync(realDestination);
        default:
          File(memberEntity).renameSync(realDestination);
      }
    } on Object {
      return false;
    }
    return _ioExists(realDestination);
  }

  void _linkEntryIo({required String source, required String linkPath}) {
    if (_ioLinkPointsTo(source: source, linkPath: linkPath)) return;
    if (FileSystemEntity.typeSync(linkPath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      _deleteIo(linkPath);
    }
    Directory(_fs.pathContext.dirname(linkPath)).createSync(recursive: true);
    Link(linkPath).createSync(source);
  }

  bool _ioExists(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  bool _ioLinkPointsTo({required String source, required String linkPath}) {
    if (FileSystemEntity.typeSync(linkPath, followLinks: false) !=
        FileSystemEntityType.link) {
      return false;
    }
    final ctx = _fs.pathContext;
    try {
      return ctx.normalize(ctx.absolute(Link(linkPath).targetSync())) ==
          ctx.normalize(ctx.absolute(source));
    } on FileSystemException {
      return false;
    }
  }

  void _deleteIo(String path) {
    switch (FileSystemEntity.typeSync(path, followLinks: false)) {
      case FileSystemEntityType.link:
        Link(path).deleteSync();
      case FileSystemEntityType.directory:
        Directory(path).deleteSync(recursive: true);
      case FileSystemEntityType.file:
        File(path).deleteSync();
      default:
        break;
    }
  }

  Future<void> _reconcileMemberHome({
    required String realHomeRoot,
    required String memberHomeRoot,
  }) async {
    final ctx = _fs.pathContext;
    final memberStat = await _fs.stat(memberHomeRoot);
    if (!memberStat.exists || !memberStat.isDirectory) return;

    for (final entry in await _fs.listDir(memberHomeRoot)) {
      final name = entry.name.trim();
      if (name.isEmpty || name == CursorHomeLayout.cursorDirName) continue;
      if (name == CursorHomeLayout.configDirName) {
        await _reconcileConfigChildren(
          realHomeRoot: realHomeRoot,
          memberHomeRoot: memberHomeRoot,
        );
        continue;
      }
      await _reconcilePassthroughEntry(
        realSource: ctx.join(realHomeRoot, name),
        memberLink: ctx.join(memberHomeRoot, name),
      );
    }
  }

  Future<void> _reconcileConfigChildren({
    required String realHomeRoot,
    required String memberHomeRoot,
  }) async {
    final ctx = _fs.pathContext;
    final memberConfig = ctx.join(
      memberHomeRoot,
      CursorHomeLayout.configDirName,
    );
    final memberConfigStat = await _fs.stat(memberConfig);
    if (!memberConfigStat.exists) return;

    final realConfig = ctx.join(realHomeRoot, CursorHomeLayout.configDirName);
    for (final entry in await _fs.listDir(memberConfig)) {
      final name = entry.name.trim();
      if (name.isEmpty || name == CursorHomeLayout.configCursorDirName) {
        continue;
      }
      await _reconcilePassthroughEntry(
        realSource: ctx.join(realConfig, name),
        memberLink: ctx.join(memberConfig, name),
      );
    }
  }

  Future<void> _mirrorConfigChildren({
    required String realHomeRoot,
    required String memberHomeRoot,
  }) async {
    final ctx = _fs.pathContext;
    final realConfig = ctx.join(realHomeRoot, CursorHomeLayout.configDirName);
    final memberConfig = ctx.join(
      memberHomeRoot,
      CursorHomeLayout.configDirName,
    );

    await _fs.ensureDir(_layout.configCursorDir(memberHomeRoot));

    final realStat = await _fs.stat(realConfig);
    if (!realStat.exists) return;

    await _fs.ensureDir(memberConfig);
    for (final entry in await _fs.listDir(realConfig)) {
      final name = entry.name.trim();
      if (name.isEmpty || name == CursorHomeLayout.configCursorDirName) {
        continue;
      }
      await _linkPassthrough(
        source: ctx.join(realConfig, name),
        linkPath: ctx.join(memberConfig, name),
      );
    }
  }

  Future<void> _reconcilePassthroughEntry({
    required String realSource,
    required String memberLink,
  }) async {
    final linkStat = await _fs.stat(memberLink);
    if (!linkStat.exists) return;

    if (linkStat.isSymlink) {
      if (await _linkAlreadyPointsTo(source: realSource, linkPath: memberLink)) {
        return;
      }
      await _fs.removeRecursive(memberLink);
      return;
    }

    final sourceExists = await _pathExists(realSource);
    if (sourceExists) {
      await _fs.removeRecursive(memberLink);
    } else if (!await _tryPromoteEntityToRealHome(
      memberEntity: memberLink,
      realDestination: realSource,
    )) {
      await _fs.removeRecursive(memberLink);
    }

    await _fs.createSymlink(target: realSource, linkPath: memberLink);
  }

  Future<bool> _tryPromoteEntityToRealHome({
    required String memberEntity,
    required String realDestination,
  }) async {
    if (await _pathExists(realDestination)) return false;

    try {
      final parent = _fs.pathContext.dirname(realDestination);
      if (parent.isNotEmpty) {
        await _fs.ensureDir(parent);
      }
      await _fs.rename(memberEntity, realDestination);
    } catch (_) {
      return false;
    }

    return await _pathExists(realDestination);
  }

  Future<void> _linkPassthrough({
    required String source,
    required String linkPath,
  }) async {
    if (await _linkAlreadyPointsTo(source: source, linkPath: linkPath)) {
      return;
    }

    final linkStat = await _fs.stat(linkPath);
    if (linkStat.exists) {
      await _fs.removeRecursive(linkPath);
    }
    await _fs.createSymlink(target: source, linkPath: linkPath);
  }

  Future<bool> _pathExists(String path) async {
    final stat = await _fs.stat(path);
    return stat.exists;
  }

  Future<bool> _linkAlreadyPointsTo({
    required String source,
    required String linkPath,
  }) async {
    final ctx = _fs.pathContext;
    final linkStat = await _fs.stat(linkPath);
    if (!linkStat.exists) return false;

    final normalizedSource = ctx.normalize(ctx.absolute(source));
    if (linkStat.isSymlink) {
      final linkTarget = await _fs.readSymlinkTarget(linkPath);
      if (linkTarget == null) return false;
      return ctx.normalize(ctx.absolute(linkTarget)) == normalizedSource;
    }

    final resolved = await _fs.resolveSymlink(linkPath);
    if (resolved == null) return false;
    return ctx.normalize(resolved) == normalizedSource;
  }
}
