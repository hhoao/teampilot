import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/github_account_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/github/github_credentials_store.dart';

/// Shared GitHub Device Flow connect / waiting / connected UI for Settings and
/// Hub publish.
class GithubDeviceFlowPanel extends StatefulWidget {
  const GithubDeviceFlowPanel({
    super.key,
    this.showAdvancedPat = false,
    this.showDisconnect = true,
    this.purposeText,
  });

  final bool showAdvancedPat;
  final bool showDisconnect;
  final String? purposeText;

  @override
  State<GithubDeviceFlowPanel> createState() => _GithubDeviceFlowPanelState();
}

class _GithubDeviceFlowPanelState extends State<GithubDeviceFlowPanel> {
  final _patController = TextEditingController();

  @override
  void dispose() {
    _patController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GithubAccountCubit, GithubAccountState>(
      builder: (context, state) {
        final l10n = context.l10n;
        final children = <Widget>[];

        if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
          children.addAll([
            Text(
              state.errorMessage!,
              style: TpTextStyles.of(context).smColored(
                Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
          ]);
        }

        switch (state.status) {
          case GithubAccountStatus.unknown:
          case GithubAccountStatus.disconnected:
            children.addAll(_disconnectedBody(context, state));
          case GithubAccountStatus.requesting:
            children.addAll(_requestingBody(context));
          case GithubAccountStatus.waiting:
            children.addAll(_waitingBody(context, state));
          case GithubAccountStatus.connected:
            children.addAll(_connectedBody(context, state));
        }

        if (widget.showAdvancedPat) {
          children.addAll([
            const SizedBox(height: 8),
            ExpansionTile(
              title: Text(l10n.githubAdvancedPat),
              children: [
                TextField(
                  key: const Key('github-pat-field'),
                  controller: _patController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.githubAdvancedPat,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (value) => _savePat(context, value),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TpButton(
                    variant: TpButtonVariant.primary,
                    onPressed: () => _savePat(context, _patController.text),
                    child: Text(l10n.save),
                  ),
                ),
              ],
            ),
          ]);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      },
    );
  }

  List<Widget> _disconnectedBody(
    BuildContext context,
    GithubAccountState state,
  ) {
    final l10n = context.l10n;
    final canSignIn = state.deviceFlowAvailable;

    return [
      Text(
        widget.purposeText ?? l10n.githubSettingsSubtitle,
        style: TpTextStyles.of(context).mutedSm,
      ),
      if (!canSignIn) ...[
        const SizedBox(height: 8),
        Text(
          l10n.githubDeviceFlowUnavailable,
          style: TpTextStyles.of(context).mutedSm,
        ),
      ],
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: TpButton(
          key: const Key('github-sign-in'),
          variant: TpButtonVariant.primary,
          onPressed: canSignIn
              ? () => context.read<GithubAccountCubit>().connect()
              : null,
          child: Text(l10n.githubSignIn),
        ),
      ),
    ];
  }

  List<Widget> _requestingBody(BuildContext context) {
    return const [
      SizedBox(height: 4),
      LinearProgressIndicator(),
      SizedBox(height: 8),
    ];
  }

  List<Widget> _waitingBody(BuildContext context, GithubAccountState state) {
    final l10n = context.l10n;
    final cubit = context.read<GithubAccountCubit>();

    return [
      Text(
        l10n.githubBrowserOpened,
        style: TpTextStyles.of(context).mutedSm,
      ),
      const SizedBox(height: 8),
      SelectableText(
        state.userCode ?? '',
        key: const Key('github-user-code'),
        style: TpTextStyles.of(context).mdBoldTightSnug,
      ),
      const SizedBox(height: 4),
      Text(
        l10n.githubWaitingCodeHint,
        style: TpTextStyles.of(context).mutedSm,
      ),
      const SizedBox(height: 12),
      SelectableText(
        state.verificationUri ?? '',
        key: const Key('github-verification-uri'),
        style: TpTextStyles.of(context).sm,
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          TpButton(
            variant: TpButtonVariant.outline,
            onPressed: cubit.reopenBrowser,
            child: Text(l10n.githubReopenBrowser),
          ),
          TpButton(
            variant: TpButtonVariant.ghost,
            onPressed: cubit.cancelConnect,
            child: Text(l10n.cancel),
          ),
        ],
      ),
    ];
  }

  List<Widget> _connectedBody(BuildContext context, GithubAccountState state) {
    final l10n = context.l10n;
    final login = state.login?.trim();
    final connectedText = (login != null && login.isNotEmpty)
        ? l10n.githubConnectedAs(login)
        : l10n.githubConnectedGeneric;

    return [
      Text(
        connectedText,
        style: TpTextStyles.of(context).mdBoldTightSnug,
      ),
      if (state.source != null) ...[
        const SizedBox(height: 4),
        Text(
          _sourceLabel(l10n, state.source!),
          style: TpTextStyles.of(context).mutedSm,
        ),
      ],
      if (widget.showDisconnect) ...[
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TpButton(
            key: const Key('github-disconnect'),
            variant: TpButtonVariant.outline,
            onPressed: () => context.read<GithubAccountCubit>().disconnect(),
            child: Text(l10n.githubDisconnect),
          ),
        ),
      ],
    ];
  }

  String _sourceLabel(AppLocalizations l10n, GithubCredentialSource source) {
    return switch (source) {
      GithubCredentialSource.oauth => l10n.githubSignIn,
      GithubCredentialSource.pat => l10n.githubAdvancedPat,
    };
  }

  void _savePat(BuildContext context, String token) {
    context.read<GithubAccountCubit>().savePat(token);
  }
}
