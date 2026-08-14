import 'package:flutter/foundation.dart';
import 'team_config.dart';

/// 归一化 hook 事件（claude 命名为规范；各 CLI 由 [HookEventCapability] 映射）。
enum HookEvent {
  sessionStart,
  sessionEnd,
  userPromptSubmit,
  preToolUse,
  postToolUse,
  postToolUseFailure,
  permissionRequest,
  stop,
  stopFailure,
  subagentStop,
  preCompact,
  notification,
  shellCommandRequest;

  /// 可携带静态决策（policy）的事件。
  bool get isIntercepting => switch (this) {
    HookEvent.preToolUse ||
    HookEvent.permissionRequest ||
    HookEvent.shellCommandRequest => true,
    _ => false,
  };

  static HookEvent? tryParse(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// 某 CLI 对某归一化事件的支持情况。
@immutable
class HookCliSupport {
  const HookCliSupport({
    required this.supported,
    this.approximate = false,
    this.nativeEvent,
  });

  final bool supported;

  /// 近似语义（如 opencode `session.idle` ≈ stop）——UI 矩阵标注。
  final bool approximate;
  final String? nativeEvent;
}

/// 归一化事件 → 各 CLI 支持矩阵（唯一事实源；writer 与 UI 能力矩阵共用）。
abstract final class HookEventCapability {
  HookEventCapability._();

  static const Map<HookEvent, Map<CliTool, HookCliSupport>> matrix = {
    HookEvent.sessionStart: {
      CliTool.claude: HookCliSupport(supported: true, nativeEvent: 'SessionStart'),
      CliTool.flashskyai: HookCliSupport(supported: true, nativeEvent: 'SessionStart'),
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'SessionStart'),
      CliTool.cursor: HookCliSupport(supported: true, nativeEvent: 'sessionStart'),
    },
    HookEvent.sessionEnd: {
      CliTool.claude: HookCliSupport(supported: true, nativeEvent: 'SessionEnd'),
      CliTool.flashskyai: HookCliSupport(supported: true, nativeEvent: 'SessionEnd'),
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'SessionEnd'),
      CliTool.cursor: HookCliSupport(supported: true, nativeEvent: 'sessionEnd'),
    },
    HookEvent.userPromptSubmit: {
      CliTool.claude: HookCliSupport(supported: true, nativeEvent: 'UserPromptSubmit'),
      CliTool.flashskyai: HookCliSupport(supported: true, nativeEvent: 'UserPromptSubmit'),
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'UserPromptSubmit'),
      CliTool.cursor: HookCliSupport(supported: true, nativeEvent: 'beforeSubmitPrompt'),
      CliTool.opencode: HookCliSupport(
        supported: true,
        approximate: true,
        nativeEvent: 'chat.message',
      ),
    },
    HookEvent.preToolUse: {
      CliTool.claude: HookCliSupport(supported: true, nativeEvent: 'PreToolUse'),
      CliTool.flashskyai: HookCliSupport(supported: true, nativeEvent: 'PreToolUse'),
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'PreToolUse'),
      CliTool.cursor: HookCliSupport(supported: true, nativeEvent: 'preToolUse'),
      CliTool.opencode: HookCliSupport(
        supported: true,
        approximate: true,
        nativeEvent: 'tool.execute.before',
      ),
    },
    HookEvent.postToolUse: {
      CliTool.claude: HookCliSupport(supported: true, nativeEvent: 'PostToolUse'),
      CliTool.flashskyai: HookCliSupport(supported: true, nativeEvent: 'PostToolUse'),
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'PostToolUse'),
      CliTool.cursor: HookCliSupport(supported: true, nativeEvent: 'postToolUse'),
      CliTool.opencode: HookCliSupport(
        supported: true,
        approximate: true,
        nativeEvent: 'tool.execute.after',
      ),
    },
    HookEvent.postToolUseFailure: {
      CliTool.claude: HookCliSupport(supported: true, nativeEvent: 'PostToolUseFailure'),
      CliTool.flashskyai: HookCliSupport(supported: true, nativeEvent: 'PostToolUseFailure'),
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'PostToolUseFailure'),
      CliTool.cursor: HookCliSupport(supported: true, nativeEvent: 'postToolUseFailure'),
    },
    HookEvent.permissionRequest: {
      CliTool.claude: HookCliSupport(supported: true, nativeEvent: 'PermissionRequest'),
      CliTool.flashskyai: HookCliSupport(supported: true, nativeEvent: 'PermissionRequest'),
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'PermissionRequest'),
      CliTool.opencode: HookCliSupport(
        supported: true,
        approximate: true,
        nativeEvent: 'permission.asked',
      ),
    },
    HookEvent.stop: {
      CliTool.claude: HookCliSupport(supported: true, nativeEvent: 'Stop'),
      CliTool.flashskyai: HookCliSupport(supported: true, nativeEvent: 'Stop'),
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'Stop'),
      CliTool.cursor: HookCliSupport(supported: true, nativeEvent: 'stop'),
      CliTool.opencode: HookCliSupport(
        supported: true,
        approximate: true,
        nativeEvent: 'session.idle',
      ),
    },
    HookEvent.stopFailure: {
      CliTool.claude: HookCliSupport(supported: true, nativeEvent: 'StopFailure'),
      CliTool.flashskyai: HookCliSupport(supported: true, nativeEvent: 'StopFailure'),
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'StopFailure'),
    },
    HookEvent.subagentStop: {
      CliTool.claude: HookCliSupport(supported: true, nativeEvent: 'SubagentStop'),
      CliTool.flashskyai: HookCliSupport(supported: true, nativeEvent: 'SubagentStop'),
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'SubagentStop'),
      CliTool.cursor: HookCliSupport(supported: true, nativeEvent: 'subagentStop'),
    },
    HookEvent.preCompact: {
      CliTool.claude: HookCliSupport(supported: true, nativeEvent: 'PreCompact'),
      CliTool.flashskyai: HookCliSupport(supported: true, nativeEvent: 'PreCompact'),
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'PreCompact'),
      CliTool.cursor: HookCliSupport(supported: true, nativeEvent: 'preCompact'),
    },
    HookEvent.notification: {
      CliTool.claude: HookCliSupport(supported: true, nativeEvent: 'Notification'),
      CliTool.flashskyai: HookCliSupport(supported: true, nativeEvent: 'Notification'),
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'Notification'),
    },
    HookEvent.shellCommandRequest: {
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'ShellCommandRequest'),
      CliTool.cursor: HookCliSupport(
        supported: true,
        approximate: true,
        nativeEvent: 'beforeShellExecution',
      ),
    },
  };

  static HookCliSupport support(HookEvent event, CliTool cli) =>
      matrix[event]?[cli] ?? const HookCliSupport(supported: false);

  static bool supports(HookEvent event, CliTool cli) =>
      support(event, cli).supported;

  static String? nativeEvent(HookEvent event, CliTool cli) =>
      support(event, cli).nativeEvent;
}
