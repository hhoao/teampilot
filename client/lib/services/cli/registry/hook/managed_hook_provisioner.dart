import 'package:path/path.dart' as p;

import '../../../../models/hook_entry.dart';
import '../../../../utils/logging/logger.dart';
import '../../../io/filesystem.dart';
import '../capabilities/hook_capability.dart';

/// 共享 managed-hooks 装配服务：统一 writer 渲染 + 脚本落盘 + 警告日志。
///
/// 5 个 CLI 装配点（claude / flashskyai / codex / cursor / opencode）原先各自
/// 复制 render + 写盘 + 日志；差异经条件参数收敛：
/// - [joinWork]：目标路径拼接（work-plane `joinWork` 归一化，或 plain
///   `pathContext.join`）；
/// - [atomicWrite] / [ensureParentDirs]：写盘方式（`writeString` 或
///   `atomicWrite`；Sftp/WslFilesystem 不自动建父目录，需要时先 ensureDir）；
/// - [pathContext]：ensure-parent 模式下 `dirname` 的解析上下文（与
///   [joinWork] 的上下文一致）；
/// - [targetOverride]：目标落在 hooksDir 之外的文件（opencode 的
///   `teampilot-user-hooks.js` 在 opencode.json 同级）；
/// - [logPrefix]：警告日志前缀（`'[hook-writer] <cli>'`；cursor 不记日志，
///   传 null）。
/// fragment 拼接留在各装配点（与其它 overlay 内容合并，见各 provider）。
final class ManagedHookProvisioner {
  const ManagedHookProvisioner({
    required this.fs,
    required this.joinWork,
    this.pathContext,
    this.atomicWrite = false,
    this.ensureParentDirs = false,
    this.logPrefix,
    this.targetOverride,
  });

  final Filesystem fs;

  /// `(dir, fileName) → 落盘路径`：默认目标 =
  /// `joinWork(ctx.hooksDir, fileName)`。
  final String Function(String dir, String fileName) joinWork;

  /// ensure-parent 模式的父目录解析上下文；null 用 [Filesystem.pathContext]。
  final p.Context? pathContext;

  /// 用 `atomicWrite` 落盘；false 时用 `writeString`。
  final bool atomicWrite;

  /// 写盘前确保父目录存在（Sftp/WslFilesystem 不自动建父目录）。
  final bool ensureParentDirs;

  /// 警告日志前缀（`'[hook-writer] <cli>'`）；null 不记日志。
  final String? logPrefix;

  /// 目标路径覆盖（返回 null 用默认目标）；用于落在 hooksDir 之外的文件。
  final String? Function(String fileName)? targetOverride;

  /// 一次渲染 + 落盘：writer.render → GeneratedScript 写盘 → 警告日志。
  /// 返回完整 [HookWriteResult]，configFragments 由装配点消费。
  Future<HookWriteResult> provision({
    required HookCapability writer,
    required List<HookEntry> entries,
    required HookRenderContext ctx,
  }) async {
    final result = writer.render(entries: entries, ctx: ctx);
    await writeScripts(result: result, ctx: ctx);
    final prefix = logPrefix;
    if (prefix != null) {
      for (final warning in result.warnings) {
        appLogger.d('$prefix $warning');
      }
    }
    return result;
  }

  /// Writes an already-rendered result without invoking the writer again.
  /// This keeps coordinator assembly pure while reusing the same injected
  /// filesystem/manifest path semantics as the legacy hook stages.
  Future<void> writeScripts({
    required HookWriteResult result,
    required HookRenderContext ctx,
  }) async {
    final ensuredDirs = <String>{};
    for (final script in result.scripts) {
      final override = targetOverride?.call(script.fileName);
      final target =
          override ??
          joinWork(script.targetDirectory ?? ctx.hooksDir, script.fileName);
      if (ensureParentDirs) {
        final parent = (pathContext ?? fs.pathContext).dirname(target);
        if (ensuredDirs.add(parent)) {
          await fs.ensureDir(parent);
        }
      }
      if (atomicWrite) {
        await fs.atomicWrite(target, script.content);
      } else {
        await fs.writeString(target, script.content);
      }
    }
  }
}
