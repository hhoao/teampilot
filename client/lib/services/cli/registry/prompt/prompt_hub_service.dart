import '../../../../models/team_config.dart';
import '../../../resource/assemblers/prompt_assembler.dart';
import '../../../resource/contribution/resource_assembly_error.dart';
import '../../../resource/providers/prompt_contribution_provider.dart';
import '../capabilities/prompt_capability.dart';
import '../cli_tool_registry.dart';

class PromptHubService {
  const PromptHubService({
    this.registry,
    this.assembler = const PromptAssembler(),
  });

  final CliToolRegistry? registry;
  final PromptAssembler assembler;

  Future<PromptMaterializeResult> provisionForCli({
    required CliTool cli,
    required PromptMaterializeContext ctx,
    PromptCapability? capability,
    Iterable<PromptContributionProvider>? providers,
  }) async {
    final activeRegistry = registry ?? CliToolRegistry.builtIn();
    final target =
        capability ?? activeRegistry.capability<PromptCapability>(cli);
    final sourceProviders =
        providers ??
        activeRegistry.providersOf<PromptContributionProvider>(cli);
    final assembly = await assembler.assemble(
      context: PromptProviderContext(
        cli: cli,
        scope: ctx.scope,
        member: ctx.member,
        forceTeamLeadDelegateMode: ctx.forceTeamLeadDelegateMode,
        mixed: ctx.mixed,
        pushDelivery: ctx.pushDelivery,
        additionalDirectories: ctx.additionalDirectories,
        memberHome: ctx.memberHome,
      ),
      providers: sourceProviders,
    );
    if (target == null) {
      if (assembly.document.contributions.isEmpty) {
        return const PromptMaterializeResult();
      }
      final provider = assembly.document.contributions.first.origin;
      throw ResourceAssemblyException([
        ResourceAssemblyError.unsupported(
          resourceKind: ResourceContributionKind.prompt,
          cli: cli,
          providerId: provider.providerId,
          sourceId: provider.sourceId,
          message: 'CLI has no PromptCapability for assembled contributions.',
        ),
      ]);
    }
    final materialized = await target.materialize(
      ctx,
      document: assembly.document,
    );
    return PromptMaterializeResult(
      environment: materialized.environment,
      written: materialized.written,
      assembly: materialized.assembly ?? assembly.assembly,
    );
  }
}
