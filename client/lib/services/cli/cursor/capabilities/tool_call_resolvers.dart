import 'package:ai_message_core/ai_message_core.dart';

import '../../../ai_history/edit_codecs/str_replace_edit_hunk_codec.dart';
import '../../../ai_history/edit_codecs/unified_diff_edit_hunk_codec.dart';
import '../../../ai_history/edit_codecs/write_edit_hunk_codec.dart';
import '../../../ai_history/tool_call_resolvers.dart';
import '../../registry/capabilities/shared_tool_call_resolvers.dart';

/// Cursor tool-call resolvers: shared configuration plus Cursor-only tool
/// names (spl@93c9991: StrReplace :244-245 / EditNotebook :250-254) and
/// `execute` as a shell / terminal tool name (前瞻条目, spl 快照未见).
class CursorToolCallResolvers extends SharedToolCallResolvers {
  const CursorToolCallResolvers();

  static const _editToolNames = {
    ...SharedToolCallResolverKeys.editToolNames,
    'strreplace',
    'editnotebook',
  };

  static const _fileEditToolNames = {
    ...SharedToolCallResolverKeys.fileEditToolNames,
    'strreplace',
    'editnotebook',
  };

  static const _strReplaceCodec = StrReplaceEditHunkCodec(
    toolNames: _editToolNames,
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
      toolNames: _fileEditToolNames,
    ),
  ];

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
      const ConfigurableAiShellToolTargetResolver(
        toolNames: {
          'bash',
          'shell',
          'execute',
          'run_terminal_cmd',
          'shell_command',
          'exec_command',
          'run_shell_command',
        },
      );
}
