import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/remote_download_catalog_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../l10n/app_localizations.dart';
import '../../services/remote_download/remote_download_source.dart';
import '../../widgets/settings/workspace_hub_shell.dart';

class DownloadSourcesConfigWorkspace extends StatefulWidget {
  const DownloadSourcesConfigWorkspace({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  State<DownloadSourcesConfigWorkspace> createState() =>
      _DownloadSourcesConfigWorkspaceState();
}

class _DownloadSourcesConfigWorkspaceState
    extends State<DownloadSourcesConfigWorkspace> {
  final _mirrorController = TextEditingController();
  var _saving = false;
  var _restoring = false;

  var _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final cubit = context.read<RemoteDownloadCatalogCubit>();
    _syncMirrorField(cubit.state.mirrorBaseUrl);
    if (!cubit.state.loaded) {
      unawaited(cubit.load());
    }
  }

  @override
  void dispose() {
    _mirrorController.dispose();
    super.dispose();
  }

  void _syncMirrorField(String? mirrorBaseUrl) {
    final text = mirrorBaseUrl ?? '';
    if (_mirrorController.text != text) {
      _mirrorController.text = text;
    }
  }

  Future<void> _saveMirror(RemoteDownloadCatalogCubit cubit) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final trimmed = _mirrorController.text.trim();
      await cubit.setMirrorBaseUrl(trimmed.isEmpty ? null : trimmed);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _restoreDefaults(RemoteDownloadCatalogCubit cubit) async {
    if (_restoring) return;
    setState(() => _restoring = true);
    try {
      await cubit.restoreDefaults();
      _syncMirrorField(null);
    } finally {
      if (mounted) {
        setState(() => _restoring = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocConsumer<RemoteDownloadCatalogCubit, RemoteDownloadCatalogState>(
      listenWhen: (previous, current) =>
          previous.mirrorBaseUrl != current.mirrorBaseUrl,
      listener: (context, state) => _syncMirrorField(state.mirrorBaseUrl),
      builder: (context, state) {
        final cubit = context.read<RemoteDownloadCatalogCubit>();
        final sources = state.catalog.enabledSorted();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showHeading) ...[
              WorkspaceSectionHeading(
                title: l10n.downloadSourcesSettingsTitle,
                subtitle: l10n.downloadSourcesSettingsSubtitle,
              ),
              const SizedBox(height: 16),
            ],
            Expanded(
              child: SingleChildScrollView(
                child: TpCard.outlined(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TpSectionHeader(
                        title: l10n.downloadSourcesEnabledSources,
                      ),
                      for (final source in sources)
                        _SourceRow(source: source, l10n: l10n),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: Text(
                          l10n.downloadSourcesMirrorBaseUrl,
                          style: TpTextStyles.of(context).smMedium,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                        child: TextFormField(
                          controller: _mirrorController,
                          decoration: InputDecoration(
                            hintText: l10n.downloadSourcesMirrorHint,
                          ),
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => unawaited(_saveMirror(cubit)),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TpButton(
                              onPressed: _saving
                                  ? null
                                  : () => unawaited(_saveMirror(cubit)),
                              child: _saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(l10n.downloadSourcesSave),
                            ),
                            TpButton(
                              variant: TpButtonVariant.outline,
                              onPressed: _restoring
                                  ? null
                                  : () => unawaited(_restoreDefaults(cubit)),
                              child: Text(l10n.downloadSourcesRestoreDefaults),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source, required this.l10n});

  final RemoteDownloadSource source;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rewriteLabel = source.rewriteOrigin ?? l10n.downloadSourcesIdentity;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(source.id, style: TpTextStyles.of(context).smMedium),
          const SizedBox(height: 4),
          Text(
            source.matchHosts.join(', '),
            style: TpTextStyles.of(context).smMediumColored(
              scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            rewriteLabel,
            style: TpTextStyles.of(context).smMediumColored(
              scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
