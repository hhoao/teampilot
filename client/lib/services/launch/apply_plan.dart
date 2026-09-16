import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const applyPlanProtocolVersion = 1;
const applyPlanInlineLimitBytes = 4096;

String contentSha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

void assertApplyPath({
  required String path,
  required String workRoot,
  required p.Context pathContext,
}) {
  if (path.contains('\x00')) {
    throw StateError('path contains NUL');
  }
  final normalized = pathContext.normalize(path);
  if (pathContext.split(normalized).contains('..')) {
    throw StateError('path contains ..');
  }
  if (normalized != workRoot && !pathContext.isWithin(workRoot, normalized)) {
    throw StateError('path escapes workRoot');
  }
}

sealed class ApplyOp {
  Map<String, Object?> toJson();
}

final class ApplyEnsureDir extends ApplyOp {
  ApplyEnsureDir(this.path);

  final String path;

  @override
  Map<String, Object?> toJson() => {'op': 'ensureDir', 'path': path};
}

final class ApplyRemove extends ApplyOp {
  ApplyRemove(this.path);

  final String path;

  @override
  Map<String, Object?> toJson() => {'op': 'remove', 'path': path};
}

final class ApplyRename extends ApplyOp {
  ApplyRename({required this.from, required this.to});

  final String from;
  final String to;

  @override
  Map<String, Object?> toJson() => {'op': 'rename', 'from': from, 'to': to};
}

final class ApplySymlink extends ApplyOp {
  ApplySymlink({required this.linkPath, required this.target});

  final String linkPath;
  final String target;

  @override
  Map<String, Object?> toJson() => {
    'op': 'symlink',
    'linkPath': linkPath,
    'target': target,
  };
}

final class ApplyWriteInline extends ApplyOp {
  ApplyWriteInline({required this.path, required this.content, this.mode});

  final String path;
  final String content;
  final int? mode;

  @override
  Map<String, Object?> toJson() => {
    'op': 'writeInline',
    'path': path,
    'content': content,
    if (mode != null) 'mode': mode,
  };
}

final class ApplyWriteBlob extends ApplyOp {
  ApplyWriteBlob({required this.path, required this.sha256, this.mode});

  final String path;
  final String sha256;
  final int? mode;

  @override
  Map<String, Object?> toJson() => {
    'op': 'writeBlob',
    'path': path,
    'sha256': sha256,
    if (mode != null) 'mode': mode,
  };
}

final class ApplyTree extends ApplyOp {
  ApplyTree({required this.dest, required this.entries});

  final String dest;
  final List<ApplyTreeEntry> entries;

  @override
  Map<String, Object?> toJson() => {
    'op': 'tree',
    'dest': dest,
    'entries': entries.map((e) => e.toJson()).toList(),
  };
}

final class ApplyTreeEntry {
  const ApplyTreeEntry({required this.rel, required this.sha256, this.mode});

  final String rel;
  final String sha256;
  final int? mode;

  Map<String, Object?> toJson() => {
    'rel': rel,
    'sha256': sha256,
    if (mode != null) 'mode': mode,
  };

  factory ApplyTreeEntry.fromJson(Map<String, Object?> json) {
    return ApplyTreeEntry(
      rel: json['rel']! as String,
      sha256: json['sha256']! as String,
      mode: json['mode'] as int?,
    );
  }
}

final class ApplyPlan {
  const ApplyPlan({
    required this.workRoot,
    required this.ops,
    this.protocolVersion = applyPlanProtocolVersion,
  });

  final int protocolVersion;
  final String workRoot;
  final List<ApplyOp> ops;

  Map<String, Object?> toJson() => {
    'protocolVersion': protocolVersion,
    'workRoot': workRoot,
    'ops': ops.map((op) => op.toJson()).toList(),
  };

  factory ApplyPlan.fromJson(Map<String, Object?> json) {
    final version = json['protocolVersion'] as int? ?? applyPlanProtocolVersion;
    if (version != applyPlanProtocolVersion) {
      throw StateError('unsupported protocolVersion');
    }
    final rawOps = json['ops'] as List<Object?>? ?? const [];
    return ApplyPlan(
      workRoot: json['workRoot']! as String,
      ops: [
        for (final raw in rawOps)
          ApplyPlan.opFromJson(raw! as Map<String, Object?>),
      ],
    );
  }

  static ApplyOp opFromJson(Map<String, Object?> json) {
    switch (json['op'] as String?) {
      case 'ensureDir':
        return ApplyEnsureDir(json['path']! as String);
      case 'remove':
        return ApplyRemove(json['path']! as String);
      case 'rename':
        return ApplyRename(
          from: json['from']! as String,
          to: json['to']! as String,
        );
      case 'symlink':
        return ApplySymlink(
          linkPath: json['linkPath']! as String,
          target: json['target']! as String,
        );
      case 'writeInline':
        return ApplyWriteInline(
          path: json['path']! as String,
          content: json['content']! as String,
          mode: json['mode'] as int?,
        );
      case 'writeBlob':
        return ApplyWriteBlob(
          path: json['path']! as String,
          sha256: json['sha256']! as String,
          mode: json['mode'] as int?,
        );
      case 'tree':
        final rawEntries = json['entries'] as List<Object?>? ?? const [];
        return ApplyTree(
          dest: json['dest']! as String,
          entries: [
            for (final raw in rawEntries)
              ApplyTreeEntry.fromJson(raw! as Map<String, Object?>),
          ],
        );
      default:
        throw StateError('unknown op: ${json['op']}');
    }
  }
}
