import '../../../../models/team_config.dart';
import '../capabilities/prompt_capability.dart';
import '../cli_tool_registry.dart';

class PromptHubService {
  const PromptHubService({this.registry});

  final CliToolRegistry? registry;

  Future<PromptMaterializeResult> provisionForCli({
    required CliTool cli,
    required PromptMaterializeContext ctx,
  }) async {
    final capability = (registry ?? CliToolRegistry.builtIn())
        .capability<PromptCapability>(cli);
    if (capability == null) return const PromptMaterializeResult();
    return capability.materialize(ctx);
  }
}
