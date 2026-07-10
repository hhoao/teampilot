import '../../l10n/app_localizations.dart';
import '../../services/expert_hub/expert_capability_pack.dart';

/// Toast copy after Landing / deep-link expert capability preflight.
String expertLandingPreflightToastMessage(
  AppLocalizations l10n, {
  required String expertName,
  required ExpertCapabilityPack pack,
}) {
  if (!pack.hasFailures) return '';
  final failedNames = pack.failedDeps.map((f) => f.name).join(', ');
  return l10n.expertHubPreflightPartial(
    expertName,
    pack.failedDeps.length,
    failedNames,
  );
}
