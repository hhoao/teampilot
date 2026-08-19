import 'package:flutter/foundation.dart';
import 'package:equatable/equatable.dart';

import '../../models/managed_provider.dart';

@immutable
class ManagedProviderPreset extends Equatable {
  const ManagedProviderPreset({
    required this.id,
    required this.labelId,
    required this.hintId,
    required this.template,
  });

  final String id;
  final String labelId;
  final String hintId;
  final ManagedProvider template;

  @override
  List<Object?> get props => [id, labelId, hintId, template];
}

final List<ManagedProviderPreset> builtInManagedProviderPresets =
    List.unmodifiable([
      ManagedProviderPreset(
        id: 'codex',
        labelId: 'codex',
        hintId: 'codex',
        template: ManagedProvider(
          id: '',
          name: 'Codex',
          kind: ManagedProviderKind.subscriptionQuota,
          adapterId: 'official-codex-subscription',
        ),
      ),
      ManagedProviderPreset(
        id: 'claude-code',
        labelId: 'claude-code',
        hintId: 'claude-code',
        template: ManagedProvider(
          id: '',
          name: 'Claude Code',
          kind: ManagedProviderKind.subscriptionQuota,
          adapterId: 'official-claude-subscription',
        ),
      ),
      ManagedProviderPreset(
        id: 'deepseek',
        labelId: 'deepseek',
        hintId: 'deepseek',
        template: ManagedProvider(
          id: '',
          name: 'DeepSeek',
          kind: ManagedProviderKind.apiBalance,
          adapterId: 'http-json',
          endpointConfig: ManagedProviderEndpointConfig(
            url: 'https://api.deepseek.com/user/balance',
            method: 'GET',
            measuresPath: r'$.balance_infos',
            fieldMappings: {
              'label': r'$.currency',
              'remaining': r'$.total_balance',
              'currency': r'$.currency',
            },
            credentialName: 'Authorization',
            credentialField: 'apiKey',
            credentialPlacement: 'header',
            credentialPrefix: 'Bearer ',
          ),
        ),
      ),
      ManagedProviderPreset(
        id: 'opencode',
        labelId: 'opencode',
        hintId: 'opencode',
        template: ManagedProvider(
          id: '',
          name: 'OpenCode',
          kind: ManagedProviderKind.customHttp,
          adapterId: 'http-json',
        ),
      ),
    ]);

ManagedProviderPreset? managedProviderPresetById(String id) {
  for (final preset in builtInManagedProviderPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}
