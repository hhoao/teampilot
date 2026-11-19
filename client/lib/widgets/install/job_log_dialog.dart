import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/install/install_job_registry.dart';
import '../../services/install/job_log_store.dart';
import '../../theme/app_fonts.dart';

Future<void> showInstallJobLogDialog(
  BuildContext context, {
  required String token,
  required String title,
}) {
  final store = context.read<InstallJobRegistry>().logs;
  return showTpDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => JobLogDialog(token: token, title: title, store: store),
  );
}

class JobLogDialog extends StatefulWidget {
  const JobLogDialog({
    required this.token,
    required this.title,
    this.store,
    super.key,
  });

  final String token;
  final String title;
  final JobLogStore? store;

  @override
  State<JobLogDialog> createState() => _JobLogDialogState();
}

class _JobLogDialogState extends State<JobLogDialog> {
  final _scroll = ScrollController();
  final _lines = <String>[];
  StreamSubscription<String>? _sub;
  bool _following = true;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    final store = widget.store;
    if (store == null) {
      _unavailable = true;
      return;
    }
    if (!store.isLive(widget.token)) {
      unawaited(_loadStatic(store));
      return;
    }
    _sub = store
        .follow(widget.token)
        .listen(
          (line) {
            if (!mounted) return;
            setState(() => _lines.add(line));
            _scrollToEnd();
          },
          onDone: () => unawaited(_loadStatic(store)),
          onError: (_) => unawaited(_loadStatic(store)),
        );
  }

  Future<void> _loadStatic(JobLogStore store) async {
    final lines = await store.read(widget.token);
    if (!mounted) return;
    setState(() {
      _lines
        ..clear()
        ..addAll(lines);
      _unavailable = lines.isEmpty;
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    if (!_following) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n.log;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final logStyle = appMonoTextStyle(
      context,
      base: styles.sm,
      height: 1.35,
      color: cs.onSurfaceVariant,
    );

    return TpDialog(
      maxWidth: 760,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(
            title: l10n.installJobTitle,
            closeTooltip: context.l10n.windowControlClose,
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 8),
          Text(widget.title, style: styles.mutedSm),
          const SizedBox(height: 8),
          Flexible(
            fit: FlexFit.loose,
            child: Container(
              height: 420,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.all(8),
              child: _unavailable
                  ? Center(
                      child: Text(
                        l10n.installJobUnavailable,
                        style: styles.mutedMd,
                      ),
                    )
                  : _lines.isEmpty
                  ? Center(
                      child: Text(l10n.installJobEmpty, style: styles.mutedMd),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      itemCount: _lines.length,
                      itemBuilder: (context, index) =>
                          SelectableText(_lines[index], style: logStyle),
                    ),
            ),
          ),
          TpDialogActions(
            children: [
              TextButton(
                onPressed: _lines.isEmpty
                    ? null
                    : () => Clipboard.setData(
                        ClipboardData(text: _lines.join('\n')),
                      ),
                child: Text(l10n.installJobCopy),
              ),
              if (!_unavailable)
                TextButton(
                  onPressed: () {
                    setState(() => _following = !_following);
                    if (_following) _scrollToEnd();
                  },
                  child: Text(
                    _following ? l10n.installJobPaused : l10n.installJobResume,
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.windowControlClose),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
