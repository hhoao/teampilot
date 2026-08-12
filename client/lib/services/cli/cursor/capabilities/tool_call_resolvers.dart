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

  // 本机实测（2026-08-13 复核 ~/.cursor agent-transcripts）：真实 cursor
  // StrReplace/Write 用 `path` 键（25839 次 StrReplace / 3902 次 Write 实测
  // 键形态 {path, old_string, new_string} / {path, contents}，`file_path`
  // 零命中）——共享键集（file_path）之外追加，spl 散文未列 key。
  static const _editPathKeys = [
    ...SharedToolCallResolverKeys.editPathKeys,
    'path',
  ];

  static const _writePathKeys = [
    ...SharedToolCallResolverKeys.writePathKeys,
    'path',
  ];

  // 本机实测：真实 cursor Write 用 `contents` 键（3902 次全为 contents，
  // `content` 零命中）。
  static const _writeContentKeys = [
    ...SharedToolCallResolverKeys.writeContentKeys,
    'contents',
  ];

  static const _strReplaceCodec = StrReplaceEditHunkCodec(
    toolNames: _editToolNames,
    pathKeys: _editPathKeys,
    oldStringKeys: SharedToolCallResolverKeys.editOldStringKeys,
    newStringKeys: SharedToolCallResolverKeys.editNewStringKeys,
  );

  static const _writeCodec = WriteEditHunkCodec(
    toolNames: SharedToolCallResolverKeys.writeToolNames,
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
