import 'message.dart';

class AiToolFileTarget {
  const AiToolFileTarget({
    required this.path,
    this.startLine,
    this.endLine,
  });

  final String path;
  final int? startLine;
  final int? endLine;
}

abstract class AiToolFileTargetResolver {
  AiToolFileTarget? resolve(AiToolCallPart part);
}

class AiToolFileTargetRule {
  const AiToolFileTargetRule({
    required this.toolNames,
    this.pathKeys = const ['file_path', 'path', 'file', 'target_file'],
    this.startLineKeys = const ['start_line', 'startLine'],
    this.endLineKeys = const ['end_line', 'endLine'],
    this.useOffsetLimit = false,
  });

  final Set<String> toolNames;
  final List<String> pathKeys;
  final List<String> startLineKeys;
  final List<String> endLineKeys;
  final bool useOffsetLimit;
}
