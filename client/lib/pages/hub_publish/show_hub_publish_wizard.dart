import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/expert_hub_cubit.dart';
import '../../cubits/github_account_cubit.dart';
import '../../cubits/mcp_cubit.dart';
import '../../cubits/plugin_cubit.dart';
import '../../cubits/skill_cubit.dart';
import '../../models/discoverable_member.dart';
import '../../models/team_config.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../services/expert_hub/local_member_template_store.dart';
import '../../services/hub_publish/bundle_provenance_lookup.dart';
import '../../services/hub_publish/github_registry_publisher.dart';
import '../../services/github/github_credentials_store.dart';
import '../../services/hub_publish/hub_publish_record_store.dart';
import '../../services/hub_publish/hub_publish_service.dart';
import 'hub_publish_wizard.dart';

/// Opens the Hub publish wizard for a local [member] or [team].
Future<void> showHubPublishWizard(
  BuildContext context, {
  required HubPublishKind kind,
  DiscoverableMember? member,
  TeamProfile? team,
  HubPublishApi? publishApi,
  GithubCredentialsStore? credentials,
  HubPublishRecordStore? records,
  BundleProvenanceLookup? lookup,
  List<DiscoverableMember>? remapCandidates,
}) {
  assert(
    (kind == HubPublishKind.expert && member != null) ||
        (kind == HubPublishKind.team && team != null),
    'expert requires member; team requires team',
  );

  final resolvedCredentials =
      credentials ??
      (() {
        try {
          return context.read<GithubAccountCubit>().store;
        } catch (_) {
          return null;
        }
      }()) ??
      GithubCredentialsStore(kv: const FlutterSecureKeyValueStore());
  final resolvedLookup = lookup ?? _lookupFromContext(context);
  final resolvedRemap =
      remapCandidates ?? _remapCandidatesFromContext(context);
  final resolvedRecords = records ?? HubPublishRecordStore();
  final resolvedApi =
      publishApi ??
      HubPublishService(
        credentials: resolvedCredentials,
        records: resolvedRecords,
        publisher: GithubRegistryPublisher(),
        lookup: resolvedLookup,
      );

  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => HubPublishWizard(
      kind: kind,
      member: member,
      team: team,
      publishApi: resolvedApi,
      credentials: resolvedCredentials,
      lookup: resolvedLookup,
      remapCandidates: resolvedRemap,
    ),
  );
}

BundleProvenanceLookup _lookupFromContext(BuildContext context) {
  List<T> tryRead<T>(T Function() read) {
    try {
      return [read()];
    } catch (_) {
      return const [];
    }
  }

  final skills = tryRead(() => context.read<SkillCubit>().state.installed);
  final plugins = tryRead(() => context.read<PluginCubit>().state.installed);
  final mcps = tryRead(() => context.read<McpCubit>().state.servers);
  return BundleProvenanceLookup(
    skills: skills.isEmpty ? const [] : skills.first,
    plugins: plugins.isEmpty ? const [] : plugins.first,
    mcps: mcps.isEmpty ? const [] : mcps.first,
  );
}

List<DiscoverableMember> _remapCandidatesFromContext(BuildContext context) {
  try {
    final hub = context.read<ExpertHubCubit>();
    return [
      for (final m in hub.state.allMembers)
        if (!LocalMemberTemplateStore.isLocalKey(m.key)) m,
    ];
  } catch (_) {
    return const [];
  }
}
