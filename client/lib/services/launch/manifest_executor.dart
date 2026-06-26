import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/ssh_profile.dart';
import '../../utils/logger.dart';
import '../io/filesystem.dart';
import '../ssh/ssh_client_factory.dart';
import '../ssh/ssh_run_result.dart';
import 'launch_manifest.dart';

/// Applies a staged [LaunchManifest] in one batch (local disk or SSH script).
class ManifestExecutor {
  const ManifestExecutor({
    this.sshClientFactory,
    this.profileById,
  });

  final SshClientFactory? sshClientFactory;
  final SshProfile? Function(String profileId)? profileById;

  Future<void> flush({
    required LaunchManifest manifest,
    required Filesystem targetFs,
    required Filesystem sourceFs,
    String? sshProfileId,
  }) async {
    if (sshProfileId != null &&
        sshProfileId.isNotEmpty &&
        sshClientFactory != null &&
        profileById != null) {
      final profile = profileById!(sshProfileId);
      if (profile != null) {
        final expanded = await _expandCopies(manifest, sourceFs);
        await _flushViaSsh(profile: profile, manifest: expanded);
        return;
      }
    }
    await _flushLocal(
      manifest: manifest,
      targetFs: targetFs,
      sourceFs: sourceFs,
    );
  }

  Future<void> _flushLocal({
    required LaunchManifest manifest,
    required Filesystem targetFs,
    required Filesystem sourceFs,
  }) async {
    final applied = identical(sourceFs, targetFs)
        ? manifest
        : await _expandCopies(manifest, sourceFs);
    for (final entry in applied.entries) {
      switch (entry) {
        case ManifestEnsureDir(:final path):
          await targetFs.ensureDir(path);
        case ManifestWriteFile(:final path, :final content):
          await targetFs.atomicWrite(path, content);
        case ManifestSymlink(:final linkPath, :final target):
          await targetFs.createSymlink(target: target, linkPath: linkPath);
        case ManifestCopyFile(:final source, :final destination):
          await targetFs.copyFile(source, destination);
        case ManifestCopyTree(:final source, :final destination):
          await targetFs.copyTree(source: source, destination: destination);
        case ManifestRemoveRecursive(:final path):
          await targetFs.removeRecursive(path);
        case ManifestRename(:final from, :final to):
          await targetFs.rename(from, to);
      }
    }
  }

  Future<void> _flushViaSsh({
    required SshProfile profile,
    required LaunchManifest manifest,
  }) async {
    final script = _buildApplyScript(manifest);
    appLogger.d(
      '[session-launch] manifest flush via ssh ops=${manifest.entries.length}',
    );
    final client = await sshClientFactory!.clientForStorage(profile);
    final result = await client.runWithResult(script, stderr: true);
    if (sshRunFailed(result)) {
      final stderr = utf8.decode(result.stderr, allowMalformed: true);
      throw StateError(
        'Failed to apply launch manifest on ${profile.host}: $stderr',
      );
    }
  }

  /// Expands copy ops into concrete file writes for SSH (sources read on control plane).
  Future<LaunchManifest> _expandCopies(
    LaunchManifest manifest,
    Filesystem sourceFs,
  ) async {
    final out = LaunchManifest(pathContext: manifest.pathContext);
    for (final entry in manifest.entries) {
      switch (entry) {
        case ManifestEnsureDir(:final path):
          out.ensureDir(path);
        case ManifestWriteFile(:final path, :final content):
          out.writeFile(path, content);
        case ManifestSymlink(:final linkPath, :final target):
          out.symlink(linkPath: linkPath, target: target);
        case ManifestRemoveRecursive(:final path):
          out.removeRecursive(path);
        case ManifestRename(:final from, :final to):
          out.rename(from: from, to: to);
        case ManifestCopyFile(:final source, :final destination):
          await _expandCopyFile(
            sourceFs: sourceFs,
            source: source,
            destination: destination,
            manifest: out,
          );
        case ManifestCopyTree(:final source, :final destination):
          await _expandCopyTree(
            sourceFs: sourceFs,
            source: source,
            destination: destination,
            manifest: out,
          );
      }
    }
    return out;
  }

  Future<void> _expandCopyFile({
    required Filesystem sourceFs,
    required String source,
    required String destination,
    required LaunchManifest manifest,
  }) async {
    final bytes = await sourceFs.readBytes(source);
    if (bytes == null) {
      throw StateError(
        'Launch manifest copy source missing on control plane: $source',
      );
    }
    manifest.ensureDir(manifest.pathContext.dirname(destination));
    manifest.writeFile(
      destination,
      utf8.decode(bytes, allowMalformed: true),
    );
  }

  Future<void> _expandCopyTree({
    required Filesystem sourceFs,
    required String source,
    required String destination,
    required LaunchManifest manifest,
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
    final ctx = manifest.pathContext;
    for (final entry in entries) {
      if (entry.isDirectory) continue;
      final srcPath = ctx.join(source, entry.name);
      final destPath = ctx.join(destination, entry.name);
      await _expandCopyFile(
        sourceFs: sourceFs,
        source: srcPath,
        destination: destPath,
        manifest: manifest,
      );
    }
  }

  static String _buildApplyScript(LaunchManifest manifest) {
    final buffer = StringBuffer()..writeln('set -e');
    for (final entry in manifest.entries) {
      switch (entry) {
        case ManifestEnsureDir(:final path):
          buffer.writeln('mkdir -p ${_shellQuote(path)}');
        case ManifestWriteFile(:final path, :final content):
          final quoted = _shellQuote(path);
          final dir = _shellQuote(_dirname(path));
          final delimiter = _heredocDelimiter(content);
          buffer
            ..writeln('mkdir -p $dir')
            ..writeln("cat > $quoted <<'$delimiter'")
            ..writeln(content)
            ..writeln(delimiter);
        case ManifestSymlink(:final linkPath, :final target):
          final dir = _shellQuote(_dirname(linkPath));
          buffer
            ..writeln('mkdir -p $dir')
            ..writeln(
              'ln -sf ${_shellQuote(target)} ${_shellQuote(linkPath)}',
            );
        case ManifestRemoveRecursive(:final path):
          buffer.writeln('rm -rf ${_shellQuote(path)}');
        case ManifestRename(:final from, :final to):
          final dir = _shellQuote(_dirname(to));
          buffer
            ..writeln('mkdir -p $dir')
            ..writeln(
              'mv ${_shellQuote(from)} ${_shellQuote(to)}',
            );
        case ManifestCopyFile():
        case ManifestCopyTree():
          break;
      }
    }
    return buffer.toString();
  }

  @visibleForTesting
  static String debugBuildApplyScript(LaunchManifest manifest) =>
      _buildApplyScript(manifest);

  static String _heredocDelimiter(String content) {
    var delimiter = '__TP_MANIFEST_${content.hashCode.abs()}__';
    var salt = 0;
    while (content.contains(delimiter)) {
      delimiter = '__TP_MANIFEST_${content.hashCode.abs()}_${salt}__';
      salt++;
    }
    return delimiter;
  }

  static String _shellQuote(String value) =>
      "'${value.replaceAll("'", "'\"'\"'")}'";

  static String _dirname(String path) {
    final index = path.lastIndexOf('/');
    if (index <= 0) return '/';
    return path.substring(0, index);
  }
}
