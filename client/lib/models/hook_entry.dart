import 'package:flutter/foundation.dart';
import 'hook_event.dart';

/// Hook 条目的来源（收敛管线：用户库 / 插件 / 扩展 / 内部托管）。
enum HookSource { userLibrary, plugin, extension, managed }

/// 拦截类事件的静态决策。
enum HookPolicy { none, allow, deny }

/// 归一化 action：命令（原始字符串或托管脚本）或 http。
@immutable
sealed class HookAction {
  const HookAction();
}

@immutable
final class CommandHookAction extends HookAction {
  const CommandHookAction.raw(String command)
    : command = command,
      fileName = null,
      scriptContent = null;

  const CommandHookAction.script({
    required String fileName,
    String? scriptContent,
  }) : command = null,
       fileName = fileName,
       scriptContent = scriptContent;

  /// 原始命令字符串（raw 用户命令；resolver 前未解析）。
  final String? command;

  /// 托管脚本文件名（如 `hook.sh` / `hook.ps1`）。
  final String? fileName;

  /// 托管脚本内容（resolver 从全局库加载后填充）。
  final String? scriptContent;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommandHookAction &&
          command == other.command &&
          fileName == other.fileName &&
          scriptContent == other.scriptContent;

  @override
  int get hashCode => Object.hash(command, fileName, scriptContent);
}

@immutable
final class HttpHookAction extends HookAction {
  const HttpHookAction({required this.url, this.headers = const {}});

  final String url;
  final Map<String, String> headers;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HttpHookAction &&
          url == other.url &&
          mapEquals(headers, other.headers);

  @override
  int get hashCode => Object.hash(
    url,
    Object.hashAllUnordered(headers.keys),
    Object.hashAllUnordered(headers.values),
  );
}

/// 统一 hook 表示：所有来源（用户库/插件/扩展/托管）的中间形态，
/// 各 CLI HookWriter 的唯一输入。
@immutable
class HookEntry {
  const HookEntry({
    required this.id,
    required this.source,
    required this.event,
    this.matcher,
    required this.action,
    this.policy = HookPolicy.none,
    this.timeout,
    this.env = const {},
    this.blockOnDecision = false,
  });

  /// 身份键（用户库 id；内部托管源为稳定符号 id）。
  final String id;
  final HookSource source;
  final HookEvent event;

  /// 工具名/命令正则（事件支持才生效）。
  final String? matcher;
  final HookAction action;
  final HookPolicy policy;
  final Duration? timeout;
  final Map<String, String> env;

  /// idle 语义：命令末尾 `exit 2`（内部托管用）。
  final bool blockOnDecision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HookEntry &&
          id == other.id &&
          source == other.source &&
          event == other.event &&
          matcher == other.matcher &&
          action == other.action &&
          policy == other.policy &&
          timeout == other.timeout &&
          mapEquals(env, other.env) &&
          blockOnDecision == other.blockOnDecision;

  @override
  int get hashCode => Object.hash(
    id,
    source,
    event,
    matcher,
    action,
    policy,
    timeout,
    Object.hashAllUnordered(env.keys),
    Object.hashAllUnordered(env.values),
    blockOnDecision,
  );
}
