import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/cursor_usage_account.dart';
import '../../../models/cursor_usage_range.dart';
import '../../../models/cursor_usage_report.dart';
import '../../../services/cursor_usage/cursor_usage_coordinator.dart';
import '../../usage/usage_format.dart';
import '../cursor_usage_format.dart';

class CursorUsageAccountList extends StatelessWidget {
  const CursorUsageAccountList({
    required this.accounts,
    required this.selectedAccountId,
    required this.syncing,
    required this.failures,
    required this.billingCycles,
    required this.reports,
    required this.onSelect,
    super.key,
  });

  final List<CursorUsageAccount> accounts;
  final String? selectedAccountId;
  final Set<String> syncing;
  final Map<String, CursorUsageFailure> failures;
  final Map<String, CursorUsageWindow> billingCycles;
  final Map<String, CursorUsageReport> reports;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final totalTokens = reports.values.fold<int>(
      0,
      (sum, report) => sum + report.totalTokens,
    );
    final totalCents = reports.values.fold<double>(
      0,
      (sum, report) => sum + report.totalCents,
    );
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
      children: [
        if (reports.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${l10n.cursorUsageAllAccounts} · '
              '${formatUsageTokens(totalTokens)} · '
              '${formatCursorUsageUsd(totalCents)}',
              style: styles.xsColored(cs.onSurface.withValues(alpha: 0.55)),
            ),
          ),
        for (final account in accounts)
          ListTile(
            dense: true,
            selected: account.accountId == selectedAccountId,
            onTap: () => onSelect(account.accountId),
            leading: _statusDot(context, account),
            title: Text(account.label, style: styles.md),
            subtitle: Text(
              _subtitle(context, account),
              style: styles.xsColored(cs.onSurface.withValues(alpha: 0.6)),
            ),
          ),
      ],
    );
  }

  Widget _statusDot(BuildContext context, CursorUsageAccount account) {
    final cs = Theme.of(context).colorScheme;
    final failure = failures[account.accountId];
    final expired = account.isExpired(DateTime.now().millisecondsSinceEpoch);
    final color = syncing.contains(account.accountId)
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
