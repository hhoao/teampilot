import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/mcp_server.dart';
import '../../services/mcp/mcp_oauth_callback_server.dart';
import '../../services/mcp/mcp_oauth_discovery.dart';
import '../../services/mcp/mcp_oauth_flow.dart';
import '../../services/mcp/mcp_oauth_server_key.dart';
import '../../services/mcp/smithery_mcp_auth.dart';

Future<bool> showMcpOAuthConnectDialog({
  required BuildContext context,
  required McpServer server,
  required String configDir,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _McpOAuthConnectDialog(
      server: server,
      configDir: configDir,
    ),
  );
  return result == true;
}

enum _McpOAuthDialogPhase { discovering, waitingCallback, finishing }

class _McpOAuthConnectDialog extends StatefulWidget {
  const _McpOAuthConnectDialog({
    required this.server,
    required this.configDir,
  });

  final McpServer server;
  final String configDir;

  @override
  State<_McpOAuthConnectDialog> createState() => _McpOAuthConnectDialogState();
}

class _McpOAuthConnectDialogState extends State<_McpOAuthConnectDialog> {
  final _callbackController = TextEditingController();
  final _flow = McpOAuthFlow();

  _McpOAuthDialogPhase _phase = _McpOAuthDialogPhase.discovering;
  String? _error;
  Uri? _authorizationUrl;
  Completer<Uri>? _manualCompleter;
  McpOAuthCallbackServer? _callbackServer;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _manualCompleter = Completer<Uri>();
    if (!Platform.isAndroid) {
      _callbackServer = McpOAuthCallbackServer();
    }
    unawaited(_runAuth());
  }

  @override
  void dispose() {
    _callbackController.dispose();
    unawaited(_callbackServer?.close(cancelled: true));
    super.dispose();
  }

  Future<void> _runAuth() async {
    try {
      await _flow.authenticate(
        configDir: widget.configDir,
        serverName: widget.server.configKey,
        serverConfig: widget.server.server,
        callbackServer: _callbackServer,
        waitForManualCallback: () => _manualCompleter!.future,
        onAuthorizationUrl: (url) {
          if (_cancelled || !mounted) return;
          setState(() {
            _authorizationUrl = url;
            _phase = _McpOAuthDialogPhase.waitingCallback;
            _error = null;
          });
          unawaited(_openBrowser());
        },
        useLocalCallback: !Platform.isAndroid,
      );
      if (_cancelled || !mounted) return;
      setState(() => _phase = _McpOAuthDialogPhase.finishing);
      Navigator.of(context).pop(true);
    } on McpOAuthCancelledException {
      // [_cancel] already closed the dialog.
    } catch (e) {
      if (_cancelled || !mounted) return;
      setState(() {
        _error = e.toString();
        _phase = _authorizationUrl != null
            ? _McpOAuthDialogPhase.waitingCallback
            : _McpOAuthDialogPhase.discovering;
      });
    }
  }

  Future<void> _openBrowser() async {
    final url = _authorizationUrl;
    if (url == null) return;
    try {
      final launched = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted && !_cancelled) {
        setState(
          () => _error = 'Could not open the system browser. Use the link below or paste the callback URL.',
        );
      }
    } catch (e) {
      if (mounted && !_cancelled) {
        setState(() => _error = e.toString());
      }
    }
  }

  void _submitManualCallback() {
    final raw = _callbackController.text.trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) {
      setState(() => _error = 'Invalid URL');
      return;
    }
    if (!uri.queryParameters.containsKey('code') &&
        !uri.queryParameters.containsKey('error')) {
      setState(
        () => _error = 'URL must include ?code= or ?error=',
      );
      return;
    }
    final completer = _manualCompleter;
    if (completer != null && !completer.isCompleted) {
      setState(() {
        _phase = _McpOAuthDialogPhase.finishing;
        _error = null;
      });
      completer.complete(uri);
    }
  }

  void _cancel() {
    if (_cancelled) return;
    _cancelled = true;
    unawaited(_callbackServer?.close(cancelled: true));
    final completer = _manualCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(const McpOAuthCancelledException());
    }
    if (mounted) {
      Navigator.of(context).pop(false);
    }
  }

  bool get _showCallbackField =>
      _authorizationUrl != null ||
      _phase != _McpOAuthDialogPhase.discovering;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final discovering = _phase == _McpOAuthDialogPhase.discovering;
    final finishing = _phase == _McpOAuthDialogPhase.finishing;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || finishing) return;
        _cancel();
      },
      child: AlertDialog(
        title: Text(l10n.mcpOAuthConnectTitle(widget.server.name)),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.mcpOAuthConnectHint),
              if (discovering) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(
                  l10n.mcpOAuthDiscovering,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_authorizationUrl != null) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: finishing ? null : _openBrowser,
                  icon: const Icon(Icons.open_in_browser, size: AppIconSizes.md),
                  label: Text(l10n.mcpOAuthOpenBrowser),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _authorizationUrl!.toString(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (_showCallbackField) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _callbackController,
                  enabled: !finishing,
                  decoration: InputDecoration(
                    labelText: l10n.mcpOAuthCallbackUrlLabel,
                    hintText: l10n.mcpOAuthCallbackUrlHint,
                  ),
                  minLines: 2,
                  maxLines: 4,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: finishing ? null : _cancel,
            child: Text(l10n.cancel),
          ),
          if (_showCallbackField)
            FilledButton(
              onPressed: finishing ? null : _submitManualCallback,
              child: Text(l10n.mcpOAuthSubmitCallback),
            ),
          if (finishing)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }
}

bool mcpServerShowsOAuthConnect(McpServer server) {
  if (!mcpServerNeedsOAuthConnect(server.server)) return false;
  return !SmitheryMcpAuth.shouldApplyCatalogBearer(server.server);
}
