import 'package:flutter/foundation.dart';

import 'cli_preset.dart';
import 'team_config.dart';

/// Denormalized Simple (unteamed) launch identity.
///
/// Persisted on [AppSession]. Create resolves once; reconnect must not
/// re-fetch a global [CliPreset] for provider/model/cli.
@immutable
class SimpleLaunchIdentity {
  const SimpleLaunchIdentity({
    required this.cli,
    this.provider = '',
    this.model = '',
    this.effort = '',
    this.expertKey = '',
    this.presetId = '',
  });

  final CliTool cli;
  final String provider;
  final String model;
  final String effort;
  final String expertKey;

  /// Provenance only — which global preset was chosen at create.
  final String presetId;

  /// Create-time resolve: preset wins over explicit args; an empty provider is
  /// filled by [officialProviderId] when supplied (services pass the CLI's
  /// [ProviderCapability.defaultOfficialProviderId] — the model never
  /// switches on [CliTool]).
  factory SimpleLaunchIdentity.resolve({
    CliTool? cli,
    CliPreset? preset,
    String? provider,
    String? model,
    String? effort,
    String? expertKey,
    String? presetId,
    String? Function(CliTool cli)? officialProviderId,
  }) {
    final resolvedCli = preset?.cli ?? cli ?? CliTool.claude;
    final fromPresetId = preset?.id.trim() ?? '';
    final resolvedPresetId =
        (presetId?.trim().isNotEmpty ?? false)
            ? presetId!.trim()
            : fromPresetId;

    var resolvedProvider = (preset?.provider.trim().isNotEmpty ?? false)
        ? preset!.provider.trim()
        : (provider?.trim() ?? '');
    if (resolvedProvider.isEmpty && officialProviderId != null) {
      resolvedProvider = officialProviderId(resolvedCli) ?? '';
    }

    final resolvedModel = (preset?.model.trim().isNotEmpty ?? false)
        ? preset!.model.trim()
        : (model?.trim() ?? '');
    final resolvedEffort = (preset?.effort.trim().isNotEmpty ?? false)
        ? preset!.effort.trim()
        : (effort?.trim() ?? '');

    return SimpleLaunchIdentity(
      cli: resolvedCli,
      provider: resolvedProvider,
      model: resolvedModel,
      effort: resolvedEffort,
      expertKey: expertKey?.trim() ?? '',
      presetId: resolvedPresetId,
    );
  }

  SimpleLaunchIdentity copyWith({
    CliTool? cli,
    String? provider,
    String? model,
    String? effort,
    String? expertKey,
    String? presetId,
  }) {
    return SimpleLaunchIdentity(
      cli: cli ?? this.cli,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      effort: effort ?? this.effort,
      expertKey: expertKey ?? this.expertKey,
      presetId: presetId ?? this.presetId,
    );
  }

  /// Defensive fallback for legacy rows whose provider predates persistence:
  /// fills the CLI's official default catalog id when unset.
  SimpleLaunchIdentity withOfficialDefaultProvider(
    String? Function(CliTool cli) resolveOfficialProvider,
  ) {
    if (provider.trim().isNotEmpty) return this;
    return copyWith(provider: resolveOfficialProvider(cli)?.trim() ?? '');
  }

  /// Apply identity onto an expert-pack member for staging / shell.
  TeamMemberConfig applyToMember(TeamMemberConfig member) {
    return member.copyWith(
      cli: cli,
      updateCli: true,
      provider: provider.isNotEmpty ? provider : member.provider,
      model: model.isNotEmpty ? model : member.model,
      effort: effort.isNotEmpty ? effort : member.effort,
      updateEffort: effort.isNotEmpty,
    );
  }

  Map<String, Object?> toJsonFields() => {
    'cli': cli.value,
    if (provider.isNotEmpty) 'provider': provider,
    if (model.isNotEmpty) 'model': model,
    if (effort.isNotEmpty) 'effort': effort,
    if (expertKey.isNotEmpty) 'expertKey': expertKey,
    if (presetId.isNotEmpty) 'presetId': presetId,
  };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SimpleLaunchIdentity &&
            cli == other.cli &&
            provider == other.provider &&
            model == other.model &&
            effort == other.effort &&
            expertKey == other.expertKey &&
            presetId == other.presetId;
  }

  @override
  int get hashCode =>
      Object.hash(cli, provider, model, effort, expertKey, presetId);
}
