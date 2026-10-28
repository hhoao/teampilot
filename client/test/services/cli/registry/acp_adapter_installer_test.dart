import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/claude/capabilities/acp_adapter_installer.dart';
import 'package:teampilot/services/cli/codex/capabilities/acp_adapter_installer.dart';
import 'package:teampilot/services/cli/registry/installer/acp_adapter_installer.dart';

void main() {
  test('npm ACP adapters satisfy the neutral contract', () async {
    const claude = ClaudeAcpAdapterInstaller();
    const codex = CodexAcpAdapterInstaller();
    expect(claude, isA<AcpAdapterInstaller>());
    expect(codex, isA<AcpAdapterInstaller>());
    expect(claude.adapterJobTarget, ClaudeAcpAdapterInstaller.jobTarget);
    expect(codex.adapterJobTarget, CodexAcpAdapterInstaller.jobTarget);
    expect(await claude.resolveInstalledPath(), isNull);
    expect(await claude.latestVersion(), isNull);
  });
}
