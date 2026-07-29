import 'builtin_member_templates.dart';
import 'expert_capability_pack.dart';
import 'expert_capability_resolver.dart';

/// Expert key written onto a new Simple session from Landing.
///
/// Empty / blank draft selection resolves to [kBuiltinDefaultExpertKey].
String resolveLandingSessionExpertKey(String? expertKey) {
  final trimmed = expertKey?.trim() ?? '';
  return trimmed.isNotEmpty ? trimmed : kBuiltinDefaultExpertKey;
}

/// Result of early expert-pack install on Landing select / deep link.
class LandingExpertPreflightResult {
  const LandingExpertPreflightResult({this.pack, this.notFound = false});

  final ExpertCapabilityPack? pack;
  final bool notFound;

  bool get hasFailures => pack?.hasFailures == true;
}

/// Runs [ExpertCapabilityResolver.preflight] for Landing summon / deep link.
Future<LandingExpertPreflightResult> preflightLandingExpert({
  required ExpertCapabilityResolver resolver,
  required String expertKey,
}) async {
  final pack = await resolver.preflight(expertKey.trim());
  if (pack == null) {
    return const LandingExpertPreflightResult(notFound: true);
  }
  return LandingExpertPreflightResult(pack: pack);
}

/// Result of Landing expert chip / picker selection with preflight.
class LandingExpertSelectResult {
  const LandingExpertSelectResult({
    this.selectedKey,
    this.cleared = false,
    this.preflight,
  });

  final String? selectedKey;
  final bool cleared;
  final LandingExpertPreflightResult? preflight;
}

/// Chip-select / picker path — same [preflightLandingExpert] as deep link.
///
/// Unknown experts clear the selection: a dead key must never be committed to
/// the Landing draft (chip fallback would then look like "none selected").
Future<LandingExpertSelectResult> selectLandingExpert({
  required ExpertCapabilityResolver resolver,
  required String expertKey,
}) async {
  final trimmed = expertKey.trim();
  if (trimmed.isEmpty) {
    return const LandingExpertSelectResult(cleared: true);
  }

  final preflight = await preflightLandingExpert(
    resolver: resolver,
    expertKey: trimmed,
  );
  if (preflight.notFound) {
    return LandingExpertSelectResult(cleared: true, preflight: preflight);
  }

  return LandingExpertSelectResult(
    selectedKey: trimmed,
    preflight: preflight,
  );
}
