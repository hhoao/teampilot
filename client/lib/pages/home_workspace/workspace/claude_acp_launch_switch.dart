import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/session_preferences_cubit.dart';
import '../../../models/team_config.dart';
import '../../../services/cli/registry/capabilities/cli_transport_capability.dart';
import '../../../services/cli/registry/cli_tool_registry.dart';

export '../../../services/chat/launch/session/launch_acp_policy.dart'
    show resolveLaunchAcp;

export '../../../services/chat/launch/session/member_acp_stamp.dart'
    show resolveMemberBindingAcp, shouldAttachMemberAcp, stampMemberAcp;

bool readAcpDefault(BuildContext context, CliTool? cli) {
  if (cli == null) return false;
  try {
    return context
        .read<SessionPreferencesCubit>()
        .state
        .preferences
        .acpDefaultFor(cli);
  } on ProviderNotFoundException {
    return CliToolRegistry.builtIn()
            .capability<CliTransportCapability>(cli)
            ?.defaultTransport ==
        CliTransport.acp;
  }
}

/// Current settings default for "this CLI uses ACP"; true when the
/// preferences cubit is not in scope (matches [SessionPreferences] default).
bool readClaudeAcpDefault(BuildContext context) =>
    readAcpDefault(context, CliTool.claude);

/// Current settings default for "this CLI uses ACP"; true when the
/// preferences cubit is not in scope (matches [SessionPreferences] default).
bool readCodexAcpDefault(BuildContext context) =>
    readAcpDefault(context, CliTool.codex);

LaunchSecurityPolicy readAcpPermissionDefault(BuildContext context) {
  try {
    return context
        .read<SessionPreferencesCubit>()
        .state
        .preferences
        .acpPermissionDefault;
  } on ProviderNotFoundException {
    return LaunchSecurityPolicy.fullAccess;
  }
}

/// Same default as [readAcpPermissionDefault], subscribed so compose rebuilds.
LaunchSecurityPolicy watchAcpPermissionDefault(BuildContext context) {
  try {
    return context.select<SessionPreferencesCubit, LaunchSecurityPolicy>(
      (cubit) => cubit.state.preferences.acpPermissionDefault,
    );
  } on ProviderNotFoundException {
    return LaunchSecurityPolicy.fullAccess;
  }
}
