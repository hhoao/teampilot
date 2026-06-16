import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/member_config_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/team_config.dart';
import '../../../services/cli/member_config/member_config_detail.dart';
import '../../../services/io/sftp_filesystem.dart';
import '../../../services/io/system_folder_opener.dart';
import '../../../services/storage/runtime_storage_context.dart';
import '../home_workspace_content_header.dart';
import '../../../widgets/app_dialog.dart';

/// Opens the read-only member config detail dialog.
Future<void> showMemberDetailDialog(
  BuildContext context, {
  required String projectId,
  required String sessionId,
  required TeamConfig team,
  required TeamMemberConfig member,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => BlocProvider(
      create: (_) =>
          MemberConfigCubit()
            ..load(
              projectId: projectId,
              sessionId: sessionId,
              team: team,
              member: member,
            ),
      child: _MemberDetailDialog(memberName: member.name),
    ),
  );
}

class _MemberDetailDialog extends StatelessWidget {
  const _MemberDetailDialog({required this.memberName});
  final String memberName;

  bool get _canRevealLocally =>
      RuntimeStorageContext.current.filesystem is! SftpFilesystem;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MemberConfigCubit>().state;
    final l10n = context.l10n;

    Widget body;
    switch (state.status) {
      case MemberConfigStatus.loaded:
        final detail = state.detail!;
        body = MemberDetailDialogBody(
          memberName: memberName,
          detail: detail,
          onOpenInFileManager:
              (_canRevealLocally && detail.resolvedDir.isNotEmpty)
              ? () => SystemFolderOpener().reveal(detail.resolvedDir)
              : null,
        );
      case MemberConfigStatus.error:
        body = Center(child: Text(l10n.memberDetailLoadError));
      case MemberConfigStatus.idle:
      case MemberConfigStatus.loading:
        body = const Center(child: CircularProgressIndicator());
    }

    return AppDialog(maxWidth: 840, maxHeight: 720, child: body);
  }
}

/// Pure presentational body (no cubit) so it is trivially widget-testable.
class MemberDetailDialogBody extends StatefulWidget {
  const MemberDetailDialogBody({
    required this.memberName,
    required this.detail,
    this.onOpenInFileManager,
    super.key,
  });

  final String memberName;
  final MemberConfigDetail detail;
  final VoidCallback? onOpenInFileManager;

  @override
  State<MemberDetailDialogBody> createState() => _MemberDetailDialogBodyState();
}

class _MemberDetailDialogBodyState extends State<MemberDetailDialogBody> {
  int _selectedTabIndex = 0;

  bool _hasWarning(String section) =>
      widget.detail.warnings.any((w) => w.section == section);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final detail = widget.detail;

    if (!detail.hasConfig) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: l10n.memberDetailTitle),
          const SizedBox(height: 24),
          Text(l10n.memberDetailEmpty, textAlign: TextAlign.center),
        ],
      );
    }

    final tabs = <String>[
      l10n.memberDetailTabOverview,
      l10n.memberDetailTabSkills,
      l10n.memberDetailTabMcp,
      l10n.memberDetailTabPlugins,
      l10n.memberDetailTabSettings,
    ];

    Widget tabContent;
    switch (_selectedTabIndex) {
      case 0:
        tabContent = _OverviewTab(detail: detail);
      case 1:
        tabContent = _ListTab(
          empty: l10n.memberDetailSectionEmpty,
          hasWarning: _hasWarning('skills'),
          items: [
            for (final s in detail.skills)
              (title: s.name, subtitle: s.description),
          ],
        );
      case 2:
        tabContent = _ListTab(
          empty: l10n.memberDetailSectionEmpty,
          hasWarning: _hasWarning('mcp'),
          items: [
            for (final m in detail.mcpServers)
              (title: m.name, subtitle: m.summary),
          ],
        );
      case 3:
        tabContent = _ListTab(
          empty: l10n.memberDetailSectionEmpty,
          hasWarning: _hasWarning('plugins'),
          items: [
            for (final pl in detail.plugins)
              (title: pl.name, subtitle: pl.version),
          ],
        );
      case 4:
        tabContent = _ListTab(
          empty: l10n.memberDetailSectionEmpty,
          hasWarning: _hasWarning('settings'),
          items: [
            for (final e in detail.settings) (title: e.key, subtitle: e.value),
          ],
        );
      default:
        tabContent = const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDialogHeader(
          title: '${l10n.memberDetailTitle} · ${widget.memberName}',
          showDividerBelow: false,
        ),
        HomeWorkspaceContentTabBar(
          tabs: tabs,
          selectedIndex: _selectedTabIndex,
          onSelect: (i) => setState(() => _selectedTabIndex = i),
        ),
        Divider(
          height: 1,
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        Expanded(
          child: tabContent
              .animate(key: ValueKey('member-detail-tab-$_selectedTabIndex'))
              .fadeIn(duration: 180.ms, curve: Curves.easeOut)
              .slideX(
                begin: 0.025,
                end: 0,
                duration: 220.ms,
                curve: Curves.easeOutCubic,
              ),
        ),
        if (widget.onOpenInFileManager != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.folder_open, size: 18),
                label: Text(l10n.memberDetailOpenInFileManager),
                onPressed: widget.onOpenInFileManager,
              ),
            ),
          ),
      ],
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.detail});
  final MemberConfigDetail detail;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final source = detail.sourceLayer == MemberConfigSourceLayer.team
        ? l10n.memberDetailSourceTeam
        : l10n.memberDetailSourceRuntime;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (detail.sourceLayer == MemberConfigSourceLayer.team)
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                source,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        const SizedBox(height: 8),
        _kv(context, 'CLI', detail.cli.value),
        if (detail.provider.isNotEmpty)
          _kv(context, 'Provider', detail.provider),
        if (detail.model.isNotEmpty) _kv(context, 'Model', detail.model),
        _kv(context, 'CONFIG_DIR', detail.resolvedDir),
      ],
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              k,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: SelectableText(v, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _ListTab extends StatelessWidget {
  const _ListTab({
    required this.items,
    required this.empty,
    this.hasWarning = false,
  });
  final List<({String title, String subtitle})> items;
  final String empty;
  final bool hasWarning;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final content = items.isEmpty
        ? Center(child: Text(empty, style: theme.textTheme.bodyMedium))
        : ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(items[i].title, style: theme.textTheme.bodyMedium),
              subtitle: items[i].subtitle.isEmpty
                  ? null
                  : Text(
                      items[i].subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
            ),
          );
    if (!hasWarning) return content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cs.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: cs.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.memberDetailLoadError,
                  style: TextStyle(color: cs.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: content),
      ],
    );
  }
}
