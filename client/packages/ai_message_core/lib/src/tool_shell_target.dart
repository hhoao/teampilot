import 'message.dart';

class AiShellToolTarget {
  const AiShellToolTarget({
    required this.command,
    this.description,
  });

  final String command;
  final String? description;

  static const summaryMaxChars = 80;

  String get summary {
    final d = description?.trim();
    if (d != null && d.isNotEmpty) return d;
    return truncateCommand(command);
  }

  static String truncateCommand(String command) {
    final oneLine = command.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= summaryMaxChars) return oneLine;
    return '${oneLine.substring(0, summaryMaxChars)}…';
  }
}

abstract class AiShellToolTargetResolver {
  AiShellToolTarget? resolve(AiToolCallPart part);
}
