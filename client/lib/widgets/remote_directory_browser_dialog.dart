import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/l10n_extensions.dart';
import '../utils/logger.dart';
import '../services/storage/remote_directory_browser.dart';
import '../services/storage/workspace_directory_picker.dart';
import '../theme/app_icon_sizes.dart';
import 'app_dialog.dart';

/// SFTP-backed remote directory browser. Resolves the [targetId]'s filesystem
/// via [WorkspaceDirectoryPicker], navigates with [RemoteDirectoryBrowser], and
/// returns the chosen (or hand-typed) absolute path via [Navigator.pop].
///
/// Connecting to a remote can throw; failures are surfaced inline while the
/// hand-fill field below stays usable as a fallback.
class RemoteDirectoryBrowserDialog extends StatefulWidget {
  const RemoteDirectoryBrowserDialog({super.key, required this.targetId});

  final String targetId;

  @override
  State<RemoteDirectoryBrowserDialog> createState() =>
      _RemoteDirectoryBrowserDialogState();
}

class _RemoteDirectoryBrowserDialogState
    extends State<RemoteDirectoryBrowserDialog> {
  final _handFillController = TextEditingController(text: '~/');
  RemoteDirectoryBrowser? _browser;
  RemoteDirectoryListing? _listing;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _handFillController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final picker = context.read<WorkspaceDirectoryPicker>();
    try {
      final fs = await picker.filesystemFor(widget.targetId);
      final browser = RemoteDirectoryBrowser(fs);
      final initial = await browser.resolveInitial(null);
      final listing = await browser.list(initial);
      if (!mounted) return;
      setState(() {
        _browser = browser;
        _listing = listing;
        _loading = false;
        _error = null;
      });
    } catch (error, stackTrace) {
      appLogger.e(
        'Failed to initialize remote directory browser',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.l10n.remoteDirectoryBrowserError;
      });
    }
  }

  Future<void> _open(String path) async {
    final browser = _browser;
    if (browser == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listing = await browser.list(path);
      if (!mounted) return;
      setState(() {
        _listing = listing;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.l10n.remoteDirectoryBrowserError;
      });
    }
  }

  void _useCurrent() {
    final path = _listing?.path;
    if (path == null) return;
    Navigator.of(context).pop(path);
  }

  void _submitHandFill() {
    final text = _handFillController.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final listing = _listing;

    return AppDialog(
      maxWidth: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: l10n.remoteDirectoryBrowserTitle),
          const SizedBox(height: 16),
          Row(
            children: [
              IconButton(
                tooltip: l10n.remoteDirectoryBrowserUpOneLevel,
                icon: Icon(
                  Icons.arrow_upward_rounded,
                  size: context.appIconSizes.md,
                ),
                onPressed:
                    listing != null && listing.parent != null && !_loading
                    ? () => _open(listing.parent!)
                    : null,
              ),
              Expanded(
                child: SelectableText(
                  listing?.path ?? '…',
                  maxLines: 1,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(height: 240, child: _buildBody(theme, l10n)),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            l10n.remoteDirectoryBrowserTypePathLabel,
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _handFillController,
                  decoration: InputDecoration(
                    hintText: l10n.remoteDirectoryBrowserTypePathHint,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submitHandFill(),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _submitHandFill,
                child: Text(l10n.remoteDirectoryBrowserUseTypedPath),
              ),
            ],
          ),
          AppDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: listing != null && !_loading ? _useCurrent : null,
                child: Text(l10n.remoteDirectoryBrowserUseThisDirectory),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme, AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final listing = _listing;
    if (listing == null) {
      return Center(
        child: Text(
          l10n.remoteDirectoryBrowserError,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (listing.directories.isEmpty) {
      return Center(
        child: Text(
          l10n.remoteDirectoryBrowserEmpty,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: listing.directories.length,
        itemBuilder: (context, index) {
          final name = listing.directories[index];
          return ListTile(
            leading: Icon(Icons.folder_outlined, size: context.appIconSizes.md),
            title: Text(name),
            trailing: Icon(
              Icons.chevron_right_rounded,
              size: context.appIconSizes.md,
            ),
            onTap: () => _open(_browser!.child(listing.path, name)),
          );
        },
      ),
    );
  }
}
