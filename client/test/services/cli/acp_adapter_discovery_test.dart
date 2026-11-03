import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/acp_adapter_discovery.dart';
import 'package:teampilot/services/cli/antigravity/antigravity_tool.dart';
import 'package:teampilot/services/cli/antigravity/capabilities/acp_settings.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_executable_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/installer/acp_adapter_installer.dart';
import 'package:teampilot/services/cli/registry/installer/installer_context.dart';
import 'package:teampilot/services/cli/installer_types.dart';

void main() {
  test('locateLocal returns only absolute Claude/Codex adapter hits', () async {
    final discovery = AcpAdapterDiscovery(registry: CliToolRegistry.builtIn());
    final located = await discovery.locateLocal(
      environment: const {'PATH': '/opt/bin', 'HOME': '/home/u'},
      fileExists: (p) => p == '/opt/bin/claude-agent-acp',
      isWindows: false,
    );
    expect(located[CliTool.claude], '/opt/bin/claude-agent-acp');
    expect(located.containsKey(CliTool.codex), isFalse);
    expect(located.containsKey(CliTool.cursor), isFalse);
  });

  test('locateLocal prefers a managed adapter installed path', () async {
    final registry = CliToolRegistry()
      ..register(
        AntigravityCliTool(
          acpSettings: AntigravityAcpSettings(
            installer: const _FakeAdapterInstaller(
              installedPath:
                  '/data/toolchain/antigravity-acp/agy_acp_server.par',
            ),
          ),
        ),
      );
    final discovery = AcpAdapterDiscovery(registry: registry);
    final located = await discovery.locateLocal(
      environment: const {'PATH': '/opt/bin', 'HOME': '/home/u'},
      // PATH lookup succeeds too; the managed install must still win.
      fileExists: (p) => p == '/opt/bin/agy_acp_server.par',
      isWindows: false,
    );
    expect(
      located[CliTool.antigravity],
      '/data/toolchain/antigravity-acp/agy_acp_server.par',
    );
  });

  test('locateRemote maps only separate-adapter CLIs via the probe', () async {
    final discovery = AcpAdapterDiscovery(registry: CliToolRegistry.builtIn());
    final located = await discovery.locateRemote(
      run: (command) async {
        if (command.contains('claude-agent-acp')) {
          return const SshCommandResult(
            exitCode: 0,
            stdout: '/home/u/.local/bin/claude-agent-acp\n',
          );
        }
        return const SshCommandResult(exitCode: 1, stdout: '');
      },
    );

    expect(located[CliTool.claude], '/home/u/.local/bin/claude-agent-acp');
    expect(located.containsKey(CliTool.codex), isFalse);
    expect(located.containsKey(CliTool.cursor), isFalse);
  });
}

class _FakeAdapterInstaller implements AcpAdapterInstaller {
  const _FakeAdapterInstaller({required this.installedPath});

  final String? installedPath;

  @override
  String get adapterJobTarget => 'adapter:fake';

  @override
  String get executableName => 'agy_acp_server.par';

  @override
  String get displayName => 'Fake adapter';

  @override
  bool get supportsInstaller => false;

  @override
  Future<String?> resolveInstalledPath() async => installedPath;

  @override
  Future<String?> latestVersion() async => '1.0.0';

  @override
  Future<CliInstallResult> install(CliInstallContext context) async =>
      const CliInstallResult(success: false, message: 'unused');
}
