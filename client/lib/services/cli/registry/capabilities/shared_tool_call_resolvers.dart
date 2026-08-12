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

/// Baseline tool-name / argument-key lists for the shared resolvers.
/// Per-CLI resolvers reuse these and extend them (e.g. OpenCode's camelCase
/// `filePath`), keeping CLI-specific keys out of the shared package.
abstract final class SharedToolCallResolverKeys {
  static const editToolNames = {
    'strreplace',
    'edit',
    'editnotebook',
    'notebookedit',
  };
  static const editPathKeys = ['file_path', 'path', 'file', 'target_file', 'notebook_path'];
  static const editOldStringKeys = ['old_string', 'oldString'];
  static const editNewStringKeys = ['new_string', 'newString', 'new_source'];
  static const editStartLineKeys = ['start_line', 'startLine'];

  static const writeToolNames = {
    'write',
    'writefile',
    'write_file',
    'create',
    'create_file',
  };
  static const writePathKeys = ['file_path', 'path', 'file', 'target_file'];
  static const writeContentKeys = ['content', 'contents'];

  static const diffToolNames = {'applypatch', 'apply_patch'};
  static const diffPatchKeys = ['patch', 'diff', 'input'];

  static const fileReadToolNames = {'read', 'readfile', 'read_file'};
  static const fileWriteToolNames = {
    'write',
    'writefile',
    'write_file',
    'create',
    'create_file',
  };
  static const fileEditToolNames = {
    'edit',
    'strreplace',
    'applypatch',
    'editnotebook',
    'notebookedit',
  };

  static const shellToolNames = {
    'bash',
    'shell',
    'shell_command',
    'exec_command',
    'run_shell_command',
    'run_terminal_cmd',
  };
}

/// Shared edit/file/shell/category configuration for all built-in CLIs.
/// Per-CLI deltas override specific resolvers (see CursorToolCallResolvers).
class SharedToolCallResolvers implements ToolCallResolversCapability {
  const SharedToolCallResolvers();

  static const _strReplaceCodec = StrReplaceEditHunkCodec(
    toolNames: SharedToolCallResolverKeys.editToolNames,
    pathKeys: SharedToolCallResolverKeys.editPathKeys,
    oldStringKeys: SharedToolCallResolverKeys.editOldStringKeys,
    newStringKeys: SharedToolCallResolverKeys.editNewStringKeys,
    startLineKeys: SharedToolCallResolverKeys.editStartLineKeys,
  );

  static const _writeCodec = WriteEditHunkCodec(
    toolNames: SharedToolCallResolverKeys.writeToolNames,
    pathKeys: SharedToolCallResolverKeys.writePathKeys,
    contentKeys: SharedToolCallResolverKeys.writeContentKeys,
  );

  static const _unifiedDiffCodec = UnifiedDiffEditHunkCodec(
    toolNames: SharedToolCallResolverKeys.diffToolNames,
    pathKeys: SharedToolCallResolverKeys.editPathKeys,
    patchKeys: SharedToolCallResolverKeys.diffPatchKeys,
  );

  static const _fileRules = <AiToolFileTargetRule>[
    AiToolFileTargetRule(
      toolNames: SharedToolCallResolverKeys.fileReadToolNames,
      useOffsetLimit: true,
    ),
    AiToolFileTargetRule(
      toolNames: SharedToolCallResolverKeys.fileWriteToolNames,
    ),
    AiToolFileTargetRule(
      toolNames: SharedToolCallResolverKeys.fileEditToolNames,
    ),
  ];

  static const _shellToolNames = SharedToolCallResolverKeys.shellToolNames;

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
