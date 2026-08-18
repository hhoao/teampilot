import 'dart:convert';

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
import '../cli/registry/hook/managed_hook_provisioner.dart';
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
    this.appConfigDir,
    this.fallbackAppConfigDir,
    this.mcpOutputBasename,
    this.hooksDir,
    this.hookConfigPath,
    this.hookRenderContext,
  }) : members = List.unmodifiable(members),
       additionalDirectories = List.unmodifiable(additionalDirectories);

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

  final String? appConfigDir;
  final String? fallbackAppConfigDir;
  final String? mcpOutputBasename;
  final String? hooksDir;

  /// Optional target file for the single native hook config fragment.
  ///
  /// Some CLIs read hooks from a member-specific file or a fake HOME rather
  /// than from [configDir].
  final String? hookConfigPath;
  final HookRenderContext? hookRenderContext;
}

/// Per-kind result retained by the launch staging caller for diagnostics and
/// observability. A kind is not attempted when its assembled set is empty.
class ResourceMaterializationResult {
  factory ResourceMaterializationResult({
    required ResourceContributionKind kind,
    required bool attempted,
    bool materialized = false,
    Iterable<String> warnings = const [],
    Iterable<ResourceAssemblyDiagnostic> diagnostics = const [],
  }) => ResourceMaterializationResult._(
    kind: kind,
    attempted: attempted,
    materialized: materialized,
    warnings: warnings,
    diagnostics: diagnostics,
  );

  ResourceMaterializationResult._({
    required this.kind,
    required this.attempted,
    required this.materialized,
    required Iterable<String> warnings,
    required Iterable<ResourceAssemblyDiagnostic> diagnostics,
  }) : warnings = List.unmodifiable(warnings),
       diagnostics = List.unmodifiable(diagnostics);

  final ResourceContributionKind kind;
  final bool attempted;
  final bool materialized;
  final List<String> warnings;
  final List<ResourceAssemblyDiagnostic> diagnostics;
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
    this.promptMaterialization,
    Iterable<SkillContribution> skills = const [],
    Iterable<McpServerSpec> mcpServers = const [],
    Iterable<HookEntry> hooks = const [],
  }) : warnings = List.unmodifiable(warnings),
       hardDiagnostics = List.unmodifiable(hardDiagnostics),
       materializations = Map.unmodifiable({
         for (final kind in ResourceContributionKind.values)
           kind:
               materializations[kind] ??
               ResourceMaterializationResult(kind: kind, attempted: false),
         ...materializations,
       }),
       skills = List.unmodifiable(skills),
       mcpServers = List.unmodifiable(mcpServers),
       hooks = List.unmodifiable(hooks);

  final List<ResourceAssemblyDiagnostic> warnings;
  final List<ResourceAssemblyError> hardDiagnostics;
  final Map<ResourceContributionKind, ResourceMaterializationResult>
  materializations;
  final PromptDocument? prompt;
  final PromptMaterializeResult? promptMaterialization;
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
        <ResourceContributionKind, ResourceMaterializationResult>{
          for (final kind in ResourceContributionKind.values)
            kind: ResourceMaterializationResult(kind: kind, attempted: false),
        };

    PromptAssemblyResult? promptAssembly;
    SkillAssemblyResult? skillAssembly;
    McpAssemblyResult? mcpAssembly;
    HookAssemblyResult? hookAssembly;
    PromptMaterializeResult? promptMaterialization;

    // Keep all collection and assembly ahead of every target write. This is
    // deliberately sequential at the kind boundary; provider order inside
    // each assembler remains deterministic even when providers are async.
    var hardCount = hard.length;
    promptAssembly = await _assemblePrompt(context, providers, warnings, hard);
    _recordAssemblyFailure(
      ResourceContributionKind.prompt,
      materializations,
      hard,
      hardCount,
    );
    hardCount = hard.length;
    skillAssembly = await _assembleSkill(context, providers, warnings, hard);
    _recordAssemblyFailure(
      ResourceContributionKind.skill,
      materializations,
      hard,
      hardCount,
    );
    hardCount = hard.length;
    mcpAssembly = await _assembleMcp(context, providers, warnings, hard);
    _recordAssemblyFailure(
      ResourceContributionKind.mcp,
      materializations,
      hard,
      hardCount,
    );
    hardCount = hard.length;
    hookAssembly = await _assembleHook(context, providers, warnings, hard);
    _recordAssemblyFailure(
      ResourceContributionKind.hook,
      materializations,
      hard,
      hardCount,
    );

    final prompt = promptAssembly?.document ?? PromptDocument([]);
    final skills = skillAssembly?.skills ?? const <SkillContribution>[];
    final mcpServers = mcpAssembly?.servers ?? const <McpServerSpec>[];
    final hooks = hookAssembly?.entries ?? const <HookEntry>[];

    if (skillAssembly != null && skills.isNotEmpty) {
      final capability = _registry.capability<SkillCapability>(context.cli);
      if (capability == null ||
          capability.skillsRepresentation !=
              ResourceRepresentation.linkedDirectory) {
        final diagnostic = _unsupported(
          ResourceContributionKind.skill,
          context.cli,
        );
        hard.add(diagnostic);
        materializations[ResourceContributionKind.skill] =
            ResourceMaterializationResult(
              kind: ResourceContributionKind.skill,
              attempted: true,
              diagnostics: [diagnostic],
            );
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
                diagnostics: const [],
              );
        } on Object catch (error, stackTrace) {
          final diagnostic = _materializerFailure(
            ResourceContributionKind.skill,
            context.cli,
            error,
            stackTrace,
          );
          hard.add(diagnostic);
          materializations[ResourceContributionKind.skill] =
              ResourceMaterializationResult(
                kind: ResourceContributionKind.skill,
                attempted: true,
                diagnostics: [diagnostic],
              );
        }
      }
    } else if (skillAssembly != null) {
      materializations[ResourceContributionKind.skill] =
          ResourceMaterializationResult(
            kind: ResourceContributionKind.skill,
            attempted: false,
          );
    }

    if (promptAssembly != null && prompt.contributions.isNotEmpty) {
      final capability = _registry.capability<PromptCapability>(context.cli);
      if (capability == null) {
        final diagnostic = _unsupported(
          ResourceContributionKind.prompt,
          context.cli,
        );
        hard.add(diagnostic);
        materializations[ResourceContributionKind.prompt] =
            ResourceMaterializationResult(
              kind: ResourceContributionKind.prompt,
              attempted: true,
              diagnostics: [diagnostic],
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
          promptMaterialization = result;
          warnings.addAll(result.diagnostics.where(_isWarning));
          materializations[ResourceContributionKind.prompt] =
              ResourceMaterializationResult(
                kind: ResourceContributionKind.prompt,
                attempted: true,
                materialized: result.written,
              );
        } on Object catch (error, stackTrace) {
          final diagnostic = _materializerFailure(
            ResourceContributionKind.prompt,
            context.cli,
            error,
            stackTrace,
          );
          hard.add(diagnostic);
          materializations[ResourceContributionKind.prompt] =
              ResourceMaterializationResult(
                kind: ResourceContributionKind.prompt,
                attempted: true,
                diagnostics: [diagnostic],
              );
        }
      }
    } else if (promptAssembly != null) {
      materializations[ResourceContributionKind.prompt] =
          ResourceMaterializationResult(
            kind: ResourceContributionKind.prompt,
            attempted: false,
          );
    }

    if (mcpAssembly != null && mcpServers.isNotEmpty) {
      final capability = _registry.capability<McpCapability>(context.cli);
      if (capability == null) {
        final diagnostic = _unsupported(
          ResourceContributionKind.mcp,
          context.cli,
        );
        hard.add(diagnostic);
        materializations[ResourceContributionKind.mcp] =
            ResourceMaterializationResult(
              kind: ResourceContributionKind.mcp,
              attempted: true,
              diagnostics: [diagnostic],
            );
      } else {
        try {
          await capability.write(
            fs: _fs,
            configDir: context.configDir,
            servers: mcpServers,
            outputBasename: context.mcpOutputBasename,
          );
          materializations[ResourceContributionKind.mcp] =
              ResourceMaterializationResult(
                kind: ResourceContributionKind.mcp,
                attempted: true,
                materialized: true,
              );
        } on Object catch (error, stackTrace) {
          final diagnostic = _materializerFailure(
            ResourceContributionKind.mcp,
            context.cli,
            error,
            stackTrace,
          );
          hard.add(diagnostic);
          materializations[ResourceContributionKind.mcp] =
              ResourceMaterializationResult(
                kind: ResourceContributionKind.mcp,
                attempted: true,
                diagnostics: [diagnostic],
              );
        }
      }
    } else if (mcpAssembly != null) {
      materializations[ResourceContributionKind.mcp] =
          ResourceMaterializationResult(
            kind: ResourceContributionKind.mcp,
            attempted: false,
          );
    }

    if (hookAssembly != null && hooks.isNotEmpty) {
      final capability = _registry.capability<HookCapability>(context.cli);
      if (capability == null) {
        final diagnostic = _unsupported(
          ResourceContributionKind.hook,
          context.cli,
        );
        hard.add(diagnostic);
        materializations[ResourceContributionKind.hook] =
            ResourceMaterializationResult(
              kind: ResourceContributionKind.hook,
              attempted: true,
              diagnostics: [diagnostic],
            );
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
          await _materializeHookResult(context: context, result: result);
          warnings.addAll(_hookWarnings(context.cli, result.warnings));
          materializations[ResourceContributionKind.hook] =
              ResourceMaterializationResult(
                kind: ResourceContributionKind.hook,
                attempted: true,
                materialized: true,
                warnings: result.warnings,
              );
        } on Object catch (error, stackTrace) {
          final diagnostic = _materializerFailure(
            ResourceContributionKind.hook,
            context.cli,
            error,
            stackTrace,
          );
          hard.add(diagnostic);
          materializations[ResourceContributionKind.hook] =
              ResourceMaterializationResult(
                kind: ResourceContributionKind.hook,
                attempted: true,
                diagnostics: [diagnostic],
              );
        }
      }
    } else if (hookAssembly != null) {
      materializations[ResourceContributionKind.hook] =
          ResourceMaterializationResult(
            kind: ResourceContributionKind.hook,
            attempted: false,
          );
    }

    // Credential merge intentionally follows all four resource writes. It is
    // a separate app/session concern and is skipped when no app path exists.
    if (context.appConfigDir != null &&
        context.appConfigDir!.trim().isNotEmpty &&
        mcpAssembly?.hasCatalogCredentialSource == true &&
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
      promptMaterialization: promptMaterialization,
      skills: skills,
      mcpServers: mcpServers,
      hooks: hooks,
    );
  }

  /// Assembles and materializes only hooks for an additional roster member.
  ///
  /// Team launch staging uses this after the single full resource pass so
  /// prompt, skill, and MCP providers are not assembled again for every
  /// member. Hook providers remain per-member because their endpoints,
  /// target CLI, and lead-only commands are seat-specific.
  Future<ResourceProvisionReport> provisionHooks(
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
        <ResourceContributionKind, ResourceMaterializationResult>{
          for (final kind in ResourceContributionKind.values)
            kind: ResourceMaterializationResult(kind: kind, attempted: false),
        };

    final hardCount = hard.length;
    final hookAssembly = await _assembleHook(
      context,
      providers,
      warnings,
      hard,
    );
    _recordAssemblyFailure(
      ResourceContributionKind.hook,
      materializations,
      hard,
      hardCount,
    );
    if (hookAssembly != null && hookAssembly.entries.isNotEmpty) {
      final capability = _registry.capability<HookCapability>(context.cli);
      if (capability == null) {
        final diagnostic = _unsupported(
          ResourceContributionKind.hook,
          context.cli,
        );
        hard.add(diagnostic);
        materializations[ResourceContributionKind.hook] =
            ResourceMaterializationResult(
              kind: ResourceContributionKind.hook,
              attempted: true,
              diagnostics: [diagnostic],
            );
      } else {
        try {
          final result = capability.render(
            entries: hookAssembly.entries,
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
          await _materializeHookResult(context: context, result: result);
          warnings.addAll(_hookWarnings(context.cli, result.warnings));
          materializations[ResourceContributionKind.hook] =
              ResourceMaterializationResult(
                kind: ResourceContributionKind.hook,
                attempted: true,
                materialized: true,
                warnings: result.warnings,
              );
        } on Object catch (error, stackTrace) {
          final diagnostic = _materializerFailure(
            ResourceContributionKind.hook,
            context.cli,
            error,
            stackTrace,
          );
          hard.add(diagnostic);
          materializations[ResourceContributionKind.hook] =
              ResourceMaterializationResult(
                kind: ResourceContributionKind.hook,
                attempted: true,
                diagnostics: [diagnostic],
              );
        }
      }
    } else if (hookAssembly != null) {
      materializations[ResourceContributionKind.hook] =
          ResourceMaterializationResult(
            kind: ResourceContributionKind.hook,
            attempted: false,
          );
    }

    return ResourceProvisionReport(
      warnings: warnings,
      hardDiagnostics: hard,
      materializations: materializations,
      hooks: hookAssembly?.entries ?? const <HookEntry>[],
    );
  }

  Future<void> _materializeHookResult({
    required CliResourceProvisionContext context,
    required HookWriteResult result,
  }) async {
    final hooksDir =
        context.hooksDir ?? _fs.pathContext.join(context.configDir, 'hooks');
    final renderContext =
        context.hookRenderContext ??
        HookRenderContext(
          hooksDir: hooksDir,
          runner: null,
          glueBuilder: const GlueScriptBuilder(),
        );
    await ManagedHookProvisioner(
      fs: _fs,
      joinWork: _fs.pathContext.join,
      atomicWrite: true,
      ensureParentDirs: true,
    ).writeScripts(result: result, ctx: renderContext);
    for (final entry in result.configFragments.entries) {
      final target = context.hookConfigPath != null
          ? context.hookConfigPath!
          : _fs.pathContext.join(context.configDir, entry.key);
      await _fs.ensureDir(_fs.pathContext.dirname(target));
      await _mergeConfigFragment(
        context: context,
        target: target,
        fragment: entry.value,
      );
    }
  }

  Future<void> _mergeConfigFragment({
    required CliResourceProvisionContext context,
    required String target,
    required Object? fragment,
  }) async {
    final existingRaw = await _fs.readString(target);
    final fragmentMap = _objectMap(fragment);
    if (fragmentMap != null) {
      final existingMap = _objectMap(
        existingRaw == null || existingRaw.trim().isEmpty
            ? null
            : _tryDecodeJson(existingRaw),
      );
      final merged = _deepMerge(existingMap ?? const {}, fragmentMap);
      if (context.paths != null) {
        await context.paths!.writeJsonIfChanged(target, merged);
      } else {
        await _fs.atomicWrite(
          target,
          const JsonEncoder.withIndent('  ').convert(merged),
        );
      }
      return;
    }

    final content = fragment is String
        ? fragment
        : const JsonEncoder.withIndent('  ').convert(fragment);
    if (existingRaw == null || existingRaw.trim().isEmpty) {
      await _fs.atomicWrite(target, content);
    } else if (!existingRaw.contains(content)) {
      await _fs.atomicWrite(target, '$existingRaw\n\n$content');
    }
  }

  Map<String, Object?>? _objectMap(Object? value) {
    if (value is! Map) return null;
    return {
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }

  Object? _tryDecodeJson(String value) {
    try {
      return jsonDecode(value);
    } on FormatException {
      return null;
    }
  }

  Map<String, Object?> _deepMerge(
    Map<String, Object?> base,
    Map<String, Object?> fragment,
  ) {
    final merged = <String, Object?>{...base};
    for (final entry in fragment.entries) {
      final baseMap = _objectMap(merged[entry.key]);
      final fragmentMap = _objectMap(entry.value);
      merged[entry.key] = baseMap != null && fragmentMap != null
          ? _deepMerge(baseMap, fragmentMap)
          : entry.value;
    }
    return merged;
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

  void _recordAssemblyFailure(
    ResourceContributionKind kind,
    Map<ResourceContributionKind, ResourceMaterializationResult> results,
    List<ResourceAssemblyError> hard,
    int previousHardCount,
  ) {
    if (hard.length == previousHardCount) return;
    final diagnostics = hard.sublist(previousHardCount);
    results[kind] = ResourceMaterializationResult(
      kind: kind,
      attempted: true,
      diagnostics: diagnostics,
    );
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
