import 'message.dart';
import 'tool_edit_hunk.dart';

abstract class AiEditToolTargetResolver {
  AiEditToolTarget? resolve(AiToolCallPart part);
}
