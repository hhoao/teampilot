import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/chat/launch/staging/manifest/apply_plan.dart';
import 'package:teampilot/services/chat/launch/staging/manifest/blob_store.dart';

final class WorkPlaneApplier {
  WorkPlaneApplier({
    required Filesystem fs,
    required BlobStore blobs,
    required String workRoot,
  }) : _fs = fs,
       _blobs = blobs,
       _workRoot = fs.pathContext.normalize(workRoot);

  final Filesystem _fs;
  final BlobStore _blobs;
  final String _workRoot;

  Future<void> apply(ApplyPlan plan) async {
    if (plan.protocolVersion != applyPlanProtocolVersion) {
      throw StateError('unsupported protocolVersion');
    }
    if (_fs.pathContext.normalize(plan.workRoot) != _workRoot) {
      throw StateError('workRoot mismatch');
    }

    for (final op in plan.ops) {
      _validateOp(op);
    }
    for (final op in plan.ops) {
      await _applyOp(op);
    }
  }

  void _assertPath(String path) {
    assertApplyPath(
      path: path,
      workRoot: _workRoot,
      pathContext: _fs.pathContext,
    );
  }

  void _validateOp(ApplyOp op) {
    final ctx = _fs.pathContext;
    switch (op) {
      case ApplyEnsureDir(:final path) ||
          ApplyRemove(:final path) ||
          ApplyWriteInline(:final path) ||
          ApplyWriteBlob(:final path):
        _assertPath(path);
      case ApplyRename(:final from, :final to):
        _assertPath(from);
        _assertPath(to);
      case ApplyTree(:final dest, :final entries):
        _assertPath(dest);
        for (final entry in entries) {
          _assertPath(ctx.join(dest, entry.rel));
        }
      case ApplySymlink(:final linkPath, :final target):
        _assertPath(linkPath);
        _assertPath(target);
    }
  }

  Future<void> _applyOp(ApplyOp op) async {
    final ctx = _fs.pathContext;
    switch (op) {
      case ApplyEnsureDir(:final path):
        await _fs.ensureDir(path);
      case ApplyRemove(:final path):
        await _fs.removeRecursive(path);
      case ApplyRename(:final from, :final to):
        await _fs.rename(from, to);
      case ApplyWriteInline(:final path, :final content):
        await _fs.ensureDir(ctx.dirname(path));
        await _fs.atomicWrite(path, content);
      case ApplyWriteBlob(:final path, :final sha256):
        final bytes = await _blobs.open(sha256);
        await _fs.ensureDir(ctx.dirname(path));
        await _fs.writeBytes(path, bytes);
      case ApplyTree(:final dest, :final entries):
        await _fs.ensureDir(dest);
        for (final entry in entries) {
          final filePath = ctx.join(dest, entry.rel);
          final bytes = await _blobs.open(entry.sha256);
          await _fs.ensureDir(ctx.dirname(filePath));
          await _fs.writeBytes(filePath, bytes);
        }
      case ApplySymlink(:final linkPath, :final target):
        await _fs.removeRecursive(linkPath);
        await _fs.createSymlink(target: target, linkPath: linkPath);
    }
  }
}
