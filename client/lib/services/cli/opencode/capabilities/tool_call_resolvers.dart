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
import '../../registry/capabilities/shared_tool_call_resolvers.dart';
import '../../registry/capabilities/tool_call_resolver_capability.dart';

/// OpenCode tool-call resolvers: shared baseline plus the camelCase
/// `filePath` argument key OpenCode emits for `edit` / `write` / `read`.
class OpencodeToolCallResolvers implements ToolCallResolversCapability {
  const OpencodeToolCallResolvers();

  static const _pathKeys = [
    ...SharedToolCallResolverKeys.editPathKeys,
    'filePath',
  ];

  static const _strReplaceCodec = StrReplaceEditHunkCodec(
    toolNames: SharedToolCallResolverKeys.editToolNames,
    pathKeys: _pathKeys,
    oldStringKeys: SharedToolCallResolverKeys.editOldStringKeys,
    newStringKeys: SharedToolCallResolverKeys.editNewStringKeys,
    startLineKeys: SharedToolCallResolverKeys.editStartLineKeys,
  );

  static const _writeCodec = WriteEditHunkCodec(
    toolNames: SharedToolCallResolverKeys.writeToolNames,
    pathKeys: _pathKeys,
    contentKeys: SharedToolCallResolverKeys.writeContentKeys,
  );

  static const _unifiedDiffCodec = UnifiedDiffEditHunkCodec(
    toolNames: SharedToolCallResolverKeys.diffToolNames,
    pathKeys: _pathKeys,
    patchKeys: SharedToolCallResolverKeys.diffPatchKeys,
  );

  static const _fileRules = <AiToolFileTargetRule>[
    AiToolFileTargetRule(
      toolNames: SharedToolCallResolverKeys.fileReadToolNames,
      pathKeys: _pathKeys,
      useOffsetLimit: true,
    ),
    AiToolFileTargetRule(
      toolNames: SharedToolCallResolverKeys.fileWriteToolNames,
      pathKeys: _pathKeys,
    ),
    AiToolFileTargetRule(
      toolNames: SharedToolCallResolverKeys.fileEditToolNames,
      pathKeys: _pathKeys,
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
        toolNames: SharedToolCallResolverKeys.shellToolNames,
      );

  @override
  AiToolCallCategoryResolver get categoryResolver =>
      defaultToolCallCategoryResolver;
}
