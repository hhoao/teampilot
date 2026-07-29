import 'message.dart';
import 'tool_edit_hunk.dart';

abstract class AiEditHunkCodec {
  bool matches(String toolName);

  AiEditHunk? encode(AiToolCallPart part);
}
