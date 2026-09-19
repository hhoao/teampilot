import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'apply_plan.dart';
import 'blob_store.dart';
import 'manifest_ssh_flush_plan.dart';
import 'manifest_ssh_overlay.dart';

final class ApplyPlanSshPayload {
  const ApplyPlanSshPayload({this.script, this.gzipTar, this.extractCommand});

  final String? script;
  final Uint8List? gzipTar;
  final String? extractCommand;
}

Future<ApplyPlanSshPayload> compileApplyPlanForSsh({
  required ApplyPlan plan,
  required BlobStore blobs,
}) async {
  if (plan.protocolVersion != applyPlanProtocolVersion) {
    throw StateError('unsupported protocolVersion');
  }

  final members = _compactedBlobMembers(plan);
  final script = _compileMutationScript(plan.ops, members.values);
  if (members.isEmpty) {
    return ApplyPlanSshPayload(script: script);
  }

  final archive = Archive();
  for (final member in members.values) {
    addOverlayFile(
      archive,
      relativePath: member.relativePath,
      bytes: await blobs.open(member.sha256),
    );
  }
  return ApplyPlanSshPayload(
    script: script,
    gzipTar: encodeLaunchOverlayGzip(archive),
    extractCommand: launchOverlayExtractCommand(plan.workRoot),
  );
}

String? _compileMutationScript(
  List<ApplyOp> ops,
  Iterable<_BlobMember> blobMembers,
) {
  final buffer = StringBuffer();
  for (var opIndex = 0; opIndex < ops.length; opIndex++) {
    final op = ops[opIndex];
    switch (op) {
      case ApplyEnsureDir(:final path):
        _writeEnsureDir(buffer, path);
      case ApplyRemove(:final path):
        buffer.writeln('rm -rf ${posixShellQuote(path)}');
      case ApplyRename(:final from, :final to):
        _writeEnsureDir(buffer, _posixDirname(to));
        buffer.writeln('mv ${posixShellQuote(from)} ${posixShellQuote(to)}');
      case ApplySymlink(:final linkPath, :final target):
        _writeEnsureDir(buffer, _posixDirname(linkPath));
        buffer
          ..writeln('rm -rf -- ${posixShellQuote(linkPath)}')
          ..writeln(
            'ln -sfn -- ${posixShellQuote(target)} '
            '${posixShellQuote(linkPath)}',
          );
      case ApplyWriteInline(:final path, :final content):
        final normalizedPath = p.posix.normalize(path);
        final supersededByBlob = blobMembers.any(
          (member) =>
              member.opIndex > opIndex &&
              p.posix.normalize(member.destination) == normalizedPath,
        );
        if (supersededByBlob) break;
        final delimiter = _heredocDelimiter(content);
        _writeEnsureDir(buffer, _posixDirname(path));
        buffer
          ..writeln("cat > ${posixShellQuote(path)} <<'$delimiter'")
          ..writeln(content)
          ..writeln(delimiter);
      case ApplyWriteBlob() || ApplyTree():
        break;
    }
  }
  if (buffer.isEmpty) return null;
  return 'set -e\n$_ensureDirFn$buffer';
}

Map<String, _BlobMember> _compactedBlobMembers(ApplyPlan plan) {
  final candidates = <_BlobMember>[];
  for (var opIndex = 0; opIndex < plan.ops.length; opIndex++) {
    final op = plan.ops[opIndex];
    switch (op) {
      case ApplyWriteBlob(:final path, :final sha256):
        candidates.add(
          _blobMember(
            plan: plan,
            destination: path,
            sha256: sha256,
            opIndex: opIndex,
          ),
        );
      case ApplyTree(:final dest, :final entries):
        for (final entry in entries) {
          candidates.add(
            _blobMember(
              plan: plan,
              destination: p.posix.join(dest, entry.rel),
              sha256: entry.sha256,
              opIndex: opIndex,
            ),
          );
        }
      case ApplyEnsureDir() ||
          ApplyRemove() ||
          ApplyRename() ||
          ApplySymlink() ||
          ApplyWriteInline():
        break;
    }
  }

  final lastWrites = <String, _BlobMember>{};
  for (final candidate in candidates) {
    lastWrites[candidate.relativePath] = candidate;
  }
  lastWrites.removeWhere((_, member) {
    for (var i = member.opIndex + 1; i < plan.ops.length; i++) {
      if (_mutationShadowsDestination(plan.ops[i], member.destination)) {
        return true;
      }
    }
    return false;
  });
  return lastWrites;
}

bool _mutationShadowsDestination(ApplyOp op, String destination) {
  final normalizedDestination = p.posix.normalize(destination);
  bool atOrAbove(String path) {
    final normalizedPath = p.posix.normalize(path);
    return normalizedDestination == normalizedPath ||
        p.posix.isWithin(normalizedPath, normalizedDestination);
  }

  return switch (op) {
    ApplyRemove(:final path) => atOrAbove(path),
    ApplyRename(:final from, :final to) => atOrAbove(from) || atOrAbove(to),
    ApplySymlink(:final linkPath) => atOrAbove(linkPath),
    ApplyWriteInline(:final path) =>
      normalizedDestination == p.posix.normalize(path),
    ApplyEnsureDir() || ApplyWriteBlob() || ApplyTree() => false,
  };
}

_BlobMember _blobMember({
  required ApplyPlan plan,
  required String destination,
  required String sha256,
  required int opIndex,
}) {
  final relativePath = manifestOverlayRelativePath(
    absolutePath: destination,
    workRoot: plan.workRoot,
    pathContext: p.posix,
  );
  if (relativePath == null || relativePath == '.') {
    throw StateError('overlay path is outside workRoot: $destination');
  }
  return _BlobMember(
    destination: destination,
    relativePath: relativePath,
    sha256: sha256,
    opIndex: opIndex,
  );
}

final class _BlobMember {
  const _BlobMember({
    required this.destination,
    required this.relativePath,
    required this.sha256,
    required this.opIndex,
  });

  final String destination;
  final String relativePath;
  final String sha256;
  final int opIndex;
}

String _posixDirname(String path) {
  final index = path.lastIndexOf('/');
  return index <= 0 ? '/' : path.substring(0, index);
}

/// Match local ensureDir: a directory or symlink (including a dangling
/// marketplace link) is already present. Walk components so `mkdir` never
/// runs `mkdir -p` through a dangling ancestor (GNU mkdir: File exists).
/// `[ -d ]` follows live directory links so children are still created in
/// the target; `[ -L ]` after that is only the dangling / non-dir case.
const _ensureDirFn = r'''
_tp_ensure_dir() {
  q=$1
  if [ -d "$q" ]; then
    return 0
  fi
  if [ -L "$q" ]; then
    return 0
  fi
  accum=
  case $q in
    /*) accum=/ ;;
  esac
  rest=$q
  case $rest in
    /*) rest=${rest#/} ;;
  esac
  while [ -n "$rest" ]; do
    part=${rest%%/*}
    if [ "$part" = "$rest" ]; then
      rest=
    else
      rest=${rest#*/}
    fi
    [ -z "$part" ] && continue
    if [ "$accum" = / ]; then
      accum="/$part"
    elif [ -n "$accum" ]; then
      accum="$accum/$part"
    else
      accum=$part
    fi
    if [ -d "$accum" ]; then
      continue
    fi
    if [ -L "$accum" ]; then
      return 0
    fi
    mkdir "$accum" || return 1
  done
}
''';

void _writeEnsureDir(StringBuffer buffer, String path) {
  buffer.writeln('_tp_ensure_dir ${posixShellQuote(path)}');
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
