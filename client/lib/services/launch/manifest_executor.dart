import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/ssh_profile.dart';
import 'package:logger/logger.dart';
import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import '../ssh/ssh_client_factory.dart';
import 'launch_manifest.dart';
import 'work_plane_script_runner.dart';

/// Applies a staged [LaunchManifest] in one batch (local disk or SSH script).
class ManifestExecutor {
  const ManifestExecutor({this.sshClientFactory, this.profileById});

  final SshClientFactory? sshClientFactory;
  final SshProfile? Function(String profileId)? profileById;

  Future<void> flush({
    required LaunchManifest manifest,
    required Filesystem targetFs,
    required Filesystem sourceFs,
    String? sshProfileId,
  }) async {
    final runner = SshWorkPlaneScriptRunner.tryCreate(
      sshProfileId: sshProfileId,
      sshClientFactory: sshClientFactory,
      profileById: profileById,
    );
    if (runner != null) {
      // Same work FS (Android/SSH home): apply mkdir/ln/cp on the remote in
      // one script. Cross-machine off-home still expands local copies first.
      final toApply = identical(sourceFs, targetFs)
          ? manifest
          : await _expandCopies(manifest, sourceFs);
      await _flushViaSsh(runner: runner, manifest: toApply);
      return;
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
    final expandSw = Stopwatch()..start();
    final applied = identical(sourceFs, targetFs)
        ? manifest
        : await _expandCopies(manifest, sourceFs);
    if (!identical(sourceFs, targetFs)) {
      appLogger.d(
        '[session-launch] manifest expand-copies '
        'in=${manifest.entries.length} out=${applied.entries.length} '
        'ms=${expandSw.elapsedMilliseconds}',
      );
    }
    final byKindMs = <String, int>{};
    final byKindCount = <String, int>{};
    const slowMs = 50;
    for (final entry in applied.entries) {
      final kind = switch (entry) {
        ManifestEnsureDir() => 'ensureDir',
        ManifestWriteFile() => 'writeFile',
        ManifestSymlink() => 'symlink',
        ManifestCopyFile() => 'copyFile',
        ManifestCopyTree() => 'copyTree',
        ManifestRemoveRecursive() => 'removeRecursive',
        ManifestRename() => 'rename',
      };
      final sw = Stopwatch()..start();
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
      final ms = sw.elapsedMilliseconds;
      byKindMs[kind] = (byKindMs[kind] ?? 0) + ms;
      byKindCount[kind] = (byKindCount[kind] ?? 0) + 1;
      if (ms >= slowMs) {
        final detail = switch (entry) {
          ManifestEnsureDir(:final path) => path,
          ManifestWriteFile(:final path) => path,
          ManifestSymlink(:final linkPath) => linkPath,
          ManifestCopyFile(:final destination) => destination,
          ManifestCopyTree(:final source, :final destination) =>
            '$source -> $destination',
          ManifestRemoveRecursive(:final path) => path,
          ManifestRename(:final from, :final to) => '$from -> $to',
        };
        appLogger.d(
          '[session-launch] manifest slow-op kind=$kind ms=$ms detail=$detail',
        );
      }
    }
    final summary = byKindCount.keys
        .map(
          (k) =>
              '$k=${byKindCount[k]}x/${byKindMs[k]}ms',
        )
        .join(' ');
    appLogger.d(
      '[session-launch] manifest flush-local '
      'ops=${applied.entries.length} $summary',
    );
  }

  Future<void> _flushViaSsh({
    required WorkPlaneScriptRunner runner,
    required LaunchManifest manifest,
  }) async {
    final script = _buildApplyScript(manifest);
    appLogger.d(
      '[session-launch] manifest flush via ssh ops=${manifest.entries.length}',
    );
    await runner.runScript(
      script,
      operation: 'Launch manifest apply',
    );
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
    manifest.writeFile(destination, utf8.decode(bytes, allowMalformed: true));
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
            ..writeln('ln -sf ${_shellQuote(target)} ${_shellQuote(linkPath)}');
        case ManifestRemoveRecursive(:final path):
          buffer.writeln('rm -rf ${_shellQuote(path)}');
        case ManifestRename(:final from, :final to):
          final dir = _shellQuote(_dirname(to));
          buffer
            ..writeln('mkdir -p $dir')
            ..writeln('mv ${_shellQuote(from)} ${_shellQuote(to)}');
        case ManifestCopyFile(:final source, :final destination):
          final dir = _shellQuote(_dirname(destination));
          buffer
            ..writeln('mkdir -p $dir')
            ..writeln(
              'cp -f -- ${_shellQuote(source)} ${_shellQuote(destination)}',
            );
        case ManifestCopyTree(:final source, :final destination):
          buffer
            ..writeln('mkdir -p ${_shellQuote(_dirname(destination))}')
            ..writeln('rm -rf ${_shellQuote(destination)}')
            ..writeln('mkdir -p ${_shellQuote(destination)}')
            ..writeln(
              'cp -R -- ${_shellQuote('$source/.')} '
              '${_shellQuote(destination)}',
            );
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
