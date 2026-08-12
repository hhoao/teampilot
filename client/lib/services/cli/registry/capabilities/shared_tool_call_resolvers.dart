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
///
/// Governance standard (tool-layer-coverage plan, Task 5): every name / key
/// here must be genuinely shared — matrix evidence (spl@93c9991, fixtures,
/// 本机实测, docs/cli-formats/) for at least two CLIs. Single-CLI names are
/// sunk to the owning CLI's resolver file and appended there
/// (e.g. Cursor's `strreplace`/`editnotebook`, OpenCode's camelCase
/// `oldString`/`newString`); names with no emission evidence are removed.
/// The category table (`tool_call_categories.dart`) is a separate union of
/// all five CLIs' tool names and is not governed here.
abstract final class SharedToolCallResolverKeys {
  static const editToolNames = {
    'edit',
    'notebookedit',
  };
  static const editPathKeys = ['file_path', 'notebook_path'];
  static const editOldStringKeys = ['old_string'];
  static const editNewStringKeys = ['new_string', 'new_source'];

  static const writeToolNames = {
    'write',
  };
  static const writePathKeys = ['file_path'];
  static const writeContentKeys = ['content'];

  // Diff codec family is a shared capability layer: codex (apply_patch
  // FREEFORM) and opencode consume the same codec configuration; the
  // freeform branch and `*** File:` header parsing live in the shared codec.
  static const diffToolNames = {'applypatch', 'apply_patch'};
  static const diffPatchKeys = ['patch', 'diff', 'input'];

  static const fileReadToolNames = {'read'};
  static const fileWriteToolNames = {
    'write',
  };
  static const fileEditToolNames = {
    'edit',
    'applypatch',
    'notebookedit',
  };

  static const shellToolNames = {
    'bash',
    'shell_command',
    'exec_command',
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
