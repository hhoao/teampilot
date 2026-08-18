import '../../models/config_bundle.dart';
import '../../models/hook_entry.dart';
import '../../models/mcp_server_spec.dart';
import '../../models/team_config.dart';
import '../cli/registry/capabilities/hook_capability.dart';
import '../cli/registry/capabilities/mcp_capability.dart';
import '../cli/registry/capabilities/prompt_capability.dart';
import '../cli/registry/capabilities/skill_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../cli/registry/config_profile/config_profile_context.dart';
import '../hook/glue_script_builder.dart';
import '../io/filesystem.dart';
import '../storage/runtime_layout.dart';
import 'assemblers/hook_assembler.dart';
import 'assemblers/mcp_assembler.dart';
import 'assemblers/prompt_assembler.dart';
import 'assemblers/skill_assembler.dart';
import 'contribution/resource_assembly_error.dart';
import 'contribution/resource_assembly_result.dart';
import 'providers/hook_contribution_provider.dart';
import 'providers/mcp_contribution_provider.dart';
import 'providers/skill_contribution_provider.dart';
import 'resource_provider_set.dart';
import 'resource_scope.dart';

/// All target paths and launch data needed by one actual CLI member.
///
/// Resource providers are the only source extension point. The context keeps
/// target-side inputs together so callers do not grow one raw list per
/// resource kind as new launch sources are added.
class CliResourceProvisionContext {
  CliResourceProvisionContext({
    required this.cli,
    required this.scope,
    required this.runtimeBundle,
    required this.fs,
    required this.layout,
    required this.configDir,
    this.resourceProviders = ResourceProviderSet.empty,
    this.paths,
    this.launchScope,
    this.member,
    Iterable<TeamMemberConfig> members = const [],
    this.workingDirectory = '',
    Iterable<String> additionalDirectories = const [],
    this.forceTeamLeadDelegateMode = false,
    this.mixed = false,
    this.pushDelivery = false,
    this.memberHome,
    Iterable<McpServerSpec> extraServers = const [],
    Map<String, Map<String, Object?>> extraServerEntries = const {},
    Map<String, String> mcpCredentials = const {},
    this.appConfigDir,
    this.fallbackAppConfigDir,
    this.mcpOutputBasename,
    this.hooksDir,
    this.hookRenderContext,
  }) : members = List.unmodifiable(members),
       additionalDirectories = List.unmodifiable(additionalDirectories),
       extraServers = List.unmodifiable(extraServers),
       extraServerEntries = Map.unmodifiable(extraServerEntries),
       mcpCredentials = Map.unmodifiable(mcpCredentials);

  final CliTool cli;
  final ResourceScope scope;
  final ConfigBundle runtimeBundle;
  final Filesystem fs;
  final RuntimeLayout layout;
  final String configDir;
  final ResourceProviderSet resourceProviders;

  /// Optional work-plane delegate used by prompt target capabilities.
  final ConfigProfileDelegate? paths;
  final LaunchProfileScope? launchScope;
  final TeamMemberConfig? member;
  final List<TeamMemberConfig> members;
  final String workingDirectory;
  final List<String> additionalDirectories;
  final bool forceTeamLeadDelegateMode;
  final bool mixed;
  final bool pushDelivery;
  final String? memberHome;

  final List<McpServerSpec> extraServers;
  final Map<String, Map<String, Object?>> extraServerEntries;
  final Map<String, String> mcpCredentials;
  final String? appConfigDir;
  final String? fallbackAppConfigDir;
  final String? mcpOutputBasename;
  final String? hooksDir;
  final HookRenderContext? hookRenderContext;
}

/// Per-kind result retained by the launch staging caller for diagnostics and
/// observability. A kind is not attempted when its assembled set is empty.
class ResourceMaterializationResult {
  const ResourceMaterializationResult({
    required this.kind,
    required this.attempted,
    this.materialized = false,
    this.warnings = const [],
  });

  final ResourceContributionKind kind;
  final bool attempted;
  final bool materialized;
  final List<String> warnings;
}

/// Unified output of one member's resource stage.
class ResourceProvisionReport {
  ResourceProvisionReport({
    Iterable<ResourceAssemblyDiagnostic> warnings = const [],
    Iterable<ResourceAssemblyError> hardDiagnostics = const [],
    Map<ResourceContributionKind, ResourceMaterializationResult>
        materializations =
        const {},
    this.prompt,
    Iterable<SkillContribution> skills = const [],
    Iterable<McpServerSpec> mcpServers = const [],
    Iterable<HookEntry> hooks = const [],
  }) : warnings = List.unmodifiable(warnings),
       hardDiagnostics = List.unmodifiable(hardDiagnostics),
       materializations = Map.unmodifiable(materializations),
       skills = List.unmodifiable(skills),
       mcpServers = List.unmodifiable(mcpServers),
       hooks = List.unmodifiable(hooks);

  final List<ResourceAssemblyDiagnostic> warnings;
  final List<ResourceAssemblyError> hardDiagnostics;
  final Map<ResourceContributionKind, ResourceMaterializationResult>
  materializations;
  final PromptDocument? prompt;
  final List<SkillContribution> skills;
  final List<McpServerSpec> mcpServers;
  final List<HookEntry> hooks;

  bool get hasErrors => hardDiagnostics.isNotEmpty;
}

/// Coordinates source resolution, four neutral assemblers, and CLI writes.
final class CliResourceProvisioner {
  CliResourceProvisioner({
    required Filesystem fs,
    required CliToolRegistry registry,
  }) : _fs = fs,
       _registry = registry;

  final Filesystem _fs;
  final CliToolRegistry _registry;

  Future<ResourceProvisionReport> provision(
    CliResourceProvisionContext context,
  ) async {
    final providers = ResourceProviderSet.fromRegistryAndInjected(
      cli: context.cli,
      registry: _registry,
      injected: context.resourceProviders,
    );
    final warnings = <ResourceAssemblyDiagnostic>[];
    final hard = <ResourceAssemblyError>[];
    final materializations =
        <ResourceContributionKind, ResourceMaterializationResult>{};

    PromptAssemblyResult? promptAssembly;
    SkillAssemblyResult? skillAssembly;
    McpAssemblyResult? mcpAssembly;
    HookAssemblyResult? hookAssembly;

    // Keep all collection and assembly ahead of every target write. This is
    // deliberately sequential at the kind boundary; provider order inside
    // each assembler remains deterministic even when providers are async.
    promptAssembly = await _assemblePrompt(context, providers, warnings, hard);
    skillAssembly = await _assembleSkill(context, providers, warnings, hard);
    mcpAssembly = await _assembleMcp(context, providers, warnings, hard);
    hookAssembly = await _assembleHook(context, providers, warnings, hard);

    final prompt = promptAssembly?.document ?? PromptDocument([]);
    final skills = skillAssembly?.skills ?? const <SkillContribution>[];
    final mcpServers = mcpAssembly?.servers ?? const <McpServerSpec>[];
    final hooks = hookAssembly?.entries ?? const <HookEntry>[];

    if (skills.isNotEmpty) {
      final capability = _registry.capability<SkillCapability>(context.cli);
      if (capability == null ||
          capability.skillsRepresentation !=
              ResourceRepresentation.linkedDirectory) {
        hard.add(_unsupported(ResourceContributionKind.skill, context.cli));
      } else {
        try {
          final result = await capability.materializeSkills(
            fs: _fs,
            configDir: context.configDir,
            contributions: skills,
          );
          warnings.addAll(_materializeWarnings(context.cli, result.errors));
          materializations[ResourceContributionKind.skill] =
              ResourceMaterializationResult(
                kind: ResourceContributionKind.skill,
                attempted: true,
                materialized: result.errors.isEmpty,
                warnings: result.errors,
              );
        } on Object catch (error, stackTrace) {
          hard.add(
            _materializerFailure(
              ResourceContributionKind.skill,
              context.cli,
              error,
              stackTrace,
            ),
          );
        }
      }
    } else {
      materializations[ResourceContributionKind.skill] =
          const ResourceMaterializationResult(
            kind: ResourceContributionKind.skill,
            attempted: false,
          );
    }

    if (prompt.contributions.isNotEmpty) {
      final capability = _registry.capability<PromptCapability>(context.cli);
      if (capability == null) {
        hard.add(_unsupported(ResourceContributionKind.prompt, context.cli));
        materializations[ResourceContributionKind.prompt] =
            const ResourceMaterializationResult(
              kind: ResourceContributionKind.prompt,
              attempted: false,
            );
      } else {
        try {
          final result = await capability.materialize(
            PromptMaterializeContext(
              paths: context.paths,
              scope: context.launchScope,
              member: context.member,
              forceTeamLeadDelegateMode: context.forceTeamLeadDelegateMode,
              mixed: context.mixed,
              pushDelivery: context.pushDelivery,
              additionalDirectories: context.additionalDirectories,
              memberHome: context.memberHome,
            ),
            document: prompt,
          );
          warnings.addAll(result.diagnostics.where(_isWarning));
          materializations[ResourceContributionKind.prompt] =
              ResourceMaterializationResult(
                kind: ResourceContributionKind.prompt,
                attempted: true,
                materialized: result.written,
              );
        } on Object catch (error, stackTrace) {
          hard.add(
            _materializerFailure(
              ResourceContributionKind.prompt,
              context.cli,
              error,
              stackTrace,
            ),
          );
        }
      }
    } else {
      materializations[ResourceContributionKind.prompt] =
          const ResourceMaterializationResult(
            kind: ResourceContributionKind.prompt,
            attempted: false,
          );
    }

    if (mcpServers.isNotEmpty) {
      final capability = _registry.capability<McpCapability>(context.cli);
      if (capability == null) {
        hard.add(_unsupported(ResourceContributionKind.mcp, context.cli));
      } else {
        try {
          await capability.write(
            fs: _fs,
            configDir: context.configDir,
            servers: mcpServers,
            outputBasename: context.mcpOutputBasename,
          );
          materializations[ResourceContributionKind.mcp] =
              const ResourceMaterializationResult(
                kind: ResourceContributionKind.mcp,
                attempted: true,
                materialized: true,
              );
        } on Object catch (error, stackTrace) {
          hard.add(
            _materializerFailure(
              ResourceContributionKind.mcp,
              context.cli,
              error,
              stackTrace,
            ),
          );
        }
      }
    } else {
      materializations[ResourceContributionKind.mcp] =
          const ResourceMaterializationResult(
            kind: ResourceContributionKind.mcp,
            attempted: false,
          );
    }

    if (hooks.isNotEmpty) {
      final capability = _registry.capability<HookCapability>(context.cli);
      if (capability == null) {
        hard.add(_unsupported(ResourceContributionKind.hook, context.cli));
      } else {
        try {
          final result = capability.render(
            entries: hooks,
            ctx:
                context.hookRenderContext ??
                HookRenderContext(
                  hooksDir:
                      context.hooksDir ??
                      _fs.pathContext.join(context.configDir, 'hooks'),
                  runner: null,
                  glueBuilder: const GlueScriptBuilder(),
                ),
          );
          warnings.addAll(_hookWarnings(context.cli, result.warnings));
          materializations[ResourceContributionKind.hook] =
              ResourceMaterializationResult(
                kind: ResourceContributionKind.hook,
                attempted: true,
                materialized: true,
                warnings: result.warnings,
              );
        } on Object catch (error, stackTrace) {
          hard.add(
            _materializerFailure(
              ResourceContributionKind.hook,
              context.cli,
              error,
              stackTrace,
            ),
          );
        }
      }
    } else {
      materializations[ResourceContributionKind.hook] =
          const ResourceMaterializationResult(
            kind: ResourceContributionKind.hook,
            attempted: false,
          );
    }

    // Credential merge intentionally follows all four resource writes. It is
    // a separate app/session concern and is skipped when no app path exists.
    if (context.appConfigDir != null &&
        context.appConfigDir!.trim().isNotEmpty &&
        _registry.capability<McpCapability>(context.cli) != null) {
      try {
        await _registry
            .capability<McpCapability>(context.cli)!
            .mergeAppCredentials(
              fs: _fs,
              appConfigDir: context.appConfigDir!,
              sessionConfigDir: context.configDir,
              fallbackAppConfigDir: context.fallbackAppConfigDir,
            );
      } on Object catch (error, stackTrace) {
        hard.add(
          _materializerFailure(
            ResourceContributionKind.mcp,
            context.cli,
            error,
            stackTrace,
            message: 'MCP credential merge failed: $error',
          ),
        );
      }
    }

    return ResourceProvisionReport(
      warnings: warnings,
      hardDiagnostics: hard,
      materializations: materializations,
      prompt: prompt,
      skills: skills,
      mcpServers: mcpServers,
      hooks: hooks,
    );
  }

  Future<PromptAssemblyResult?> _assemblePrompt(
    CliResourceProvisionContext context,
    ResourceProviderSet providers,
    List<ResourceAssemblyDiagnostic> warnings,
    List<ResourceAssemblyError> hard,
  ) async {
    try {
      final result = await const PromptAssembler().assemble(
        context: PromptProviderContext(
          cli: context.cli,
          scope: context.launchScope,
          member: context.member,
          forceTeamLeadDelegateMode: context.forceTeamLeadDelegateMode,
          mixed: context.mixed,
          pushDelivery: context.pushDelivery,
          additionalDirectories: context.additionalDirectories,
          memberHome: context.memberHome,
        ),
        providers: providers.prompts,
      );
      _collect(result.assembly, warnings, hard);
      return result;
    } on ResourceAssemblyException catch (error) {
      hard.addAll(error.diagnostics);
    } on Object catch (error, stackTrace) {
      hard.add(
        _providerFailure(
          ResourceContributionKind.prompt,
          context.cli,
          error,
          stackTrace,
        ),
      );
    }
    return null;
  }

  Future<SkillAssemblyResult?> _assembleSkill(
    CliResourceProvisionContext context,
    ResourceProviderSet providers,
    List<ResourceAssemblyDiagnostic> warnings,
    List<ResourceAssemblyError> hard,
  ) async {
    try {
      final result = await const SkillAssembler().assemble(
        context: SkillProviderContext(
          cli: context.cli,
          scope: context.scope,
          filesystem: _fs,
          targetConfigDir: context.configDir,
        ),
        providers: providers.skills,
      );
      _collect(result.assembly, warnings, hard);
      return result;
    } on ResourceAssemblyException catch (error) {
      hard.addAll(error.diagnostics);
    } on Object catch (error, stackTrace) {
      hard.add(
        _providerFailure(
          ResourceContributionKind.skill,
          context.cli,
          error,
          stackTrace,
        ),
      );
    }
    return null;
  }

  Future<McpAssemblyResult?> _assembleMcp(
    CliResourceProvisionContext context,
    ResourceProviderSet providers,
    List<ResourceAssemblyDiagnostic> warnings,
    List<ResourceAssemblyError> hard,
  ) async {
    try {
      final result = await const McpAssembler().assemble(
        context: McpProviderContext(
          cli: context.cli,
          scope: context.launchScope,
          mcpServerIds: context.runtimeBundle.mcpServerIds,
          extraServers: context.extraServers,
          extraServerEntries: context.extraServerEntries,
          credentials: context.mcpCredentials,
        ),
        providers: providers.mcp,
      );
      _collect(result.assembly, warnings, hard);
      return result;
    } on ResourceAssemblyException catch (error) {
      hard.addAll(error.diagnostics);
    } on Object catch (error, stackTrace) {
      hard.add(
        _providerFailure(
          ResourceContributionKind.mcp,
          context.cli,
          error,
          stackTrace,
        ),
      );
    }
    return null;
  }

  Future<HookAssemblyResult?> _assembleHook(
    CliResourceProvisionContext context,
    ResourceProviderSet providers,
    List<ResourceAssemblyDiagnostic> warnings,
    List<ResourceAssemblyError> hard,
  ) async {
    try {
      final hookCapability = _registry.capability<HookCapability>(context.cli);
      final result = await const HookAssembler().assemble(
        context: HookProviderContext(
          cli: context.cli,
          member: context.member,
          supportsHttp: hookCapability?.supportsHttp ?? false,
          filesystem: _fs,
          hooksDirectory: context.hooksDir,
          scope: context.launchScope,
        ),
        providers: providers.hooks,
      );
      _collect(result.assembly, warnings, hard);
      return result;
    } on ResourceAssemblyException catch (error) {
      hard.addAll(error.diagnostics);
    } on Object catch (error, stackTrace) {
      hard.add(
        _providerFailure(
          ResourceContributionKind.hook,
          context.cli,
          error,
          stackTrace,
        ),
      );
    }
    return null;
  }

  void _collect(
    ResourceAssemblyResult result,
    List<ResourceAssemblyDiagnostic> warnings,
    List<ResourceAssemblyError> hard,
  ) {
    warnings.addAll(result.warnings);
    hard.addAll(result.errors.whereType<ResourceAssemblyError>());
  }

  bool _isWarning(ResourceAssemblyDiagnostic diagnostic) =>
      diagnostic.severity == ResourceAssemblyDiagnosticSeverity.warning;

  List<ResourceAssemblyDiagnostic> _materializeWarnings(
    CliTool cli,
    List<String> errors,
  ) => [
    for (final error in errors)
      ResourceAssemblyDiagnostic(
        severity: ResourceAssemblyDiagnosticSeverity.warning,
        resourceKind: ResourceContributionKind.skill,
        cli: cli,
        providerId: 'skill-materializer',
        message: error,
      ),
  ];

  List<ResourceAssemblyDiagnostic> _hookWarnings(
    CliTool cli,
    List<String> values,
  ) => [
    for (final value in values)
      ResourceAssemblyDiagnostic(
        severity: ResourceAssemblyDiagnosticSeverity.warning,
        resourceKind: ResourceContributionKind.hook,
        cli: cli,
        providerId: 'hook-materializer',
        message: value,
      ),
  ];

  ResourceAssemblyError _unsupported(
    ResourceContributionKind kind,
    CliTool cli,
  ) => ResourceAssemblyError.unsupported(
    resourceKind: kind,
    cli: cli,
    providerId: 'target-capability',
    sourceId: cli.value,
    message: '${kind.name} resources are not supported by ${cli.value}.',
  );

  ResourceAssemblyError _providerFailure(
    ResourceContributionKind kind,
    CliTool cli,
    Object error,
    StackTrace stackTrace,
  ) => ResourceAssemblyError.provider(
    resourceKind: kind,
    cli: cli,
    providerId: 'resource-provider',
    sourceId: cli.value,
    message: '${kind.name} provider failed: $error',
    cause: error,
    stackTrace: stackTrace,
  );

  ResourceAssemblyError _materializerFailure(
    ResourceContributionKind kind,
    CliTool cli,
    Object error,
    StackTrace stackTrace, {
    String? message,
  }) => ResourceAssemblyError.provider(
    resourceKind: kind,
    cli: cli,
    providerId: 'resource-materializer',
    sourceId: cli.value,
    message: message ?? '${kind.name} materializer failed: $error',
    cause: error,
    stackTrace: stackTrace,
  );
}
