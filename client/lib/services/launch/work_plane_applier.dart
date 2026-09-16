import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/launch/apply_plan.dart';
import 'package:teampilot/services/launch/blob_store.dart';

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

  Future<void> _applyOp(ApplyOp op) async {
    final ctx = _fs.pathContext;
    switch (op) {
      case ApplyEnsureDir(:final path):
        _assertPath(path);
        await _fs.ensureDir(path);
      case ApplyRemove(:final path):
        _assertPath(path);
        await _fs.removeRecursive(path);
      case ApplyRename(:final from, :final to):
        _assertPath(from);
        _assertPath(to);
        await _fs.rename(from, to);
      case ApplyWriteInline(:final path, :final content):
        _assertPath(path);
        await _fs.ensureDir(ctx.dirname(path));
        await _fs.writeString(path, content);
      case ApplyWriteBlob(:final path, :final sha256):
        _assertPath(path);
        final bytes = await _blobs.open(sha256);
        await _fs.ensureDir(ctx.dirname(path));
        await _fs.writeBytes(path, bytes);
      case ApplyTree(:final dest, :final entries):
        _assertPath(dest);
        await _fs.ensureDir(dest);
        for (final entry in entries) {
          final filePath = ctx.join(dest, entry.rel);
          _assertPath(filePath);
          final bytes = await _blobs.open(entry.sha256);
          await _fs.ensureDir(ctx.dirname(filePath));
          await _fs.writeBytes(filePath, bytes);
        }
      case ApplySymlink(:final linkPath, :final target):
        _assertPath(linkPath);
        _assertPath(target);
        await _fs.removeRecursive(linkPath);
        await _fs.createSymlink(target: target, linkPath: linkPath);
    }
  }
}
