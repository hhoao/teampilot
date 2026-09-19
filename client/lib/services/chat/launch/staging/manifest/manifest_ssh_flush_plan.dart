import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../../../io/filesystem.dart';
import 'launch_manifest.dart';
import 'manifest_ssh_overlay.dart';

enum ManifestSshEpochKind { script, tar }

class ManifestSshEpoch {
  const ManifestSshEpoch({
    required this.kind,
    this.script,
    this.gzipTar,
    this.extractCommand,
  });

  final ManifestSshEpochKind kind;
  final String? script;
  final Uint8List? gzipTar;
  final String? extractCommand;
}

/// POSIX single-quoted string for `bash -c` / `rm -rf --` paths.
String posixShellQuote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

/// mkdir/ln/rm/mv/cp plus heredoc `writeFile` (same-host and mutation epochs).
String buildMutationApplyScript(LaunchManifest manifest) {
  final buffer = StringBuffer()..writeln('set -e');
  for (final entry in manifest.entries) {
    switch (entry) {
      case ManifestEnsureDir(:final path):
        buffer.writeln('mkdir -p ${posixShellQuote(path)}');
      case ManifestWriteFile(:final path, :final content):
        final quoted = posixShellQuote(path);
        final dir = posixShellQuote(_posixDirname(path));
        final delimiter = _heredocDelimiter(content);
        buffer
          ..writeln('mkdir -p $dir')
          ..writeln("cat > $quoted <<'$delimiter'")
          ..writeln(content)
          ..writeln(delimiter);
      case ManifestSymlink(:final linkPath, :final target):
        buffer
          ..writeln('mkdir -p ${posixShellQuote(_posixDirname(linkPath))}')
          ..writeln('rm -rf -- ${posixShellQuote(linkPath)}')
          ..writeln(
            'ln -sfn -- ${posixShellQuote(target)} ${posixShellQuote(linkPath)}',
          );
      case ManifestRemoveRecursive(:final path):
        buffer.writeln('rm -rf ${posixShellQuote(path)}');
      case ManifestRename(:final from, :final to):
        buffer
          ..writeln('mkdir -p ${posixShellQuote(_posixDirname(to))}')
          ..writeln('mv ${posixShellQuote(from)} ${posixShellQuote(to)}');
      case ManifestCopyFile(:final source, :final destination):
        buffer
          ..writeln('mkdir -p ${posixShellQuote(_posixDirname(destination))}')
          ..writeln(
            'cp -f -- ${posixShellQuote(source)} ${posixShellQuote(destination)}',
          );
      case ManifestCopyTree(:final source, :final destination):
        buffer
          ..writeln('mkdir -p ${posixShellQuote(_posixDirname(destination))}')
          ..writeln('rm -rf ${posixShellQuote(destination)}')
          ..writeln('mkdir -p ${posixShellQuote(destination)}')
          ..writeln(
            'cp -R -- ${posixShellQuote('$source/.')} '
            '${posixShellQuote(destination)}',
          );
    }
  }
  return buffer.toString();
}

/// Split [manifest] into stdin script epochs and gzip-tar overlay epochs.
Future<List<ManifestSshEpoch>> buildManifestSshFlushPlan({
  required LaunchManifest manifest,
  required Filesystem sourceFs,
  required String workRoot,
  required bool sameHost,
}) async {
  if (sameHost) {
    return [
      ManifestSshEpoch(
        kind: ManifestSshEpochKind.script,
        script: buildMutationApplyScript(manifest),
      ),
    ];
  }
  final planner = _OffHomePlanner(
    manifest: manifest,
    sourceFs: sourceFs,
    workRoot: workRoot,
  );
  await planner.build();
  return planner.epochs;
}

enum _BufferKind { script, tar }

enum _MemberKind { file, dir }

final class _OverlayMember {
  const _OverlayMember(this.kind, {this.bytes});

  final _MemberKind kind;
  final List<int>? bytes;
}

final class _OffHomePlanner {
  _OffHomePlanner({
    required this.manifest,
    required this.sourceFs,
    required this.workRoot,
  }) : _script = LaunchManifest(pathContext: manifest.pathContext);

  final LaunchManifest manifest;
  final Filesystem sourceFs;
  final String workRoot;
  final epochs = <ManifestSshEpoch>[];
  final _overlay = <String, _OverlayMember>{};
  LaunchManifest _script;
  _BufferKind? _open;

  p.Context get _ctx => manifest.pathContext;

  Future<void> build() async {
    for (final entry in manifest.entries) {
      switch (entry) {
        case ManifestEnsureDir(:final path):
          _addEnsureDir(path);
        case ManifestWriteFile(:final path, :final content):
          _addWriteFile(path, content);
        case ManifestSymlink(:final linkPath, :final target):
          await _addSymlink(linkPath: linkPath, target: target);
        case ManifestCopyFile(:final source, :final destination):
          await _addCopyFile(source: source, destination: destination);
        case ManifestCopyTree(:final source, :final destination):
          await _addCopyTree(source: source, destination: destination);
        case ManifestRemoveRecursive(:final path):
          _openKind(_BufferKind.script);
          _script.removeRecursive(path);
        case ManifestRename(:final from, :final to):
          _openKind(_BufferKind.script);
          _script.rename(from: from, to: to);
      }
    }
    _flushOpen();
    _flushTar();
    _flushScript();
  }

  void _addEnsureDir(String path) {
    final rel = _relative(path);
    if (rel == null) {
      _openKind(_BufferKind.script);
      _script.ensureDir(path);
      return;
    }
    _openKind(_BufferKind.tar);
    _overlay[rel] = const _OverlayMember(_MemberKind.dir);
  }

  void _addWriteFile(String path, String content) {
    final rel = _relative(path);
    if (rel == null) {
      _openKind(_BufferKind.script);
      _script.writeFile(path, content);
      return;
    }
    _openKind(_BufferKind.tar);
    _overlay[rel] = _OverlayMember(
      _MemberKind.file,
      bytes: utf8.encode(content),
    );
  }

  Future<void> _addSymlink({
    required String linkPath,
    required String target,
  }) async {
    if (_targetWithinRoot(target: target, linkPath: linkPath)) {
      // Never emit tar symlink members: ustar truncates targets >100 bytes.
      // Mutation script already does leftover-dir `rm -rf` then `ln -sfn`.
      _openKind(_BufferKind.script);
      _script.symlink(linkPath: linkPath, target: target);
      return;
    }
    await _copyExternal(
      currentTarget: _resolveTarget(target: target, linkPath: linkPath),
      destination: linkPath,
      visited: <String>{},
    );
  }

  Future<void> _addCopyFile({
    required String source,
    required String destination,
  }) async {
    final bytes = await sourceFs.readBytes(source);
    if (bytes == null) {
      throw StateError(
        'Launch manifest copy source missing on control plane: $source',
      );
    }
    _addBytes(destination, bytes);
  }

  Future<void> _addCopyTree({
    required String source,
    required String destination,
  }) async {
    final entries = await sourceFs.listDirRecursive(source);
    if (entries.isEmpty) {
      final stat = await sourceFs.stat(source);
      if (!stat.isDirectory) {
        throw StateError(
          'Launch manifest copy tree source missing on control plane: $source',
        );
      }
      return;
    }
    for (final entry in entries) {
      if (entry.isDirectory) continue;
      await _addCopyFile(
        source: _ctx.join(source, entry.name),
        destination: _ctx.join(destination, entry.name),
      );
    }
  }

  Future<void> _copyExternal({
    required String currentTarget,
    required String destination,
    required Set<String> visited,
  }) async {
    if (!visited.add(currentTarget)) {
      throw StateError(
        'Launch manifest external symlink cycle: $currentTarget',
      );
    }
    final stat = await sourceFs.lstat(currentTarget);
    if (stat.isFile) {
      await _addCopyFile(source: currentTarget, destination: destination);
      return;
    }
    if (stat.isDirectory) {
      await _addCopyTree(source: currentTarget, destination: destination);
      return;
    }
    if (stat.isSymlink) {
      final nextTarget = await sourceFs.readSymlinkTarget(currentTarget);
      if (nextTarget != null) {
        await _copyExternal(
          currentTarget: _resolveTarget(
            target: nextTarget,
            linkPath: currentTarget,
          ),
          destination: destination,
          visited: visited,
        );
        return;
      }
    }
    throw StateError(
      'Launch manifest external symlink target missing on control plane: '
      '$currentTarget',
    );
  }

  void _addBytes(String destination, List<int> bytes) {
    final rel = _relative(destination);
    if (rel == null) {
      // Follow-up: out-of-root copy bodies go through a heredoc writeFile and
      // are not binary-safe (`String.fromCharCodes`).
      _openKind(_BufferKind.script);
      _script.writeFile(destination, String.fromCharCodes(bytes));
      return;
    }
    _openKind(_BufferKind.tar);
    _overlay[rel] = _OverlayMember(_MemberKind.file, bytes: bytes);
  }

  void _openKind(_BufferKind kind) {
    if (_open != null && _open != kind) {
      _flushOpen();
    }
    _open = kind;
  }

  void _flushOpen() {
    switch (_open) {
      case _BufferKind.tar:
        _flushTar();
      case _BufferKind.script:
        _flushScript();
      case null:
        break;
    }
    _open = null;
  }

  void _flushTar() {
    if (_overlay.isEmpty) return;
    final archive = Archive();
    for (final MapEntry(:key, :value) in _overlay.entries) {
      switch (value.kind) {
        case _MemberKind.file:
          addOverlayFile(archive, relativePath: key, bytes: value.bytes!);
        case _MemberKind.dir:
          addOverlayDir(archive, relativePath: key);
      }
    }
    epochs.add(
      ManifestSshEpoch(
        kind: ManifestSshEpochKind.tar,
        gzipTar: encodeLaunchOverlayGzip(archive),
        extractCommand: launchOverlayExtractCommand(workRoot),
      ),
    );
    _overlay.clear();
  }

  void _flushScript() {
    if (_script.entries.isEmpty) return;
    epochs.add(
      ManifestSshEpoch(
        kind: ManifestSshEpochKind.script,
        script: buildMutationApplyScript(_script),
      ),
    );
    _script = LaunchManifest(pathContext: _ctx);
  }

  String? _relative(String absolutePath) {
    final rel = manifestOverlayRelativePath(
      absolutePath: absolutePath,
      workRoot: workRoot,
      pathContext: _ctx,
    );
    if (rel == null || rel == '.') return null;
    return rel;
  }

  bool _targetWithinRoot({required String target, required String linkPath}) {
    final root = _ctx.normalize(_ctx.absolute(workRoot));
    final normalized = _ctx.normalize(
      _ctx.absolute(_resolveTarget(target: target, linkPath: linkPath)),
    );
    return normalized == root || _ctx.isWithin(root, normalized);
  }

  String _resolveTarget({required String target, required String linkPath}) {
    final effective = _ctx.isAbsolute(target)
        ? target
        : _ctx.join(_ctx.dirname(linkPath), target);
    return _ctx.normalize(effective);
  }
}

String _posixDirname(String path) {
  final index = path.lastIndexOf('/');
  return index <= 0 ? '/' : path.substring(0, index);
}

String _heredocDelimiter(String content) {
  var delimiter = '__TP_MANIFEST_${content.hashCode.abs()}__';
  var salt = 0;
  while (content.contains(delimiter)) {
    delimiter = '__TP_MANIFEST_${content.hashCode.abs()}_${salt}__';
    salt++;
  }
  return delimiter;
}
