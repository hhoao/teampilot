import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_agent_config.dart';

void main() {
  test('workspace agent JSON does not persist launch security policy', () {
    const config = WorkspaceAgentConfig();

    expect(config.toJson().containsKey('launchSecurityPolicy'), isFalse);
  });
}
