import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../../l10n/l10n_extensions.dart';
import '../../../../models/app_provider_config.dart';
import '../../../../models/ssh_profile.dart';
import '../../../chat/runtime/pty/ssh_pty_transport.dart';
import '../../remote_cli_locator.dart';
import '../../../ssh/ssh_client_factory.dart';
import '../../../ssh/ssh_member_session.dart';
import 'antigravity_login_dialog.dart';

/// Interactive `agy` login over SSH, using an isolated remote HOME.
class AntigravityRemoteLoginDialog extends StatefulWidget {
  const AntigravityRemoteLoginDialog({
    required this.provider,
    required this.executable,
    required this.profile,
    this.factory,
    this.verifyModels,
    this.openSession,
    this.terminalBuilder,
    super.key,
  }) : assert(factory != null || openSession != null);

  final AppProviderConfig provider;
  final String executable;
  final SshProfile profile;
  final SshClientFactory? factory;
  final AntigravityModelsProbe? verifyModels;
  final Future<SshMemberSession> Function(SshProfile profile)? openSession;

  /// Test seam; production builds a [TerminalView].
  final Widget Function(TerminalEngine engine)? terminalBuilder;

  @override
  State<AntigravityRemoteLoginDialog> createState() =>
      _AntigravityRemoteLoginDialogState();
}

class _AntigravityRemoteLoginDialogState
    extends State<AntigravityRemoteLoginDialog> {
  late final TerminalEngine _engine;
  SshMemberSession? _session;
  SshPtyTransport? _transport;
  StreamSubscription<Uint8List>? _outputSub;
  StreamSubscription<Uint8List>? _engineSub;
  String? _root;
  String? _home;
  String? _workspace;
  String? _executable;
  String? _error;
  var _starting = true;
  var _exited = false;
  var _verifying = false;
  var _verifyFailed = false;

  @override
  void initState() {
    super.initState();
    _engine = TerminalEngine(config: TerminalConfig.defaults());
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final opener =
          widget.openSession ??
          (profile) => SshMemberSession.open(widget.factory!, profile);
      final session = await opener(widget.profile);
      _session = session;
      final home = (await session.run(r'printf %s "$HOME"')).trim();
      final root =
          '$home/.local/share/teampilot/cli-login/antigravity/'
          '${_safeSegment(widget.provider.id)}';
      await session.run('mkdir -p "$root/home" "$root/workspace"');
      _root = root;
      _home = '$root/home';
      _workspace = '$root/workspace';

      final located = await const DefaultRemoteCliLocator('agy').locate((
        command,
      ) async {
        final result = await session.runWithResult(command);
        return SshCommandResult(
          exitCode: result.exitCode ?? 1,
          stdout: utf8.decode(result.stdout, allowMalformed: true),
          stderr: utf8.decode(result.stderr, allowMalformed: true),
        );
      });
      _executable = located ?? widget.executable;
      final command =
          'export HOME=${_shellQuote(_home!)}; '
          'export GEMINI_HOME=${_shellQuote('$_home/.gemini')}; '
          'export TERM=xterm-256color; '
          'export COLORTERM=truecolor; '
          'cd ${_shellQuote(_workspace!)}; '
          'exec ${_shellQuote(_executable!)}';
      final channel = await session.openPty(
        command: command,
        columns: 100,
        rows: 30,
      );
      if (!mounted) {
        channel.close();
        return;
      }
      final transport = SshPtyTransport(channel: channel);
      _transport = transport;
      _outputSub = transport.output.listen(_engine.feed);
      _engineSub = _engine.output.listen(transport.write);
      _engine.onPtyResize = (columns, rows) => transport.resize(rows, columns);
      unawaited(
        transport.done.then((_) {
          if (mounted) setState(() => _exited = true);
        }),
      );
      setState(() => _starting = false);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = '$error';
      });
    }
  }

  Map<String, String> get _environment => {
    'HOME': _home ?? '',
    'GEMINI_HOME': '${_home ?? ''}/.gemini',
    'TERM': 'xterm-256color',
    'COLORTERM': 'truecolor',
  };

  Future<void> _done() async {
    final executable = _executable;
    final workspace = _workspace;
    if (executable == null || workspace == null || _verifying) return;
    setState(() {
      _verifying = true;
      _verifyFailed = false;
    });
    final ok = await _verifySafely(executable, workspace);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _verifying = false;
      _verifyFailed = true;
    });
  }

  Future<bool> _verifySafely(String executable, String workspace) async {
    final verify = widget.verifyModels;
    if (verify != null) {
      try {
        return await verify(
          executable: executable,
          environment: _environment,
          workingDirectory: workspace,
        );
      } on Object {
        return false;
      }
    }
    final session = _session;
    if (session == null) return false;
    try {
      final root = _root;
      if (root == null) return false;
      final result = await session.runWithResult(
        'cd ${_shellQuote(workspace)} && '
        'HOME=${_shellQuote(_home!)} '
        'GEMINI_HOME=${_shellQuote('$_home/.gemini')} '
        '${_shellQuote(executable)} models',
      );
      return (result.exitCode ?? 1) == 0;
    } on Object {
      return false;
    }
  }

  @override
  void dispose() {
    _outputSub?.cancel();
    _engineSub?.cancel();
    _engine.onPtyResize = null;
    _transport?.close();
    unawaited(_session?.close());
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final terminalHeight = (MediaQuery.sizeOf(context).height * 0.55).clamp(
      260.0,
      520.0,
    );
    final canDone = !_verifying && !_starting && _error == null;
    return TpDialog(
      maxWidth: 960,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(title: l10n.antigravityCredentialsLoginTitle),
          const SizedBox(height: 12),
          Text(
            l10n.antigravityCredentialsLoginIntro,
            style: TpTextStyles.of(context).mutedSm,
          ),
          const SizedBox(height: 12),
          Container(
            height: terminalHeight,
            decoration: BoxDecoration(
              color: const Color(0xFF101014),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x33FFFFFF)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned.fill(
                  child: widget.terminalBuilder?.call(_engine) ??
                      TerminalView(
                        _engine,
                        theme: TerminalTheme.defaults,
                        textStyle: TerminalStyle.defaults(),
                        preferGpuSurface: false,
                        autofocus: true,
                        padding: const EdgeInsets.all(8),
                        onPtyResize: (columns, rows) {
                          if (columns < kMinTerminalColumns ||
                              rows < kMinTerminalRows) {
                            return;
                          }
                          _transport?.resize(rows, columns);
                        },
                      ),
                ),
                if (_starting)
                  Center(
                    child: Text(
                      l10n.antigravityCredentialsLoginStarting,
                      style: const TextStyle(color: Color(0xFFDDDDDD)),
                    ),
                  ),
                if (_error != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Text(
                      l10n.antigravityCredentialsLoginFailed(_error!),
                      style: const TextStyle(color: Color(0xFFFF7B72)),
                    ),
                  ),
              ],
            ),
          ),
          if (_exited) ...[
            const SizedBox(height: 8),
            Text(
              l10n.antigravityCredentialsLoginExited,
              style: TpTextStyles.of(context).mutedSm,
            ),
          ],
          if (_verifyFailed) ...[
            const SizedBox(height: 8),
            Text(
              l10n.antigravityCredentialsLoginVerifyFailed,
              style: const TextStyle(color: Color(0xFFFF7B72)),
            ),
          ],
          const SizedBox(height: 16),
          TpDialogActions(
            children: [
              TpButton(
                variant: TpButtonVariant.outline,
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.antigravityCredentialsCancel),
              ),
              TpButton(
                key: const Key('antigravityRemoteLoginDone'),
                onPressed: canDone ? () => unawaited(_done()) : null,
                child: Text(l10n.antigravityCredentialsDone),
              ),
              if (_error != null)
                TpButton(
                  variant: TpButtonVariant.outline,
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _starting = true;
                    });
                    unawaited(_start());
                  },
                  child: Text(l10n.antigravityCredentialsRetry),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String _safeSegment(String value) {
  final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_').trim();
  return sanitized.isEmpty ? 'default' : sanitized;
}

String _shellQuote(String value) =>
    "'${value.replaceAll("'", "'\"'\"'")}'";
