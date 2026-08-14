import '../../../models/team_config.dart';
import '../capabilities/prompt_capability.dart';
import '../cli_tool_registry.dart';

class PromptHubService {
  const PromptHubService();

  Future<PromptMaterializeResult> provisionForCli({
    required CliTool cli,
    required PromptMaterializeContext ctx,
  }) async {
    final capability =
        CliToolRegistry.builtIn().capability<PromptCapability>(cli);
    if (capability == null) return const PromptMaterializeResult();
    capability.virtualize(
      PromptVirtualizeContext(
        paths: ctx.paths,
        scope: ctx.scope,
        member: ctx.member,
        memberHome: ctx.memberHome,
      ),
    );
    return capability.materialize(ctx);
  }
}
