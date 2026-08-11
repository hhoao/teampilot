import 'package:ai_message_core/ai_message_core.dart'
    hide
        StrReplaceEditHunkCodec,
        WriteEditHunkCodec,
        UnifiedDiffEditHunkCodec;

import '../../../ai_history/edit_codecs/str_replace_edit_hunk_codec.dart';
import '../../../ai_history/edit_codecs/unified_diff_edit_hunk_codec.dart';
import '../../../ai_history/edit_codecs/write_edit_hunk_codec.dart';
import '../../../ai_history/tool_call_categories.dart';
import '../../../ai_history/tool_call_resolvers.dart';
import 'tool_call_resolver_capability.dart';

/// Shared edit/file/shell/category configuration for all built-in CLIs.
/// Per-CLI deltas override specific resolvers (see CursorToolCallResolvers).
class SharedToolCallResolvers implements ToolCallResolversCapability {
  const SharedToolCallResolvers();

  static const _strReplaceCodec = StrReplaceEditHunkCodec(
    toolNames: {'strreplace', 'edit', 'editnotebook', 'notebookedit'},
    pathKeys: ['file_path', 'path', 'file', 'target_file'],
    oldStringKeys: ['old_string', 'oldString'],
    newStringKeys: ['new_string', 'newString'],
    startLineKeys: ['start_line', 'startLine'],
  );

  static const _writeCodec = WriteEditHunkCodec(
    toolNames: {'write', 'writefile', 'write_file', 'create', 'create_file'},
    pathKeys: ['file_path', 'path', 'file', 'target_file'],
    contentKeys: ['content', 'contents'],
  );

  static const _unifiedDiffCodec = UnifiedDiffEditHunkCodec(
    toolNames: {'applypatch', 'apply_patch'},
    pathKeys: ['file_path', 'path', 'file', 'target_file'],
    patchKeys: ['patch', 'diff', 'input'],
  );

  static const _fileRules = <AiToolFileTargetRule>[
    AiToolFileTargetRule(
      toolNames: {'read', 'readfile', 'read_file'},
      useOffsetLimit: true,
    ),
    AiToolFileTargetRule(
      toolNames: {
        'write',
        'writefile',
        'write_file',
        'create',
        'create_file',
      },
    ),
    AiToolFileTargetRule(
      toolNames: {
        'edit',
        'strreplace',
        'applypatch',
        'editnotebook',
        'notebookedit',
      },
    ),
  ];

  static const _shellToolNames = {
    'bash',
    'shell',
    'shell_command',
    'exec_command',
    'run_shell_command',
    'run_terminal_cmd',
  };

  @override
  AiEditToolTargetResolver get editResolver =>
      const ConfigurableAiEditToolTargetResolver(
        codecs: [_strReplaceCodec, _writeCodec, _unifiedDiffCodec],
      );

  @override
  AiToolFileTargetResolver get fileResolver =>
      const ConfigurableAiToolFileTargetResolver(rules: _fileRules);

  @override
  AiShellToolTargetResolver get shellResolver =>
      const ConfigurableAiShellToolTargetResolver(toolNames: _shellToolNames);

  @override
  AiToolCallCategoryResolver get categoryResolver =>
      defaultToolCallCategoryResolver;
}
