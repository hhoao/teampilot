import 'package:flutter/foundation.dart';

import '../../models/managed_provider.dart';
import '../../models/team_config.dart';

/// Parsed `provider:<cli>:<providerId>` managed-provider credential source.
///
/// Ids may contain any non-colon characters (provider ids are user slugs);
/// everything after the second colon is the id.
@immutable
class ManagedProviderLinkSource {
  const ManagedProviderLinkSource({
    required this.cli,
    required this.providerId,
  });

  final CliTool cli;
  final String providerId;

  String get value => managedProviderLinkSourceValue(cli, providerId);

  @override
  bool operator ==(Object other) =>
      other is ManagedProviderLinkSource &&
      other.cli == cli &&
      other.providerId == providerId;

  @override
  int get hashCode => Object.hash(cli, providerId);
}

String managedProviderLinkSourceValue(CliTool cli, String providerId) =>
    'provider:${cli.value}:$providerId';

ManagedProviderLinkSource? managedProviderLinkSourceOf(String source) {
  final trimmed = source.trim();
  if (!trimmed.startsWith('provider:')) return null;
  final rest = trimmed.substring('provider:'.length);
  final firstColon = rest.indexOf(':');
  if (firstColon <= 0) return null;
  final cli = CliTool.tryParse(rest.substring(0, firstColon));
  final providerId = rest.substring(firstColon + 1);
  if (cli == null || providerId.isEmpty) return null;
  return ManagedProviderLinkSource(cli: cli, providerId: providerId);
}

bool isManagedProviderLinkedToProvider(ManagedProvider provider) =>
    managedProviderLinkSourceOf(provider.endpointConfig.credentialSource) !=
    null;
