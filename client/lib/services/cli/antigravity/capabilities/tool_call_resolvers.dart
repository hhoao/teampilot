import 'package:ai_message_core/ai_message_core.dart';

import '../../../ai_history/edit_codecs/str_replace_edit_hunk_codec.dart';
import '../../../ai_history/edit_codecs/unified_diff_edit_hunk_codec.dart';
import '../../../ai_history/edit_codecs/write_edit_hunk_codec.dart';
import '../../../ai_history/tool_call_categories.dart';
import '../../../ai_history/tool_call_resolvers.dart';
import '../../registry/capabilities/shared_tool_call_resolvers.dart';

/// Antigravity tool-call resolvers: shared configuration plus Antigravity's
/// snake_case tool names and CamelCase argument keys.
///
/// Key shapes mirror the `agy` hook/tool payloads (`CommandLine`,
/// `AbsolutePath`, `TargetFile`, `TargetContent`, `ReplacementContent`,
/// `CodeContent`, `DirectoryPath`, `SearchPath`), while the shared snake_case
/// aliases remain accepted for ACP replays and fixture compatibility.
final class AntigravityToolCallResolvers extends SharedToolCallResolvers {
  const AntigravityToolCallResolvers();

  static const instance = AntigravityToolCallResolvers();

  static const _editToolNames = {
    ...SharedToolCallResolverKeys.editToolNames,
    'replace_file_content',
    'multi_replace_file_content',
  };

  static const _writeToolNames = {
    ...SharedToolCallResolverKeys.writeToolNames,
    'write_to_file',
  };

  static const _fileReadToolNames = {
    ...SharedToolCallResolverKeys.fileReadToolNames,
    'view_file',
  };

  static const _fileWriteToolNames = {
    ...SharedToolCallResolverKeys.fileWriteToolNames,
    'write_to_file',
  };

  static const _fileEditToolNames = {
    ...SharedToolCallResolverKeys.fileEditToolNames,
    'replace_file_content',
    'multi_replace_file_content',
  };

  static const _editPathKeys = [
    ...SharedToolCallResolverKeys.editPathKeys,
    'path',
    'TargetFile',
    'AbsolutePath',
  ];

  static const _writePathKeys = [
    ...SharedToolCallResolverKeys.writePathKeys,
    'path',
    'TargetFile',
    'AbsolutePath',
  ];

  static const _readPathKeys = [
    ...SharedToolCallResolverKeys.editPathKeys,
    'path',
    'AbsolutePath',
  ];

  static const _editOldStringKeys = [
    ...SharedToolCallResolverKeys.editOldStringKeys,
    'TargetContent',
  ];

  static const _editNewStringKeys = [
    ...SharedToolCallResolverKeys.editNewStringKeys,
    'ReplacementContent',
  ];

  static const _writeContentKeys = [
    ...SharedToolCallResolverKeys.writeContentKeys,
    'CodeContent',
  ];

  static const _shellToolNames = {
    ...SharedToolCallResolverKeys.shellToolNames,
    'run_command',
  };

  static const _strReplaceCodec = StrReplaceEditHunkCodec(
    toolNames: _editToolNames,
    pathKeys: _editPathKeys,
    oldStringKeys: _editOldStringKeys,
    newStringKeys: _editNewStringKeys,
  );

  static const _writeCodec = WriteEditHunkCodec(
    toolNames: _writeToolNames,
    pathKeys: _writePathKeys,
    contentKeys: _writeContentKeys,
  );

  static const _unifiedDiffCodec = UnifiedDiffEditHunkCodec(
    toolNames: SharedToolCallResolverKeys.diffToolNames,
    pathKeys: _editPathKeys,
    patchKeys: SharedToolCallResolverKeys.diffPatchKeys,
  );

  static const _fileRules = <AiToolFileTargetRule>[
    AiToolFileTargetRule(
      toolNames: _fileReadToolNames,
      pathKeys: _readPathKeys,
      useOffsetLimit: true,
    ),
    AiToolFileTargetRule(
      toolNames: _fileWriteToolNames,
      pathKeys: _writePathKeys,
    ),
    AiToolFileTargetRule(
      toolNames: _fileEditToolNames,
      pathKeys: _editPathKeys,
    ),
  ];

  static const _categoryNameRules = <String, AiToolCallCategory>{
    ...defaultToolCallNameRules,
    'run_command': AiToolCallCategory.command,
    'view_file': AiToolCallCategory.read,
    'write_to_file': AiToolCallCategory.write,
    'replace_file_content': AiToolCallCategory.edit,
    'multi_replace_file_content': AiToolCallCategory.edit,
    'list_dir': AiToolCallCategory.read,
    'find_by_name': AiToolCallCategory.read,
    'read_url_content': AiToolCallCategory.search,
    'invoke_subagent': AiToolCallCategory.subagent,
    'send_message': AiToolCallCategory.subagent,
    'manage_task': AiToolCallCategory.task,
    'schedule': AiToolCallCategory.task,
    'ask_question': AiToolCallCategory.askUser,
    'generate_image': AiToolCallCategory.other,
  };

  static const _categoryResolver = ConfigurableAiToolCallCategoryResolver(
    nameRules: _categoryNameRules,
    prefixRules: defaultToolCallPrefixRules,
  );

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
  AiToolCallCategoryResolver get categoryResolver => _categoryResolver;
}
