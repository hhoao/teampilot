import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/skill_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/skill_registry_source.dart';
import '../../services/skill/registry/api_registry_source.dart';
import '../../services/skill/registry/git_repo_registry_source.dart';
import '../../services/skill/registry/skill_registry_source.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/debounce/button_callbacks.dart';
import '../../widgets/app_toast/app_toast.dart';
import '../../widgets/workspace_library_card.dart';
import 'skill_management_cards.dart';

class SkillRegistriesSection extends StatefulWidget {
  const SkillRegistriesSection({super.key});

  @override
  State<SkillRegistriesSection> createState() => _SkillRegistriesSectionState();
}

class _SkillRegistriesSectionState extends State<SkillRegistriesSection> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<SkillCubit, SkillState>(
      builder: (context, state) {
        return SingleChildScrollView(
          child: WorkspaceLibraryCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TpCardHeader(title: l10n.skillsNavRegistries),
                const SizedBox(height: 12),
                for (final source in state.sources)
                  _RegistryRow(
                    source: source,
                    syncing: source is GitRepoRegistrySource &&
                        state.repoSyncingKeys.contains(
                          '${source.gitRepo.owner}__${source.gitRepo.name}',
                        ),
                    onToggle: (v) => context
                        .read<SkillCubit>()
                        .toggleRegistrySource(source.id, v),
                    onEdit: () => _editSource(context, source),
                    onReset: () => _resetSource(context, source),
                  ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: throttledAsync('skill_add_registry', () =>
                        _addSourceDialog(context)),
                    icon: Icon(Icons.add, size: context.tpIconSizes.md),
                    label: Text(l10n.skillsRegistryAddSource),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  SkillRegistrySourceConfig _configOf(SkillRegistrySource source) {
    if (source is ApiRegistrySource) return source.config;
    if (source is GitRepoRegistrySource) return source.config;
    return SkillRegistriesConfig.defaults().sources.first;
  }

  Future<void> _editSource(
    BuildContext context,
    SkillRegistrySource source,
  ) async {
    final result = await showDialog<SkillRegistrySourceConfig>(
      context: context,
      builder: (ctx) => _RegistryEditDialog(
        config: _configOf(source),
        onTest: () async {
          final cubit = context.read<SkillCubit>();
          final ok = await cubit.testRegistryConnection(source.id);
          if (!ctx.mounted) return ok;
          AppToast.show(
            ctx,
            message: ok
                ? ctx.l10n.skillsRegistryTestOk
                : ctx.l10n.skillsRegistryTestFailed('connection'),
            variant: ok ? TpToastVariant.success : TpToastVariant.error,
          );
          return ok;
        },
      ),
    );
    if (result == null || !mounted) return;
    await context.read<SkillCubit>().updateRegistrySource(result);
  }

  Future<void> _resetSource(
    BuildContext context,
    SkillRegistrySource source,
  ) async {
    final l10n = context.l10n;
    final isBuiltIn = source.id == 'skillsSh' || source.id == 'skillsMp';
    final cfg = _configOf(source);
    final title = isBuiltIn ? l10n.skillsRegistryRemoveTitle : l10n.skillsRemove;
    final message = isBuiltIn
        ? l10n.skillsRegistryResetConfirm(cfg.label)
        : l10n.skillsRepoRemoveConfirm(cfg.label);
    final ok = await skillConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: isBuiltIn ? l10n.confirm : l10n.skillsRemove,
      destructive: !isBuiltIn,
    );
    if (ok != true || !mounted) return;
    if (isBuiltIn) {
      final defaults = SkillRegistriesConfig.defaults().byId(cfg.id)!;
      await context
          .read<SkillCubit>()
          .updateRegistrySource(cfg.copyWith(
            label: defaults.label,
            baseUrl: defaults.baseUrl,
            browseQuery: defaults.browseQuery,
            clearApiToken: true,
          ));
    } else {
      await context.read<SkillCubit>().removeRegistrySource(cfg.id);
    }
  }

  Future<void> _addSourceDialog(BuildContext context) async {
    final l10n = context.l10n;
    final kind = await showDialog<SkillRegistryKind>(
      context: context,
      builder: (ctx) => TpDialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(title: l10n.skillsRegistryAddSource),
            const SizedBox(height: 16),
            _DialogListTile(
              icon: Icons.dns_outlined,
              title: l10n.skillsRegistrySourceKindApi,
              onTap: () => Navigator.pop(ctx, SkillRegistryKind.api),
            ),
            _DialogListTile(
              icon: Icons.source_outlined,
              title: l10n.skillsRegistrySourceKindGit,
              onTap: () => Navigator.pop(ctx, SkillRegistryKind.gitRepo),
            ),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;
    if (kind == SkillRegistryKind.gitRepo) {
      await _addGitSourceDialog(context);
    } else {
      await _addApiSourceDialog(context);
    }
  }

  Future<void> _addGitSourceDialog(BuildContext context) async {
    final l10n = context.l10n;
    final saved = await showDialog<String?>(
      context: context,
      builder: (ctx) => _AddGitSourceDialog(l10n: l10n),
    );
    if (saved == null || !mounted) return;
    final parts = saved.split('/');
    final id = 'git-${parts[0]}-${parts[1]}';
    if (context.read<SkillCubit>().state.registriesConfig.byId(id) != null) {
      AppToast.show(context, message: l10n.skillsRepoInvalidUrl, variant: TpToastVariant.error);
      return;
    }
    await context.read<SkillCubit>().addRegistrySource(
      SkillRegistrySourceConfig(
        id: id,
        kind: SkillRegistryKind.gitRepo,
        label: '${parts[0]}/${parts[1]}',
        gitOwner: parts[0],
        gitName: parts[1],
        gitBranch: parts[2],
      ),
    );
  }

  Future<void> _addApiSourceDialog(BuildContext context) async {
    final l10n = context.l10n;
    final protocol = await showDialog<SkillRegistryProtocol>(
      context: context,
      builder: (ctx) => TpDialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(title: l10n.skillsRegistryProtocolLabel),
            const SizedBox(height: 16),
            _DialogListTile(
              icon: Icons.cloud_outlined,
              title: l10n.skillsRegistryProtocolSkillsSh,
              onTap: () => Navigator.pop(ctx, SkillRegistryProtocol.skillsSh),
            ),
            _DialogListTile(
              icon: Icons.cloud_outlined,
              title: l10n.skillsRegistryProtocolSkillsMp,
              onTap: () => Navigator.pop(ctx, SkillRegistryProtocol.skillsMp),
            ),
          ],
        ),
      ),
    );
    if (protocol == null || !mounted) return;
    final result = await showDialog<SkillRegistrySourceConfig>(
      context: context,
      builder: (ctx) => _AddApiSourceFormDialog(protocol: protocol, l10n: l10n),
    );
    if (result == null || !mounted) return;
    await context.read<SkillCubit>().addRegistrySource(result);
  }
}

/// Plain clickable row inside a [TpDialog] (ListTile-style without the
/// ListTile dependency).
class _DialogListTile extends StatelessWidget {
  const _DialogListTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: context.tpIconSizes.md),
            const SizedBox(width: 12),
            Expanded(child: Text(title)),
          ],
        ),
      ),
    );
  }
}

class _AddGitSourceDialog extends StatefulWidget {
  const _AddGitSourceDialog({required this.l10n});

  final AppLocalizations l10n;

  @override
  State<_AddGitSourceDialog> createState() => _AddGitSourceDialogState();
}

class _AddGitSourceDialogState extends State<_AddGitSourceDialog> {
  late final TextEditingController _ownerCtl;
  late final TextEditingController _nameCtl;
  late final TextEditingController _branchCtl;

  @override
  void initState() {
    super.initState();
    _ownerCtl = TextEditingController();
    _nameCtl = TextEditingController();
    _branchCtl = TextEditingController(text: 'main');
  }

  @override
  void dispose() {
    _ownerCtl.dispose();
    _nameCtl.dispose();
    _branchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return TpDialog(
      maxWidth: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(title: l10n.skillsRegistrySourceKindGit),
          const SizedBox(height: 16),
          TextField(
            controller: _ownerCtl,
            decoration: InputDecoration(labelText: l10n.skillsRegistryOwnerLabel),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtl,
            decoration: InputDecoration(labelText: l10n.skillsRegistryNameOfRepoLabel),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _branchCtl,
            decoration: InputDecoration(labelText: l10n.skillsRepoBranch),
          ),
          TpDialogActions(
            children: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
              FilledButton(
                onPressed: () {
                  final owner = _ownerCtl.text.trim();
                  final name = _nameCtl.text.trim();
                  if (owner.isEmpty || name.isEmpty) return;
                  Navigator.pop(
                    context,
                    '$owner/$name/${_branchCtl.text.trim().isEmpty ? 'main' : _branchCtl.text.trim()}',
                  );
                },
                child: Text(l10n.save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddApiSourceFormDialog extends StatefulWidget {
  const _AddApiSourceFormDialog({required this.protocol, required this.l10n});

  final SkillRegistryProtocol protocol;
  final AppLocalizations l10n;

  @override
  State<_AddApiSourceFormDialog> createState() => _AddApiSourceFormDialogState();
}

class _AddApiSourceFormDialogState extends State<_AddApiSourceFormDialog> {
  late final TextEditingController _labelCtl;
  late final TextEditingController _urlCtl;
  late final TextEditingController _browseCtl;

  @override
  void initState() {
    super.initState();
    _labelCtl = TextEditingController();
    _urlCtl = TextEditingController(
      text: SkillRegistrySourceConfig.defaultBaseUrl(widget.protocol),
    );
    _browseCtl = TextEditingController(
      text: widget.protocol == SkillRegistryProtocol.skillsSh ? 'ai' : '',
    );
  }

  @override
  void dispose() {
    _labelCtl.dispose();
    _urlCtl.dispose();
    _browseCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final protocol = widget.protocol;
    return TpDialog(
      maxWidth: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(title: l10n.skillsRegistryAddSource),
          const SizedBox(height: 16),
          TextField(
            controller: _labelCtl,
            decoration: InputDecoration(labelText: l10n.skillsRegistryNameLabel),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlCtl,
            decoration: InputDecoration(
              labelText: l10n.skillsRegistryBaseUrlLabel,
              hintText: SkillRegistrySourceConfig.defaultBaseUrl(protocol),
            ),
          ),
          if (protocol == SkillRegistryProtocol.skillsSh) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _browseCtl,
              decoration: InputDecoration(labelText: l10n.skillsRegistryBrowseQueryLabel),
            ),
          ],
          TpDialogActions(
            children: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
              FilledButton(
                onPressed: () {
                  final label = _labelCtl.text.trim();
                  if (label.isEmpty) return;
                  final url = _urlCtl.text.trim();
                  final now = DateTime.now().microsecondsSinceEpoch;
                  Navigator.pop(
                    context,
                    SkillRegistrySourceConfig(
                      id: 'custom-$now',
                      kind: SkillRegistryKind.api,
                      label: label,
                      protocol: protocol,
                      baseUrl: url.isEmpty ? null : url,
                      browseQuery: protocol == SkillRegistryProtocol.skillsSh
                          ? (_browseCtl.text.trim().isEmpty ? 'ai' : _browseCtl.text.trim())
                          : null,
                    ),
                  );
                },
                child: Text(l10n.save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RegistryRow extends StatelessWidget {
  const _RegistryRow({
    required this.source,
    required this.syncing,
    required this.onToggle,
    required this.onEdit,
    required this.onReset,
  });

  final SkillRegistrySource source;
  final bool syncing;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final textBase = cs.onSurface;
    final cfg = source is ApiRegistrySource
        ? (source as ApiRegistrySource).config
        : (source as GitRepoRegistrySource).config;
    final subtitle = source is GitRepoRegistrySource
        ? '@${(source as GitRepoRegistrySource).gitRepo.branch}'
        : (cfg.hasApiToken
              ? '@${source.label} · ${l10n.skillsRegistryApiKeySet}'
              : '@${source.label}');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TpHover(
        backgroundColor: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        onTap: onEdit,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: workspaceInsetDecoration(cs, radius: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source is GitRepoRegistrySource
                          ? (source as GitRepoRegistrySource).gitRepo.githubUrl
                          : cfg.baseUrlOrDefault,
                      style: TpTextStyles.of(context).mdSemiboldColored(textBase),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TpTextStyles.of(
                        context,
                      ).xsColored(textBase.withValues(alpha: 0.55)),
                    ),
                  ],
                ),
              ),
              if (syncing) ...[
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
              ],
              Switch(value: source.enabled, onChanged: onToggle),
              IconButton(
                tooltip: source.id == 'skillsSh' || source.id == 'skillsMp'
                    ? l10n.skillsRegistryRemoveTitle
                    : l10n.skillsRemove,
                onPressed: onReset,
                icon: Icon(
                  Icons.delete_outline,
                  size: context.tpIconSizes.md,
                  color: cs.error,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegistryEditDialog extends StatefulWidget {
  const _RegistryEditDialog({required this.config, required this.onTest});
  final SkillRegistrySourceConfig config;
  final Future<bool> Function() onTest;

  @override
  State<_RegistryEditDialog> createState() => _RegistryEditDialogState();
}

class _RegistryEditDialogState extends State<_RegistryEditDialog> {
  late final TextEditingController _labelCtl;
  late final TextEditingController _urlCtl;
  late final TextEditingController _tokenCtl;
  late final TextEditingController _browseCtl;
  late final TextEditingController _ownerCtl;
  late final TextEditingController _nameCtl;
  late final TextEditingController _branchCtl;
  bool _testing = false;

  bool get _isApi => widget.config.kind == SkillRegistryKind.api;

  @override
  void initState() {
    super.initState();
    _labelCtl = TextEditingController(text: widget.config.label);
    _urlCtl = TextEditingController(
      text: widget.config.baseUrlOrDefault == '' ? '' : widget.config.baseUrlOrDefault,
    );
    _tokenCtl = TextEditingController(text: widget.config.apiToken ?? '');
    _browseCtl = TextEditingController(text: widget.config.browseQuery ?? '');
    _ownerCtl = TextEditingController(text: widget.config.gitOwner ?? '');
    _nameCtl = TextEditingController(text: widget.config.gitName ?? '');
    _branchCtl = TextEditingController(text: widget.config.gitBranch ?? 'main');
  }

  @override
  void dispose() {
    _labelCtl.dispose(); _urlCtl.dispose(); _tokenCtl.dispose();
    _browseCtl.dispose(); _ownerCtl.dispose(); _nameCtl.dispose(); _branchCtl.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    try {
      await widget.onTest();
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _save() {
    if (_isApi) {
      final label = _labelCtl.text.trim();
      final url = _urlCtl.text.trim();
      final token = _tokenCtl.text.trim();
      final browse = _browseCtl.text.trim();
      Navigator.pop(
        context,
        widget.config.copyWith(
          label: label.isEmpty ? widget.config.label : label,
          baseUrl: url,
          clearBaseUrl: url.isEmpty,
          apiToken: token,
          clearApiToken: token.isEmpty,
          browseQuery: browse,
          clearBrowseQuery: browse.isEmpty,
        ),
      );
    } else {
      Navigator.pop(
        context,
        widget.config.copyWith(
          label: _labelCtl.text.trim().isEmpty ? widget.config.label : _labelCtl.text.trim(),
          gitOwner: _ownerCtl.text.trim(),
          gitName: _nameCtl.text.trim(),
          gitBranch: _branchCtl.text.trim().isEmpty ? 'main' : _branchCtl.text.trim(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TpDialog(
      maxWidth: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(title: l10n.skillsRegistryEditTitle),
          const SizedBox(height: 16),
          TextField(controller: _labelCtl, decoration: InputDecoration(labelText: l10n.skillsRegistryNameLabel)),
          if (_isApi) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _urlCtl,
              decoration: InputDecoration(
                labelText: l10n.skillsRegistryBaseUrlLabel,
                hintText: SkillRegistrySourceConfig.defaultBaseUrl(widget.config.protocol ?? SkillRegistryProtocol.skillsSh),
              ),
            ),
            if (widget.config.protocol == SkillRegistryProtocol.skillsMp) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _tokenCtl,
                obscureText: true,
                autocorrect: false,
                decoration: InputDecoration(labelText: l10n.skillsRegistryTokenLabel),
              ),
            ],
            if (widget.config.protocol == SkillRegistryProtocol.skillsSh) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _browseCtl,
                decoration: InputDecoration(labelText: l10n.skillsRegistryBrowseQueryLabel),
              ),
            ],
          ] else ...[
            const SizedBox(height: 12),
            TextField(controller: _ownerCtl, decoration: InputDecoration(labelText: l10n.skillsRegistryOwnerLabel)),
            const SizedBox(height: 12),
            TextField(controller: _nameCtl, decoration: InputDecoration(labelText: l10n.skillsRegistryNameOfRepoLabel)),
            const SizedBox(height: 12),
            TextField(controller: _branchCtl, decoration: InputDecoration(labelText: l10n.skillsRepoBranch)),
          ],
          TpDialogActions(
            children: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
              if (_isApi)
                TextButton(
                  onPressed: _testing ? null : _test,
                  child: _testing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l10n.mcpRepoTestConnection),
                ),
              FilledButton(onPressed: _save, child: Text(l10n.save)),
            ],
          ),
        ],
      ),
    );
  }
}
