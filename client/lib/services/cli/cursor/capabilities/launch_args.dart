import '../../cli_tool_adapter.dart';

final class CursorCliToolAdapter implements CliToolAdapter {
  const CursorCliToolAdapter();

  @override
  List<String> buildArguments(CliLaunchContext context) {
    final member = context.member;
    final args = <String>[
      ...buildSessionPrefixArgs(context),
      '--approve-mcps',
      '--force',
    ];

    final model = member.model.trim();
    if (model.isNotEmpty) {
      args.addAll(['--model', model]);
    }
    addExtraArgs(args, context.team.extraArgs);
    addExtraArgs(args, member.extraArgs);

    return args;
  }
}
