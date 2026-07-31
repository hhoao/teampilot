import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../cubits/remote_download_catalog_cubit.dart';
import '../../cubits/termux_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../services/remote_download/remote_download_catalog.dart';
import '../../services/remote_download/remote_download_http.dart';
import '../../services/remote_download/remote_download_resolver.dart';
import '../../services/remote_download/remote_downloader.dart';
import '../../services/storage/app_storage.dart';
import '../../services/termux/termux_apk_acquisition.dart';
import '../../services/termux/termux_config.dart';
import '../../services/termux/termux_key_material.dart';
import '../../services/termux/termux_package_probe.dart';
import '../../widgets/app_toast/app_toast.dart';

const _termuxPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=com.termux';
const _termuxFdroidUrl = 'https://f-droid.org/packages/com.termux/';
const _termuxGitHubUrl = 'https://github.com/termux/termux-app';

enum _TermuxAcquireUiPhase { idle, downloading, installing }

/// Guided Termux OpenSSH setup (Roxum-style copyable commands + Connect).
class TermuxSetupPage extends StatefulWidget {
  const TermuxSetupPage({
    super.key,
    this.packageProbe,
    this.apkAcquisition,
  });

  final TermuxPackageProbe? packageProbe;
  final TermuxApkAcquisition? apkAcquisition;

  @override
  State<TermuxSetupPage> createState() => _TermuxSetupPageState();
}

class _TermuxSetupPageState extends State<TermuxSetupPage>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  String _username = '';
  String? _publicKey;
  var _loadingKey = true;
  bool? _termuxInstalled;
  var _probingTermux = true;
  var _acquiring = false;
  var _acquirePhase = _TermuxAcquireUiPhase.idle;

  late final TermuxPackageProbe _packageProbe;
  late TermuxApkAcquisition _apkAcquisition;
  http.Client? _ownedHttpClient;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _packageProbe = widget.packageProbe ?? TermuxPackageProbe();
    if (widget.apkAcquisition != null) {
      _apkAcquisition = widget.apkAcquisition!;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _initDefaultApkAcquisition();
        unawaited(_bootstrap());
      });
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrap());
    });
  }

  void _initDefaultApkAcquisition() {
    RemoteDownloadCatalogCubit? catalogCubit;
    try {
      catalogCubit = context.read<RemoteDownloadCatalogCubit>();
    } on ProviderNotFoundException {
      catalogCubit = null;
    }
    _ownedHttpClient = http.Client();
    final resolver = RemoteDownloadResolver.withProvider(
      () => catalogCubit?.state.catalog ?? RemoteDownloadCatalog.defaults(),
    );
    final downloadHttp = RemoteDownloadHttp(
      client: _ownedHttpClient!,
      resolver: resolver,
    );
    final downloader = RemoteDownloader(
      client: _ownedHttpClient!,
      resolver: resolver,
    );
    _apkAcquisition = TermuxApkAcquisition(
      http: downloadHttp,
      downloader: downloader,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _usernameController.dispose();
    _ownedHttpClient?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_probeTermuxInstalled());
    }
  }

  Future<void> _bootstrap() async {
    final cubit = context.read<TermuxCubit>();
    final config = cubit.state.config;
    if (config != null && config.username.trim().isNotEmpty) {
      _username = config.username.trim();
      _usernameController.text = _username;
    }
    await Future.wait([
      _probeTermuxInstalled(),
      _prepareKeys(),
    ]);
  }

  Future<void> _probeTermuxInstalled() async {
    if (!mounted) return;
    setState(() => _probingTermux = true);
    final installed = await _packageProbe.isTermuxInstalled();
    if (!mounted) return;
    setState(() {
      _termuxInstalled = installed;
      _probingTermux = false;
    });
  }

  Future<void> _prepareKeys() async {
    setState(() => _loadingKey = true);
    final nativePath = AppPathsBootstrapper.current.basePath;
    final credentials = context.read<SshCredentialStore>();
    await TermuxKeyMaterial.ensureKeyPair(
      nativeAppDataPath: nativePath,
      credentials: credentials,
    );
    final pubKey = await TermuxKeyMaterial.publicKeyOpenSsh(nativePath);
    if (!mounted) return;
    setState(() {
      _publicKey = pubKey;
      _loadingKey = false;
    });
  }

  String _authorizedKeysCommand(String publicKey) {
    return 'mkdir -p ~/.ssh\n\n'
        'chmod 700 ~/.ssh\n\n'
        'echo "$publicKey" >> ~/.ssh/authorized_keys\n\n'
        'chmod 600 ~/.ssh/authorized_keys';
  }

  String? _validateUsername(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty || !trimmed.startsWith('u')) {
      return context.l10n.termuxSetupUsernameError;
    }
    return null;
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _downloadAndInstall() async {
    if (_acquiring || _termuxInstalled == true) return;

    setState(() {
      _acquiring = true;
      _acquirePhase = _TermuxAcquireUiPhase.downloading;
    });

    final result = await _apkAcquisition.downloadAndInstall(
      onProgress: (received, total) {
        if (!mounted) return;
        setState(() {
          _acquirePhase = total != null && received >= total
              ? _TermuxAcquireUiPhase.installing
              : _TermuxAcquireUiPhase.downloading;
        });
      },
    );

    if (!mounted) return;
    setState(() {
      _acquiring = false;
      _acquirePhase = _TermuxAcquireUiPhase.idle;
    });

    if (result.success) {
      await _probeTermuxInstalled();
      return;
    }

    final l10n = context.l10n;
    final message = switch (result.phase) {
      TermuxApkAcquirePhase.installFailed ||
      TermuxApkAcquirePhase.installNoResult =>
        l10n.termuxSetupInstallDenied,
      _ => l10n.termuxSetupDownloadFailed,
    };
    AppToast.show(
      context,
      message: message,
      variant: TpToastVariant.error,
    );
  }

  Future<void> _connect() async {
    if (context.read<TermuxCubit>().state.connecting) return;

    final username = _usernameController.text.trim().isNotEmpty
        ? _usernameController.text.trim()
        : _username.trim();
    if (username.isEmpty || !username.startsWith('u')) {
      _formKey.currentState?.validate();
      return;
    }

    final cubit = context.read<TermuxCubit>();
    await cubit.saveConfig(TermuxConfig(username: username));
    await cubit.connect();
    if (!mounted) return;
    final state = cubit.state;
    if (state.connected) {
      AppToast.show(
        context,
        message: context.l10n.termuxSetupConnectSuccess,
        variant: TpToastVariant.success,
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    final error = state.lastError?.trim();
    if (error != null && error.isNotEmpty) {
      AppToast.show(
        context,
        message: _connectFailureMessage(context.l10n, error),
        variant: TpToastVariant.error,
      );
    }
  }

  String _connectFailureMessage(AppLocalizations l10n, String error) {
    final short = error.length > 120 ? '${error.substring(0, 117)}...' : error;
    return l10n.termuxSetupConnectFailedWithDetail(short);
  }

  Future<void> _confirmClearSetup() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => TpDialog(
        maxWidth: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(title: l10n.termuxSetupClearConfirmTitle),
            const SizedBox(height: 16),
            Text(l10n.termuxSetupClearConfirmBody),
            TpDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(l10n.cancel),
                ),
                TpButton(
                  key: const Key('termux_clear_confirm_button'),
                  variant: TpButtonVariant.destructive,
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(l10n.termuxSetupClearConfirmAction),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<TermuxCubit>().clearSetup();
    if (!mounted) return;
    _usernameController.clear();
    _username = '';
    setState(() {
      _publicKey = null;
      _loadingKey = true;
    });
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    unawaited(_prepareKeys());
  }

  Widget _buildInstallStep(BuildContext context) {
    final l10n = context.l10n;
    final tp = TpTheme.of(context);
    final cs = Theme.of(context).colorScheme;

    if (_probingTermux) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_termuxInstalled == true)
          Text(
            l10n.termuxSetupTermuxInstalled,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: cs.primary,
            ),
          )
        else ...[
          if (_acquiring) ...[
            if (_acquirePhase == _TermuxAcquireUiPhase.downloading)
              const LinearProgressIndicator(),
            SizedBox(height: tp.spacing.sm),
            Text(
              _acquirePhase == _TermuxAcquireUiPhase.installing
                  ? l10n.termuxSetupInstalling
                  : l10n.termuxSetupDownloading,
            ),
            SizedBox(height: tp.spacing.sm),
          ],
          TpButton(
            key: const Key('termux_download_install_button'),
            onPressed: _acquiring ? null : () => unawaited(_downloadAndInstall()),
            child: Text(
              _acquiring
                  ? (_acquirePhase == _TermuxAcquireUiPhase.installing
                        ? l10n.termuxSetupInstalling
                        : l10n.termuxSetupDownloading)
                  : l10n.termuxSetupDownloadInstall,
            ),
          ),
        ],
        SizedBox(height: tp.spacing.sm),
        Wrap(
          spacing: tp.spacing.sm,
          runSpacing: tp.spacing.sm,
          children: [
            TpButton(
              variant: TpButtonVariant.outline,
              onPressed: () => _openUrl(_termuxPlayStoreUrl),
              child: Text(l10n.termuxSetupInstallPlayStore),
            ),
            TpButton(
              variant: TpButtonVariant.outline,
              onPressed: () => _openUrl(_termuxFdroidUrl),
              child: Text(l10n.termuxSetupInstallFDroid),
            ),
            TpButton(
              variant: TpButtonVariant.outline,
              onPressed: () => _openUrl(_termuxGitHubUrl),
              child: Text(l10n.termuxSetupInstallGitHub),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tp = TpTheme.of(context);
    final pubKey = _publicKey ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.termuxSetupTitle)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(tp.spacing.lg),
          children: [
            Text(
              l10n.termuxSetupIntro,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            SizedBox(height: tp.spacing.lg),
            _SetupStep(
              title: l10n.termuxSetupStepInstallTermux,
              child: _buildInstallStep(context),
            ),
            _SetupStep(
              title: l10n.termuxSetupStepInstallOpenssh,
              child: _CopyCommandBlock(command: 'pkg install openssh'),
            ),
            _SetupStep(
              title: l10n.termuxSetupStepAuthorizedKeys,
              child: _loadingKey
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(),
                    )
                  : _CopyCommandBlock(
                      command: _authorizedKeysCommand(pubKey),
                      multiline: true,
                    ),
            ),
            _SetupStep(
              title: l10n.termuxSetupStepStorage,
              child: const _CopyCommandBlock(command: 'termux-setup-storage'),
            ),
            _SetupStep(
              title: l10n.termuxSetupStepStartSshd,
              child: const _CopyCommandBlock(command: 'sshd'),
            ),
            _SetupStep(
              title: l10n.termuxSetupStepWhoami,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _CopyCommandBlock(command: 'whoami'),
                  SizedBox(height: tp.spacing.xs),
                  Text(
                    l10n.termuxSetupWhoamiHint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            _SetupStep(
              title: l10n.termuxSetupUsernameLabel,
              child: TextFormField(
                key: const Key('termux_username_field'),
                controller: _usernameController,
                onChanged: (value) => _username = value,
                decoration: tpOutlineInputDecoration(
                  context,
                  decoration: InputDecoration(
                    hintText: l10n.termuxSetupUsernameHint,
                  ),
                ),
                validator: _validateUsername,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                textInputAction: TextInputAction.done,
              ),
            ),
            SizedBox(height: tp.spacing.md),
            TpButton(
              key: const Key('termux_connect_button'),
              onPressed: () => unawaited(_connect()),
              child: BlocBuilder<TermuxCubit, TermuxState>(
                builder: (context, state) {
                  if (state.connecting) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: tp.spacing.sm),
                        Text(l10n.termuxSetupConnecting),
                      ],
                    );
                  }
                  return Text(l10n.termuxSetupConnect);
                },
              ),
            ),
            SizedBox(height: tp.spacing.lg),
            TpButton(
              key: const Key('termux_clear_setup_button'),
              variant: TpButtonVariant.destructive,
              onPressed: _confirmClearSetup,
              child: Text(l10n.termuxSetupClearSetup),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupStep extends StatelessWidget {
  const _SetupStep({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tp = TpTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: tp.spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          SizedBox(height: tp.spacing.sm),
          child,
        ],
      ),
    );
  }
}

class _CopyCommandBlock extends StatelessWidget {
  const _CopyCommandBlock({required this.command, this.multiline = false});

  final String command;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final tp = TpTheme.of(context);

    return Container(
      padding: EdgeInsets.all(tp.spacing.sm),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(tp.control.radius),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Expanded(
            child: SelectableText(
              command,
              style: styles.smColored(cs.onSurface.withValues(alpha: 0.9)),
              maxLines: multiline ? null : 1,
            ),
          ),
          SizedBox(width: tp.spacing.sm),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: command));
              if (!context.mounted) return;
              AppToast.show(
                context,
                message: l10n.extensionCommandCopied,
                variant: TpToastVariant.success,
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: Text(l10n.extensionCopyCommand),
          ),
        ],
      ),
    );
  }
}
