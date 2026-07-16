import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/ai_feature_settings_cubit.dart';
import '../../cubits/app_provider_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../models/ai_feature_setting.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../models/default_team_roster.dart';
import '../../models/team_roster_slot.dart';
import '../../models/team_config.dart';
import '../../services/ai/ai_feature_setting_resolver.dart';
import '../../services/ai/team_config_draft.dart';
import '../../services/ai/team_config_generator.dart';
import '../../services/ai/team_draft_roster_mapper.dart';
import '../../services/cli/registry/capabilities/provider_catalog_capability.dart';
import '../../services/cli/registry/cli_display_name.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../widgets/app_provider/brand_dropdown_rows.dart';
import '../../widgets/app_provider/provider_brand_icon.dart';
import '../../widgets/cli/cli_brand_icon.dart';
import 'home_workspace_team_generate_section.dart';

enum _TeamCreationMethod { custom, ai }

typedef _NewTeamDialogResult = ({
  String name,
  TeamMode mode,
  CliTool cli,
  Map<String, String> providerIdsByTool,
  List<TeamRosterSlot>? roster,
  String description,
});

/// Large centered "create team" modal launched from the workspace sidebar's
/// "New Team" row. Mirrors the Apifox workspace-creation modal: centered title +
/// close, Native / Mixed mode cards, a named form row, and a single primary
/// create action.
Future<void> showHomeNewTeamDialog(
  BuildContext context,
  LaunchProfileCubit teamCubit,
) async {
  final result = await showDialog<_NewTeamDialogResult>(
    context: context,
    builder: (_) => const HomeNewTeamDialog(),
  );
  if (result == null || !context.mounted) return;
  await teamCubit.addTeam(
    result.name,
    cli: result.cli,
    teamMode: result.mode,
    providerIdsByTool: result.providerIdsByTool,
    description: result.description,
    roster: (result.roster != null && result.roster!.isNotEmpty)
        ? result.roster
        : DefaultTeamRoster.bootstrap(
            joinedAt: DateTime.now().millisecondsSinceEpoch,
          ),
  );
}

class HomeNewTeamDialog extends StatefulWidget {
  const HomeNewTeamDialog({super.key});

  @override
  State<HomeNewTeamDialog> createState() => _HomeNewTeamDialogState();
}

class _HomeNewTeamDialogState extends State<HomeNewTeamDialog> {
  late final TextEditingController _nameController;
  _TeamCreationMethod _creationMethod = _TeamCreationMethod.custom;
  TeamMode? _mode;
  CliTool _cli = CliTool.claude;
  String _providerId = '';
  bool _canCreate = false;
  bool _didSeedProvider = false;
  bool _generating = false;
  TeamConfigDraft? _draft;

  /// AI-tab description; drives the "生成" button enabled state.
  String _aiDescription = '';

  /// Non-null while streaming generation runs: 0..1 progress for the bar.
  double? _genProgress;
  Timer? _easeTimer;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController()..addListener(_syncCanCreate);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didSeedProvider) return;
    _didSeedProvider = true;
    _syncDefaultProviderForCli(_cli);
  }

  @override
  void dispose() {
    _easeTimer?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  void _syncCanCreate() {
    if (_mode == null) {
      if (_canCreate) setState(() => _canCreate = false);
      return;
    }
    final canCreate = _creationMethod == _TeamCreationMethod.custom
        ? _nameController.text.trim().isNotEmpty
        : _draft != null && _draft!.members.isNotEmpty;
    if (canCreate != _canCreate) setState(() => _canCreate = canCreate);
  }

  String _teamNameForSubmit() {
    if (_creationMethod == _TeamCreationMethod.custom) {
      return _nameController.text.trim();
    }
    final draftName = _draft?.teamName?.trim();
    if (draftName != null && draftName.isNotEmpty) return draftName;
    return context.l10n.homeWorkspaceNewTeam;
  }

  CliTool? _providerCatalogCli(CliTool cli) {
    final registry = CliToolRegistryScope.maybeOf(context);
    if (registry == null) return null;
    return registry.capability<ProviderCatalogCapability>(cli) != null
        ? cli
        : null;
  }

  void _ensureNativeTeamCli() {
    final registry = CliToolRegistryScope.maybeOf(context);
    if (registry == null) return;
    if (registry.supportsNativeTeam(_cli)) return;
    final fallback = registry.nativeTeamLaunchable.firstOrNull?.id;
    if (fallback == null || fallback == _cli) return;
    setState(() {
      _cli = fallback;
      _providerId = '';
    });
    _syncDefaultProviderForCli(fallback);
  }

  void _syncDefaultProviderForCli(CliTool cli) {
    final catalogCli = _providerCatalogCli(cli);
    if (catalogCli == null) {
      if (_providerId.isNotEmpty) setState(() => _providerId = '');
      return;
    }
    final appProviders = context.read<AppProviderCubit>().state;
    final providers = appProviders.providersFor(catalogCli);
    final global = appProviders.selectedProviderIdByCli[catalogCli];
    final next = global != null && providers.any((p) => p.id == global)
        ? global
        : providers.firstOrNull?.id ?? '';
    if (next != _providerId) setState(() => _providerId = next);
  }

  Map<String, String> _providerIdsByToolForSubmit() {
    if (_mode != TeamMode.native) return const <String, String>{};
    final catalogCli = _providerCatalogCli(_cli);
    final providerId = _providerId.trim();
    if (catalogCli == null || providerId.isEmpty) {
      return const <String, String>{};
    }
    return {catalogCli.value: providerId};
  }

  _NewTeamDialogResult _buildDialogResult({
    required String name,
    required TeamMode mode,
    List<TeamRosterSlot>? roster,
    String description = '',
    Map<String, String>? providerIdsByTool,
  }) => (
    name: name,
    mode: mode,
    cli: _cli,
    providerIdsByTool: providerIdsByTool ?? const <String, String>{},
    roster: roster,
    description: description,
  );

  Future<void> _submit() async {
    final name = _teamNameForSubmit().trim();
    if (name.isEmpty) return;
    final mode = _mode;
    if (mode == null) return;
    List<TeamRosterSlot>? roster;
    if (_draft != null) {
      roster = await rosterSlotsFromTeamDraft(_draft!);
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      _buildDialogResult(
        name: name,
        mode: mode,
        providerIdsByTool: _providerIdsByToolForSubmit(),
        roster: roster,
        description: _draft?.description?.trim() ?? '',
      ),
    );
  }

  bool get _canGenerate =>
      _mode != null && _aiDescription.trim().isNotEmpty && !_generating;

  /// AI flow: stream-generate the team, advancing the progress bar, then create
  /// the team and close the dialog. The bar eases toward — but never reaches —
  /// 100% until generation completes (a periodic timer keeps it moving even when
  /// the CLI does not stream NDJSON events).
  Future<void> _generateAndCreate() async {
    final l10n = context.l10n;
    final mode = _mode;
    final description = _aiDescription.trim();
    if (mode == null || description.isEmpty || _generating) return;

    final stored = context.read<AiFeatureSettingsCubit>().state.settingFor(
      AiFeatureId.teamGenerate,
    );
    final appProviders = context.read<AppProviderCubit>().state;
    final registry = CliToolRegistryScope.of(context);
    final presets = context.read<CliPresetsCubit>().state.presets;
    if (!aiFeatureIsConfigured(
      stored: stored,
      registry: registry,
      appProviders: appProviders,
      globalPresets: presets,
    )) {
      AppToast.show(
        context,
        message: l10n.teamGenNoProvider,
        variant: TpToastVariant.error,
      );
      return;
    }
    final setting = resolveAiFeatureSetting(
      stored: stored,
      appProviders: appProviders,
      registry: registry,
      globalPresets: presets,
    );

    setState(() {
      _generating = true;
      _genProgress = 0;
    });
    _easeTimer?.cancel();
    _easeTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      final cur = _genProgress ?? 0;
      final next = (cur + (0.9 - cur) * 0.05).clamp(0.0, 0.92);
      setState(() => _genProgress = next);
    });

    try {
      final draft = await TeamConfigGenerator().generateStreaming(
        setting: setting,
        description: description,
        mode: mode,
        joinedAt: DateTime.now().millisecondsSinceEpoch,
        onProgress: (p) {
          if (!mounted) return;
          if (p > (_genProgress ?? 0)) setState(() => _genProgress = p);
        },
      );
      _easeTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _genProgress = 1.0;
        _draft = draft;
        _cli = setting.cli;
        _providerId = setting.providerId;
      });
      // Auto-create the team from the streamed draft and close the dialog.
      await _submit();
    } on Object {
      _easeTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _generating = false;
        _genProgress = null;
      });
      AppToast.show(
        context,
        message: l10n.teamGenFailed,
        variant: TpToastVariant.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);

    final maxDialogHeight = MediaQuery.sizeOf(context).height * 0.92;

    return TpDialog(
      maxWidth: 720,
      maxHeight: maxDialogHeight,
      scrollable: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(
            title: l10n.homeWorkspaceNewTeam,
            titleAlignment: Alignment.center,
            showDividerBelow: false,
          ),
          const SizedBox(height: 20),
          TpSegmentedPicker<_TeamCreationMethod>(
            alignment: Alignment.center,
            customWidths: const [156, 120],
            segments: [
              TpSegmentedOption(
                value: _TeamCreationMethod.custom,
                label: l10n.homeWorkspaceNewTeamMethodCustom,
                icon: Icons.tune_outlined,
              ),
              TpSegmentedOption(
                value: _TeamCreationMethod.ai,
                label: l10n.homeWorkspaceNewTeamMethodAi,
                icon: Icons.auto_awesome_outlined,
              ),
            ],
            selected: _creationMethod,
            onChanged: (method) {
              setState(() {
                _creationMethod = method;
                if (method == _TeamCreationMethod.custom) {
                  _draft = null;
                }
              });
              _syncCanCreate();
            },
          ),
          const SizedBox(height: 12),
          Text(
            _creationMethod == _TeamCreationMethod.custom
                ? l10n.homeWorkspaceNewTeamSubtitle
                : l10n.homeWorkspaceNewTeamSubtitleAi,
            textAlign: TextAlign.center,
            style: styles.mdColored(cs.onSurfaceVariant),
          ),
          const SizedBox(height: 28),
          // Team mode is a fundamental decision for both the custom and AI
          // flows, so the mode cards render regardless of creation method.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _ModeCard(
                    icon: Icons.dashboard_customize_outlined,
                    title: l10n.teamModeNativeTitle,
                    description: l10n.teamModeNativeDescription,
                    badge: l10n.homeWorkspaceNewTeamRecommended,
                    badgeIsPrimary: true,
                    selected: _mode == TeamMode.native,
                    onTap: () {
                      setState(() {
                        _mode = TeamMode.native;
                        _draft = null;
                      });
                      _ensureNativeTeamCli();
                      _syncCanCreate();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _ModeCard(
                    icon: Icons.hub_outlined,
                    title: l10n.teamModeMixedTitle,
                    description: l10n.teamModeMixedDescription,
                    badge: l10n.homeWorkspaceNewTeamModeBeta,
                    badgeIsPrimary: false,
                    selected: _mode == TeamMode.mixed,
                    onTap: () {
                      setState(() {
                        _mode = TeamMode.mixed;
                        _draft = null;
                      });
                      _syncCanCreate();
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_creationMethod == _TeamCreationMethod.custom) ...[
            if (_mode == TeamMode.native) ...[
              const SizedBox(height: 20),
              _NativeTeamOptionsCard(
                cli: _cli,
                providerId: _providerId,
                onCliChanged: (cli) {
                  setState(() {
                    _cli = cli;
                    _providerId = '';
                  });
                  _syncDefaultProviderForCli(cli);
                },
                onProviderChanged: (id) =>
                    setState(() => _providerId = id ?? ''),
              ),
            ],
            const SizedBox(height: 24),
            _NameField(
              controller: _nameController,
              onSubmitted: (_) => _submit(),
            ),
          ] else ...[
            const SizedBox(height: 24),
            HomeTeamGenerateSection(
              enabled: _mode != null,
              progress: _genProgress,
              onDescriptionChanged: (v) => setState(() => _aiDescription = v),
            ),
          ],
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              const SizedBox(width: 12),
              Builder(
                builder: (context) {
                  final isAi = _creationMethod == _TeamCreationMethod.ai;
                  final enabled = isAi
                      ? _canGenerate
                      : (_canCreate && !_generating);
                  return FilledButton(
                    onPressed: enabled
                        ? (isAi ? _generateAndCreate : _submit)
                        : null,
                    child: _generating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            isAi
                                ? l10n.teamGenButton
                                : l10n.homeWorkspaceCreateTeam,
                          ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatefulWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.badge,
    required this.badgeIsPrimary,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final String badge;
  final bool badgeIsPrimary;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final selected = widget.selected;
    final restingBg = cs.surfaceContainerHighest.withValues(alpha: 0.35);
    final hoverTint = cs.onSurface.withValues(alpha: 0.06);

    final Color borderColor = selected
        ? cs.primary
        : _hovered
        ? cs.primary.withValues(alpha: 0.45)
        : cs.outlineVariant.withValues(alpha: 0.6);
    final Color background = selected
        ? cs.primary.withValues(alpha: 0.07)
        : _hovered
        ? Color.alphaBlend(hoverTint, restingBg)
        : restingBg;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      hitTestBehavior: HitTestBehavior.opaque,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: selected ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    widget.icon,
                    size: context.tpIconSizes.lg,
                    color: selected ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: styles.lgBoldSnugColored(cs.onSurface),
                    ),
                  ),
                  _Badge(label: widget.badge, primary: widget.badgeIsPrimary),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                widget.description,
                style: styles.smColored(cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.primary});

  final String label;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final Color fg = primary ? cs.tertiary : cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: styles.xsSemiboldColored(fg),
      ),
    );
  }
}

class _NativeTeamOptionsCard extends StatelessWidget {
  const _NativeTeamOptionsCard({
    required this.cli,
    required this.providerId,
    required this.onCliChanged,
    required this.onProviderChanged,
  });

  final CliTool cli;
  final String providerId;
  final ValueChanged<CliTool> onCliChanged;
  final ValueChanged<String?> onProviderChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final registry = CliToolRegistryScope.of(context);
    final nativeTeamClis = registry.nativeTeamLaunchable.toList()
      ..sort((a, b) => a.id.value.compareTo(b.id.value));
    final catalogCli =
        registry.capability<ProviderCatalogCapability>(cli) != null
        ? cli
        : null;
    final providers = catalogCli == null
        ? const <AppProviderConfig>[]
        : context.watch<AppProviderCubit>().state.providersFor(catalogCli);
    final providerEntries = [
      ('', l10n.selectProvider),
      for (final provider in providers) (provider.id, provider.name),
    ];
    final effectiveProviderId =
        providerId.isNotEmpty && providers.any((p) => p.id == providerId)
        ? providerId
        : '';

    return TpCard.outlined(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpPreferenceRow(
            title: l10n.teamCliLabel,
            subtitle: l10n.teamCliSubtitle,
            titleLeading: CliBrandIcon(cli: cli, size: 28, borderRadius: 7),
            trailing: TpCompactSelect<CliTool>(
              value: cli,
              entries: [
                for (final def in nativeTeamClis)
                  (def.id, cliDisplayName(def, l10n)),
              ],
              itemBuilder: cliDropdownItemBuilder(
                registry: registry,
                l10n: l10n,
              ),
              onChanged: (value) {
                if (value == null) return;
                onCliChanged(value);
              },
            ),
            showDividerBelow: catalogCli != null,
          ),
          if (catalogCli != null)
            TpPreferenceRow(
              title: l10n.provider,
              subtitle: l10n.appProviderTeamToolSubtitle,
              titleLeading:
                  providers
                      .where((p) => p.id == effectiveProviderId)
                      .map(
                        (p) => ProviderBrandIcon.fromConfig(
                          p,
                          size: 28,
                          borderRadius: 7,
                          showBorder: false,
                        ),
                      )
                      .firstOrNull ??
                  const SizedBox.shrink(),
              trailing: providerEntries.isEmpty
                  ? Text(
                      l10n.onboardingDefaultPresetEmpty,
                      style: TpTextStyles.of(context).mutedSm,
                    )
                  : TpCompactSelect<String>(
                      value: effectiveProviderId,
                      entries: providerEntries,
                      itemBuilder: providerDropdownItemBuilder(
                        providers: providers,
                        labelFor: (id) =>
                            providers
                                .where((p) => p.id == id)
                                .map((p) => p.name)
                                .firstOrNull ??
                            id,
                      ),
                      onChanged: onProviderChanged,
                    ),
              showDividerBelow: false,
            ),
        ],
      ),
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({required this.controller, required this.onSubmitted});

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  cs.primary,
                  Color.lerp(cs.primary, cs.tertiary, 0.6) ?? cs.primary,
                ],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.groups_2_rounded,
              size: context.tpIconSizes.lg,
              color: cs.onPrimary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.teamName,
                  style: styles.xsColored(cs.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: controller,
                  autofocus: true,
                  onSubmitted: onSubmitted,
                  style: styles.lgColored(cs.onSurface),
                  decoration: InputDecoration(
                    hintText: l10n.homeWorkspaceNewTeamNameHint,
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
