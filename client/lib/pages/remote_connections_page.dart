import 'package:flutter/material.dart';

import 'ssh_profiles/ssh_profiles_section.dart';

class RemoteConnectionsPage extends StatelessWidget {
  const RemoteConnectionsPage({super.key, this.embedded = false});

  /// When true, omits the [Scaffold] so the surrounding shell supplies chrome.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    const body = SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: SshProfilesSection(showRemoteConfig: false),
    );
    if (embedded) return body;
    return const Scaffold(body: body);
  }
}
