import '../../../models/hook_event.dart';
import '../../../models/team_config.dart';

/// 原生事件名 → 归一化 [HookEvent] 的映射表（数据驱动；不在目录的原生事件
/// 返回 null，由调用方 warning 丢弃）。归一化目录扩展时只加表项。
abstract final class HookEventNameMapper {
  HookEventNameMapper._();

  static const Map<CliTool, Map<String, HookEvent>> tables = {
    CliTool.claude: {
      'SessionStart': HookEvent.sessionStart,
      'SessionEnd': HookEvent.sessionEnd,
      'UserPromptSubmit': HookEvent.userPromptSubmit,
      'PreToolUse': HookEvent.preToolUse,
      'PostToolUse': HookEvent.postToolUse,
      'PostToolUseFailure': HookEvent.postToolUseFailure,
      'PermissionRequest': HookEvent.permissionRequest,
      'Stop': HookEvent.stop,
      'StopFailure': HookEvent.stopFailure,
      'SubagentStop': HookEvent.subagentStop,
      'PreCompact': HookEvent.preCompact,
      'Notification': HookEvent.notification,
    },
    CliTool.flashskyai: {
      'SessionStart': HookEvent.sessionStart,
      'SessionEnd': HookEvent.sessionEnd,
      'UserPromptSubmit': HookEvent.userPromptSubmit,
      'PreToolUse': HookEvent.preToolUse,
      'PostToolUse': HookEvent.postToolUse,
      'PostToolUseFailure': HookEvent.postToolUseFailure,
      'PermissionRequest': HookEvent.permissionRequest,
      'Stop': HookEvent.stop,
      'StopFailure': HookEvent.stopFailure,
      'SubagentStop': HookEvent.subagentStop,
      'PreCompact': HookEvent.preCompact,
      'Notification': HookEvent.notification,
    },
    CliTool.codex: {
      'SessionStart': HookEvent.sessionStart,
      'SessionEnd': HookEvent.sessionEnd,
      'UserPromptSubmit': HookEvent.userPromptSubmit,
      'PreToolUse': HookEvent.preToolUse,
      'PostToolUse': HookEvent.postToolUse,
      'PermissionRequest': HookEvent.permissionRequest,
      'Stop': HookEvent.stop,
      'SubagentStop': HookEvent.subagentStop,
      'PreCompact': HookEvent.preCompact,
    },
    CliTool.cursor: {
      'sessionStart': HookEvent.sessionStart,
      'sessionEnd': HookEvent.sessionEnd,
      'beforeSubmitPrompt': HookEvent.userPromptSubmit,
      'preToolUse': HookEvent.preToolUse,
      'postToolUse': HookEvent.postToolUse,
      'postToolUseFailure': HookEvent.postToolUseFailure,
      'stop': HookEvent.stop,
      'subagentStop': HookEvent.subagentStop,
      'preCompact': HookEvent.preCompact,
      'beforeShellExecution': HookEvent.shellCommandRequest,
    },
  };

  static HookEvent? map(CliTool cli, String nativeEvent) =>
      tables[cli]?[nativeEvent];
}
