import '../../models/launch_security_policy.dart';

/// Merges the proxy launch block into an existing `session/new` `_meta`.
///
/// CLI-specific keys such as Claude's `claudeCode` stay. The proxy reads only
/// `teampilot`. Permission is `ask` or `fullAccess`; other policies are sent
/// as `fullAccess`, which is what the proxy accepts.
Map<String, Object?> mergeAcpProxySessionMeta({
  required Map<String, Object?> base,
  required String cli,
  required List<String> argv,
  required Map<String, String> env,
  required LaunchSecurityPolicy permissionPolicy,
  String? authenticateMethodId,
}) {
  if (argv.isEmpty || argv.first.isEmpty) {
    throw ArgumentError.value(argv, 'argv', 'ACP proxy launch argv is empty');
  }
  final method = authenticateMethodId?.trim() ?? '';
  final teampilot = <String, Object?>{
    'cli': cli,
    'executable': argv.first,
    'args': argv.skip(1).toList(growable: false),
    'env': env,
    'permissionPolicy': permissionPolicy == LaunchSecurityPolicy.ask
        ? 'ask'
        : 'fullAccess',
    if (method.isNotEmpty) 'authenticateMethodId': method,
  };
  return {...base, 'teampilot': teampilot};
}
