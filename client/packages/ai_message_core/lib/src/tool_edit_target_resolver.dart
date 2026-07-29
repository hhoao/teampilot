import 'codecs/str_replace_edit_hunk_codec.dart';
import 'message.dart';
import 'tool_edit_hunk.dart';
import 'tool_edit_hunk_codec.dart';

abstract class AiEditToolTargetResolver {
  AiEditToolTarget? resolve(AiToolCallPart part);
}

class DefaultAiEditToolTargetResolver implements AiEditToolTargetResolver {
  const DefaultAiEditToolTargetResolver({this.codecs = defaultCodecs});

  final List<AiEditHunkCodec> codecs;

  static const defaultCodecs = <AiEditHunkCodec>[
    StrReplaceEditHunkCodec(),
  ];

  @override
  AiEditToolTarget? resolve(AiToolCallPart part) {
    for (final codec in codecs) {
      if (!codec.matches(part.toolName)) continue;
      final hunk = codec.encode(part);
      if (hunk != null) return AiEditToolTarget(hunk: hunk);
    }
    return null;
  }
}
