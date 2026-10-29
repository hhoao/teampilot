import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/cursor_usage_account.dart';
import '../../../models/cursor_usage_range.dart';
import '../../../models/cursor_usage_report.dart';
import '../../../services/cursor_usage/cursor_usage_cache.dart';
import '../../../services/cursor_usage/cursor_usage_coordinator.dart';
import 'usage_totals.dart';

class CursorUsageAccountList extends StatelessWidget {
  const CursorUsageAccountList({
    required this.accounts,
    required this.selectedAccountId,
    required this.syncing,
    required this.failures,
    required this.billingCycles,
    required this.reports,
    required this.onSelect,
    required this.onDelete,
    required this.onSetEnabled,
    super.key,
  });

  final List<CursorUsageAccount> accounts;
  final String? selectedAccountId;
  final Set<String> syncing;
  final Map<String, CursorUsageFailure> failures;
  final Map<String, CursorUsageWindow> billingCycles;
  final Map<String, CursorUsageReport> reports;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onDelete;
  final void Function(String accountId, bool enabled) onSetEnabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    if (accounts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          l10n.cursorUsageNoAccounts,
          style: styles.smColored(cs.onSurface.withValues(alpha: 0.6)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final account in accounts)
          ListTile(
            dense: true,
            selected: account.accountId == selectedAccountId,
            enabled: account.enabled,
            onTap: () => onSelect(account.accountId),
            leading: _statusDot(context, account),
            title: Text(account.label, style: styles.md),
            subtitle: Text(
              _subtitle(context, account),
              style: styles.xsColored(cs.onSurface.withValues(alpha: 0.6)),
            ),
            trailing: _accountMenu(context, account),
          ),
        if (reports.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(l10n.cursorUsageAllAccounts, style: styles.mdSemibold),
          const SizedBox(height: 8),
          CursorUsageTotals(
            report: aggregateCursorUsageReports(reports.values),
          ),
        ],
      ],
    );
  }

  Widget _accountMenu(BuildContext context, CursorUsageAccount account) {
    final l10n = context.l10n;
    final entries = <PopupMenuEntry<String>>[
      if (account.enabled)
        PopupMenuItem(
          value: 'disable',
          height: 36,
          child: Text(l10n.cursorUsageDisableAccount),
        )
      else
        PopupMenuItem(
          value: 'enable',
          height: 36,
          child: Text(l10n.cursorUsageEnableAccount),
        ),
      if (account.source == CursorAccountSource.manual)
        const PopupMenuDivider(),
      if (account.source == CursorAccountSource.manual)
        PopupMenuItem(
          value: 'delete',
          height: 36,
          child: Text(l10n.cursorUsageDeleteAccount),
        ),
    ];
    return PopupMenuButton<String>(
      tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
      onSelected: (value) async {
        switch (value) {
          case 'disable':
            onSetEnabled(account.accountId, false);
          case 'enable':
            onSetEnabled(account.accountId, true);
          case 'delete':
            final confirmed = await _confirmDelete(context, account);
            if (confirmed) onDelete(account.accountId);
        }
      },
      itemBuilder: (_) => entries,
      icon: const Icon(Icons.more_vert, size: 18),
    );
  }

  Future<bool> _confirmDelete(
    BuildContext context,
    CursorUsageAccount account,
  ) {
    final l10n = context.l10n;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.cursorUsageDeleteAccount),
        content: Text(l10n.cursorUsageDeleteAccountBody(account.label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.cursorUsageDeleteAccount),
          ),
        ],
      ),
    ).then((value) => value ?? false);
  }

  Widget _statusDot(BuildContext context, CursorUsageAccount account) {
    final cs = Theme.of(context).colorScheme;
    final failure = failures[account.accountId];
    final expired = account.isExpired(DateTime.now().millisecondsSinceEpoch);
    final color = !account.enabled
        ? cs.onSurface.withValues(alpha: 0.3)
        : syncing.contains(account.accountId)
        ? cs.primary
        : expired || failure != null
        ? cs.error
        : cs.tertiary;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  String _subtitle(BuildContext context, CursorUsageAccount account) {
    final l10n = context.l10n;
    final parts = <String>[
      account.source == CursorAccountSource.manual
          ? l10n.cursorUsageSourceManual
          : l10n.cursorUsageSourceAuto,
    ];
    if (account.teamId != 0) parts.add('team ${account.teamId}');
    // Prefer the catalog name; the raw provider id is only a fallback.
    final providerName =
        account.providerName ?? account.providerId;
    if (providerName != null) {
      parts.add(l10n.cursorUsageFromProvider(providerName));
    }
    if (!account.enabled) parts.add(l10n.cursorUsageStatusDisabled);
    if (account.isExpired(DateTime.now().millisecondsSinceEpoch)) {
      parts.add(l10n.cursorUsageStatusExpired);
    }
    final failure = failures[account.accountId];
    if (failure != null) parts.add(_failureLabel(context, failure));
    return parts.join(' · ');
  }

  String _failureLabel(BuildContext context, CursorUsageFailure failure) {
    final l10n = context.l10n;
    return switch (failure) {
      CursorUsageFailure.login => l10n.cursorUsageErrorLogin,
      CursorUsageFailure.rateLimited => l10n.cursorUsageErrorRateLimited,
      CursorUsageFailure.network => l10n.cursorUsageErrorNetwork,
      CursorUsageFailure.http => l10n.cursorUsageErrorHttp,
      CursorUsageFailure.invalidResponse => l10n.cursorUsageErrorInvalid,
      CursorUsageFailure.accountMismatch => l10n.cursorUsageErrorMismatch,
      CursorUsageFailure.rangeTooLarge => l10n.cursorUsageErrorRangeTooLarge,
      CursorUsageFailure.noCredential => l10n.cursorUsageErrorNoCredential,
    };
  }
}
