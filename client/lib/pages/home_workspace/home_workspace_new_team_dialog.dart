import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../cubits/team_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../models/default_team_roster.dart';
import '../../models/team_config.dart';
import '../../services/cli/registry/cli_display_name.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';

/// Large centered "create team" modal launched from the workspace sidebar's
/// "New Team" row. Mirrors the Apifox project-creation modal: centered title +
/// close, two big selectable mode cards (Native / Mixed), a named form row, and
/// a single primary create action. The chosen [TeamMode] is the headline
/// decision; the CLI backend defaults to [TeamCli.flashskyai].
Future<void> showHomeWorkspaceNewTeamDialog(
  BuildContext context,
  TeamCubit teamCubit,
) async {
  final l10n = context.l10n;
  final result =
      await showDialog<
        ({
          String name,
          TeamMode mode,
          TeamCli cli,
          Map<String, String> providerIdsByTool,
        })
      >(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        builder: (_) => const HomeWorkspaceNewTeamDialog(),
      );
  if (result == null || !context.mounted) return;
  await teamCubit.addTeam(
    result.name,
    cli: result.cli,
    teamMode: result.mode,
    providerIdsByTool: result.providerIdsByTool,
    members: DefaultTeamRoster.localized(
      l10n,
      joinedAt: DateTime.now().millisecondsSinceEpoch,
    ),
  );
}

class HomeWorkspaceNewTeamDialog extends StatefulWidget {
  const HomeWorkspaceNewTeamDialog({super.key});

  @override
  State<HomeWorkspaceNewTeamDialog> createState() =>
      _HomeWorkspaceNewTeamDialogState();
}

class _HomeWorkspaceNewTeamDialogState
    extends State<HomeWorkspaceNewTeamDialog> {
  late final TextEditingController _nameController;
  TeamMode _mode = TeamMode.native;
  TeamCli _cli = TeamCli.claude;
  String? _providerId;
  bool _canCreate = false;
  bool _didSeedProvider = false;

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
    _nameController.dispose();
    super.dispose();
  }

  void _syncCanCreate() {
    final canCreate = _nameController.text.trim().isNotEmpty;
    if (canCreate != _canCreate) setState(() => _canCreate = canCreate);
  }

  AppProviderCli? _providerCatalogCli(TeamCli cli) =>
      CliToolRegistryScope.maybeOf(
        context,
      )?.tryGet(cli.value)?.providerCatalogCli;

  void _syncDefaultProviderForCli(TeamCli cli) {
    final catalogCli = _providerCatalogCli(cli);
    if (catalogCli == null) {
      if (_providerId != null) setState(() => _providerId = null);
      return;
    }
    final appProviders = context.read<AppProviderCubit>().state;
    final providers = appProviders.providersFor(catalogCli);
    final global = appProviders.selectedProviderIdByCli[catalogCli];
    final next = global != null && providers.any((p) => p.id == global)
        ? global
        : providers.firstOrNull?.id;
    if (next != _providerId) setState(() => _providerId = next);
  }

  Map<String, String> _providerIdsByToolForSubmit() {
    if (_mode != TeamMode.native) return const {};
    final catalogCli = _providerCatalogCli(_cli);
    final providerId = _providerId?.trim() ?? '';
    if (catalogCli == null || providerId.isEmpty) return const {};
    return {catalogCli.value: providerId};
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop((
      name: name,
      mode: _mode,
      cli: _cli,
      providerIdsByTool: _providerIdsByToolForSubmit(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);

    final maxDialogHeight = MediaQuery.sizeOf(context).height * 0.92;

    return Dialog(
      backgroundColor: cs.workspaceCard,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 720, maxHeight: maxDialogHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(title: l10n.homeWorkspaceNewTeam),
              const SizedBox(height: 8),
              Text(
                l10n.homeWorkspaceNewTeamSubtitle,
                textAlign: TextAlign.center,
                style: styles.body.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
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
                        onTap: () => setState(() => _mode = TeamMode.native),
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
                        onTap: () => setState(() => _mode = TeamMode.mixed),
                      ),
                    ),
                  ],
                ),
              ),
              if (_mode == TeamMode.native) ...[
                const SizedBox(height: 20),
                _NativeTeamOptionsCard(
                  cli: _cli,
                  providerId: _providerId,
                  onCliChanged: (cli) {
                    setState(() => _cli = cli);
                    _syncDefaultProviderForCli(cli);
                  },
                  onProviderChanged: (id) => setState(() => _providerId = id),
                ),
              ],
              const SizedBox(height: 24),
              _NameField(
                controller: _nameController,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _canCreate ? _submit : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                    ),
                    child: Text(l10n.homeWorkspaceCreateTeam),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          title,
          style: styles.dialogTitle.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: IconButton(
            tooltip: context.l10n.cancel,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.close_rounded,
              size: AppIconSizes.md,
              color: cs.onSurfaceVariant,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final selected = widget.selected;

    final Color borderColor = selected
        ? cs.primary
        : cs.outlineVariant.withValues(alpha: _hovered ? 0.9 : 0.6);
    final Color background = selected
        ? cs.primary.withValues(alpha: 0.07)
        : _hovered
        ? cs.onSurface.withValues(alpha: 0.03)
        : cs.surfaceContainerHighest.withValues(alpha: 0.35);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
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
                    size: AppIconSizes.lg,
                    color: selected ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: styles.subtitle.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _Badge(label: widget.badge, primary: widget.badgeIsPrimary),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                widget.description,
                style: styles.bodySmall.copyWith(color: cs.onSurfaceVariant),
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
    final styles = AppTextStyles.of(context);
    final Color fg = primary ? cs.tertiary : cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: styles.caption.copyWith(color: fg, fontWeight: FontWeight.w600),
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

  final TeamCli cli;
  final String? providerId;
  final ValueChanged<TeamCli> onCliChanged;
  final ValueChanged<String?> onProviderChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final registry = CliToolRegistryScope.of(context);
    final launchable = registry.launchable.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final catalogCli = registry.tryGet(cli.value)?.providerCatalogCli;
    final providers = catalogCli == null
        ? const <AppProviderConfig>[]
        : context.watch<AppProviderCubit>().state.providersFor(catalogCli);
    final providerEntries = [
      for (final provider in providers) (provider.id, provider.name),
    ];
    final effectiveProviderId =
        providerId != null && providers.any((p) => p.id == providerId)
        ? providerId!
        : providers.firstOrNull?.id ?? '';

    return SettingsSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsLabeledRow(
            title: l10n.teamCliLabel,
            subtitle: l10n.teamCliSubtitle,
            trailing: SettingsCompactDropdown<TeamCli>(
              value: cli,
              entries: [
                for (final def in launchable)
                  (TeamCli.decode(def.id), cliDisplayName(def, l10n)),
              ],
              onChanged: (value) {
                if (value == null) return;
                onCliChanged(value);
              },
            ),
            showDividerBelow: catalogCli != null,
          ),
          if (catalogCli != null)
            SettingsLabeledRow(
              title: l10n.provider,
              subtitle: l10n.appProviderTeamToolSubtitle,
              trailing: providerEntries.isEmpty
                  ? Text(
                      l10n.onboardingDefaultProviderEmpty,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  : SettingsCompactDropdown<String>(
                      value: effectiveProviderId,
                      entries: providerEntries,
                      onChanged: (value) {
                        if (value == null) return;
                        onProviderChanged(value);
                      },
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
    final styles = AppTextStyles.of(context);
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
              size: AppIconSizes.lg,
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
                  style: styles.caption.copyWith(color: cs.onSurfaceVariant),
                ),
                TextField(
                  controller: controller,
                  autofocus: true,
                  onSubmitted: onSubmitted,
                  style: styles.prominent.copyWith(color: cs.onSurface),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    hintText: l10n.homeWorkspaceNewTeamNameHint,
                    hintStyle: styles.prominent.copyWith(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
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
