import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/resource/assemblers/mcp_assembler.dart';
import 'package:teampilot/services/resource/contribution/resource_assembly_error.dart';
import 'package:teampilot/services/resource/providers/catalog_mcp_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/mcp_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/plugin_mcp_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/smithery_mcp_contribution_provider.dart';

void main() {
  test('catalog provider does not load repository for empty ids', () async {
    var loads = 0;
    final provider = CatalogMcpContributionProvider(
      catalogLoader: () {
        loads++;
        return const [];
      },
    );

    final result = await provider.provide(
      McpProviderContext(cli: CliTool.claude),
    );

    expect(result, isEmpty);
    expect(loads, 0);
  });

  test('catalog loader failure keeps the selected source id', () async {
    final provider = CatalogMcpContributionProvider(
      catalogLoader: () => throw StateError('catalog unavailable'),
    );

    expect(
      () => const McpAssembler().assemble(
        context: McpProviderContext(
          cli: CliTool.claude,
          mcpServerIds: ['catalog-a'],
        ),
        providers: [provider],
      ),
      throwsA(
        isA<ResourceAssemblyException>().having(
          (error) => error.diagnostics.single,
          'diagnostic',
          isA<ResourceAssemblyError>()
              .having((error) => error.providerId, 'provider', 'catalog')
              .having((error) => error.sourceId, 'source', 'catalog-a'),
        ),
      ),
    );
  });

  test('plugin manifest failure keeps the plugin id', () async {
    final root = await Directory.systemTemp.createTemp('mcp_plugin_provider_');
    addTearDown(() => root.delete(recursive: true));
    final pluginDir = Directory('${root.path}/plugin-a');
    await pluginDir.create(recursive: true);
    await File('${pluginDir.path}/.mcp.json').writeAsString('{invalid');

    final plugin = Plugin(
      id: 'plugin-a',
      name: 'Plugin A',
      description: '',
      version: '1.0.0',
      directory: 'plugin-a',
      capabilities: const PluginCapabilities(),
      installedAt: 0,
      updatedAt: 0,
    );
    final provider = PluginMcpContributionProvider(
      fs: LocalFilesystem(),
      pluginsRoot: root.path,
      catalog: [plugin],
      enabledPluginIds: const ['plugin-a'],
    );

    expect(
      () => const McpAssembler().assemble(
        context: McpProviderContext(cli: CliTool.claude),
        providers: [provider],
      ),
      throwsA(
        isA<ResourceAssemblyException>().having(
          (error) => error.diagnostics.single,
          'diagnostic',
          isA<ResourceAssemblyError>()
              .having((error) => error.providerId, 'provider', 'plugin')
              .having((error) => error.sourceId, 'source', 'plugin-a'),
        ),
      ),
    );
  });

  test('Smithery wrapper preserves lower provider error metadata', () {
    final provider = SmitheryMcpContributionProvider(
      source: _FailingProvider(),
    );

    expect(
      () => const McpAssembler().assemble(
        context: McpProviderContext(cli: CliTool.claude),
        providers: [provider],
      ),
      throwsA(
        isA<ResourceAssemblyException>().having(
          (error) => error.diagnostics.single,
          'diagnostic',
          isA<ResourceAssemblyError>()
              .having((error) => error.providerId, 'provider', 'catalog')
              .having((error) => error.sourceId, 'source', 'catalog-a'),
        ),
      ),
    );
  });
}

final class _FailingProvider implements McpContributionProvider {
  @override
  String get providerId => 'catalog';

  @override
  Future<Iterable<McpContribution>> provide(McpProviderContext context) {
    throw ResourceAssemblyException([
      ResourceAssemblyError.provider(
        resourceKind: ResourceContributionKind.mcp,
        cli: context.cli,
        providerId: providerId,
        sourceId: 'catalog-a',
        message: 'catalog failed',
      ),
    ]);
  }
}
