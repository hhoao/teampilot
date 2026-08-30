import '../../l10n/app_localizations.dart';

/// Placeholder / tooltip JSON examples for the managed provider editor.
///
/// Kept in Dart (not ARB) so `$` and `{}` in examples do not break gen-l10n.
abstract final class ManagedProviderEditorFieldExamples {
  static const responsePath = r'$.data';

  static const requestBody = r'''
{
  "region": "us"
}''';

  static const headers = r'''
{
  "Accept": "application/json",
  "User-Agent": "my-cli",
  "ChatGPT-Account-Id": "{accountId}"
}''';

  static const windows = r'''
[
  {
    "label": "5h",
    "used": "$.rate_limit.primary_window.used_percent",
    "resetsAt": "$.rate_limit.primary_window.reset_at",
    "unit": "%"
  },
  {
    "label": "Weekly",
    "used": "$.rate_limit.secondary_window.used_percent",
    "resetsAt": "$.rate_limit.secondary_window.reset_at",
    "unit": "%"
  }
]''';

  static const balanceWindows = r'''
[
  {
    "label": "USD",
    "remaining": "$.balance_infos[0].total_balance"
  },
  {
    "label": "CNY",
    "remaining": "$.balance_infos[1].total_balance"
  }
]''';

  static const credentialTemplate =
      'WorkosCursorSessionToken={accountId}::{accessToken}';
}

String managedProviderHttpJsonReferenceTip(AppLocalizations l10n) {
  return l10n.managedProvidersReferenceSyntaxHelper;
}

String managedProviderFieldTip(
  AppLocalizations l10n, {
  required String explanation,
  String example = '',
  String? seeAlso,
}) {
  final parts = <String>[explanation.trim()];
  final trimmedExample = example.trim();
  if (trimmedExample.isNotEmpty) {
    parts.add('${l10n.managedProvidersFieldExampleLabel}：\n$trimmedExample');
  }
  if (seeAlso != null && seeAlso.trim().isNotEmpty) {
    parts.add(seeAlso.trim());
  }
  return parts.join('\n\n');
}
