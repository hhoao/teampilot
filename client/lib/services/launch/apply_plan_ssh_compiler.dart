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

  final script = _compileMutationScript(plan.ops);
  final members = _compactedBlobMembers(plan);
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

String? _compileMutationScript(List<ApplyOp> ops) {
  final buffer = StringBuffer();
  for (final op in ops) {
    switch (op) {
      case ApplyEnsureDir(:final path):
        buffer.writeln('mkdir -p ${posixShellQuote(path)}');
      case ApplyRemove(:final path):
        buffer.writeln('rm -rf ${posixShellQuote(path)}');
      case ApplyRename(:final from, :final to):
        buffer
          ..writeln('mkdir -p ${posixShellQuote(_posixDirname(to))}')
          ..writeln('mv ${posixShellQuote(from)} ${posixShellQuote(to)}');
      case ApplySymlink(:final linkPath, :final target):
        buffer
          ..writeln('mkdir -p ${posixShellQuote(_posixDirname(linkPath))}')
          ..writeln('rm -rf -- ${posixShellQuote(linkPath)}')
          ..writeln(
            'ln -sfn -- ${posixShellQuote(target)} '
            '${posixShellQuote(linkPath)}',
          );
      case ApplyWriteInline(:final path, :final content):
        final delimiter = _heredocDelimiter(content);
        buffer
          ..writeln('mkdir -p ${posixShellQuote(_posixDirname(path))}')
          ..writeln("cat > ${posixShellQuote(path)} <<'$delimiter'")
          ..writeln(content)
          ..writeln(delimiter);
      case ApplyWriteBlob() || ApplyTree():
        break;
    }
  }
  if (buffer.isEmpty) return null;
  return 'set -e\n$buffer';
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
      final op = plan.ops[i];
      if (op is! ApplyRemove) continue;
      final removePath = p.posix.normalize(op.path);
      final destination = p.posix.normalize(member.destination);
      if (destination == removePath ||
          p.posix.isWithin(removePath, destination)) {
        return true;
      }
    }
    return false;
  });
  return lastWrites;
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

String _heredocDelimiter(String content) {
  var delimiter = '__TP_MANIFEST_${content.hashCode.abs()}__';
  var salt = 0;
  while (content.contains(delimiter)) {
    delimiter = '__TP_MANIFEST_${content.hashCode.abs()}_${salt}__';
    salt++;
  }
  return delimiter;
}
