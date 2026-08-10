import '../../../../models/team_config.dart';
import '../../cli_tool_adapter.dart';

/// opencode TUI (bare `opencode`, default command). Working directory via
/// process cwd; model as `provider/model`; resume via `--session`.
final class OpencodeCliToolAdapter implements CliToolAdapter {
  const OpencodeCliToolAdapter();

  @override
  List<String> buildArguments(CliLaunchContext context) {
    final member = context.member;
    final args = <String>[];

    final resume = context.resumeSessionId?.trim() ?? '';
    if (resume.isNotEmpty) {
      args.addAll(['--session', resume]);
    }

    final model = _opencodeModel(member);
    if (model.isNotEmpty) {
      args.addAll(['--model', model]);
    }

    final agent = member.agent.trim();
    if (agent.isNotEmpty) {
      args.addAll(['--agent', agent]);
    }

    addExtraArgs(args, context.team.extraArgs);
    addExtraArgs(args, member.extraArgs);

    return args;
  }

  String _opencodeModel(TeamMemberConfig member) {
    final provider = member.provider.trim();
    final model = member.model.trim();
    if (model.isEmpty) return '';
    return provider.isNotEmpty ? '$provider/$model' : model;
  }
}
