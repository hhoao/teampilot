import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../../l10n/l10n_extensions.dart';
import '../../../terminal/terminal_transport.dart';
import '../../../terminal/terminal_transport_starter.dart';
import 'codebuddy_auth_store.dart';

/// Embedded interactive `codebuddy` terminal used to sign in / switch account.
///
/// The CLI has no `auth login` subcommand; the only login surface is the TUI
/// (login-method picker, then `/login` for account switching). This dialog
/// starts the CLI with a **per-provider isolated `HOME`** so credentials land in
/// TeamPilot's provider store instead of the user's global CodeBuddy login.
/// "/login" is auto-typed only when the composer is showing (an already
/// signed-in home); a startup login picker is left to the user. "Done" reports
/// success back to the provider action bar, which copies the token into the
/// provider store.
class CodebuddyLoginDialog extends StatefulWidget {
  const CodebuddyLoginDialog({
    required this.executable,
    required this.store,
    required this.providerId,
    this.arguments = const [],
    super.key,
  });

  final String executable;
  final CodebuddyAuthStore store;
  final String providerId;
  final List<String> arguments;

  @override
  State<CodebuddyLoginDialog> createState() => _CodebuddyLoginDialogState();
}

class _CodebuddyLoginDialogState extends State<CodebuddyLoginDialog> {
  static const _selectionDelay = Duration(milliseconds: 700);
  static const _submitDelay = Duration(milliseconds: 900);

  late final TerminalEngine _engine;
  TerminalTransport? _transport;
  StreamSubscription<Uint8List>? _outputSub;
  StreamSubscription<Uint8List>? _engineSub;
  final _timers = <Timer>[];
  final _recentOutput = StringBuffer();
  var _loginSent = false;
  String? _error;
  var _starting = true;
  var _exited = false;

  @override
  void initState() {
    super.initState();
    _engine = TerminalEngine(config: TerminalConfig.defaults());
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await widget.store.ensureLoginWorkspace(widget.providerId);
      final home = widget.store.loginHome(widget.providerId);
      final configDir = widget.store.loginConfigDir(widget.providerId);
      final workingDirectory = widget.store.loginWorkspace(widget.providerId);
      final transport = await defaultTransportStarter(
        widget.executable,
        arguments: widget.arguments,
        workingDirectory: workingDirectory,
        columns: 100,
        rows: 30,
        environment: {
          ...Platform.environment,
          'HOME': home,
          if (Platform.isWindows) 'USERPROFILE': home,
          'CODEBUDDY_CONFIG_DIR': configDir,
          'TERM': 'xterm-256color',
          'COLORTERM': 'truecolor',
        },
      );
      if (!mounted) {
        transport.close();
        return;
      }
      _transport = transport;
      _outputSub = transport.output.listen(_onOutput);
      _engineSub = _engine.output.listen(transport.write);
      _engine.onPtyResize = (columns, rows) => transport.resize(rows, columns);
      unawaited(
        transport.done.then((_) {
          if (mounted) setState(() => _exited = true);
        }),
      );
      setState(() => _starting = false);
      _scheduleAutoLogin();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = '$error';
      });
    }
  }

  void _onOutput(Uint8List data) {
    _engine.feed(data);
    if (_recentOutput.length > 16000) _recentOutput.clear();
    _recentOutput.write(utf8.decode(data, allowMalformed: true));
  }

  /// Auto-types `/login` only once the TUI shows its composer. A fresh login
  /// prompt (no composer) must be driven by the user instead — sending Enter
  /// there would pick a login method blindly.
  void _scheduleAutoLogin() {
    _timers.add(
      Timer.periodic(const Duration(milliseconds: 800), (timer) {
        if (_loginSent) {
          timer.cancel();
          return;
        }
        // A logged-out CLI already shows its login-method picker; pressing
        // Enter there would pick an account type blindly. Leave it to the
        // user and skip /login entirely.
        if (_looksLikeLoginPicker()) {
          timer.cancel();
          return;
        }
        if (_looksLikeComposer()) {
          timer.cancel();
          _sendLogin();
        } else if (timer.tick >= 12) {
          // ~10s: leave it to the user (the toolbar button stays available).
          timer.cancel();
        }
      }),
    );
  }

  bool _looksLikeLoginPicker() {
    final text = _recentOutput.toString();
    return text.contains('Select login method') ||
        text.contains('Log in via') ||
        text.contains('选择登录方式');
  }

  bool _looksLikeComposer() {
    final text = _recentOutput.toString();
    return text.contains('Tips for getting started') ||
        text.contains('Recent activity') ||
        text.contains('? for shortcuts');
  }

  void _sendLogin({bool force = false}) {
    if ((_loginSent && !force) || _transport == null || _exited) return;
    _loginSent = true;
    _write('/login');
    // First Enter opens the slash-command menu entry, second runs it.
    _timers.add(Timer(_selectionDelay, () => _write('\r')));
    _timers.add(Timer(_submitDelay, () => _write('\r')));
  }

  void _write(String text) {
    final transport = _transport;
    if (transport == null || _exited) return;
    transport.write(Uint8List.fromList(utf8.encode(text)));
  }

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _outputSub?.cancel();
    _engineSub?.cancel();
    _engine.onPtyResize = null;
    _transport?.close();
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
    return TpDialog(
      maxWidth: 960,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(title: l10n.codebuddyCredentialsLoginTitle),
          const SizedBox(height: 12),
          Text(
            l10n.codebuddyCredentialsLoginIntro,
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
                  child: TerminalView(
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
                      l10n.codebuddyCredentialsLoginStarting,
                      style: const TextStyle(color: Color(0xFFDDDDDD)),
                    ),
                  ),
                if (_error != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Text(
                      l10n.codebuddyCredentialsLoginFailed(_error!),
                      style: const TextStyle(color: Color(0xFFFF7B72)),
                    ),
                  ),
              ],
            ),
          ),
          if (_exited) ...[
            const SizedBox(height: 8),
            Text(
              l10n.codebuddyCredentialsLoginExited,
              style: TpTextStyles.of(context).mutedSm,
            ),
          ],
          const SizedBox(height: 16),
          TpDialogActions(
            children: [
              TpButton(
                variant: TpButtonVariant.outline,
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.codebuddyCredentialsCancel),
              ),
              TpButton(
                variant: TpButtonVariant.outline,
                onPressed: _exited ? null : () => _sendLogin(force: true),
                child: Text(l10n.codebuddyCredentialsSendLogin),
              ),
              TpButton(
                onPressed: _exited
                    ? null
                    : () => Navigator.of(context).pop(true),
                child: Text(l10n.codebuddyCredentialsDone),
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
                  child: Text(l10n.codebuddyCredentialsRetry),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
