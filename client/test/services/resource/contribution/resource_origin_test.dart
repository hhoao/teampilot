import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/resource/contribution/resource_assembly_error.dart';
import 'package:teampilot/services/resource/contribution/resource_assembly_result.dart';
import 'package:teampilot/services/resource/contribution/resource_origin.dart';
import 'package:teampilot/services/resource/cli_resource_provisioner.dart';

void main() {
  test('ContributionOrigin compares by all provenance fields', () {
    const first = ContributionOrigin(
      providerId: 'managed-prompts',
      kind: ResourceOriginKind.managed,
      sourceId: 'default',
    );
    const same = ContributionOrigin(
      providerId: 'managed-prompts',
      kind: ResourceOriginKind.managed,
      sourceId: 'default',
    );
    const different = ContributionOrigin(
      providerId: 'managed-prompts',
      kind: ResourceOriginKind.team,
      sourceId: 'default',
    );

    expect(first, same);
    expect(first.hashCode, same.hashCode);
    expect(first, isNot(different));
    expect(first.toString(), contains('managed-prompts'));
    expect(first.toString(), contains('managed'));
    expect(first.toString(), contains('default'));
  });

  test('ResourceAssemblyException carries multiple structured diagnostics', () {
    const diagnostics = [
      ResourceAssemblyError.provider(
        resourceKind: ResourceContributionKind.prompt,
        cli: CliTool.codex,
        providerId: 'workspace-prompts',
        sourceId: 'readme',
        message: 'provider failed',
      ),
      ResourceAssemblyError.conflict(
        resourceKind: ResourceContributionKind.mcp,
        cli: CliTool.codex,
        providerId: 'team-mcp',
        message: 'conflicting server',
      ),
    ];

    final exception = ResourceAssemblyException(diagnostics);

    expect(exception.diagnostics, diagnostics);
    expect(exception.toString(), contains('provider failed'));
    expect(exception.toString(), contains('conflicting server'));
  });

  test('ResourceAssemblyException exposes only typed error diagnostics', () {
    const errors = <ResourceAssemblyError>[
      ResourceAssemblyError.unsupported(
        resourceKind: ResourceContributionKind.skill,
        cli: CliTool.claude,
        providerId: 'catalog',
        message: 'skill unsupported',
      ),
    ];

    final exception = ResourceAssemblyException(errors);
    final List<ResourceAssemblyError> typedDiagnostics = exception.diagnostics;

    expect(typedDiagnostics, errors);
    expect(
      () => ResourceAssemblyException(const <ResourceAssemblyError>[]),
      throwsArgumentError,
    );
  });

  test('ResourceAssemblyError equality includes error kind', () {
    const provider = ResourceAssemblyError.provider(
      resourceKind: ResourceContributionKind.prompt,
      cli: CliTool.claude,
      providerId: 'provider',
      message: 'same fields',
    );
    const conflict = ResourceAssemblyError.conflict(
      resourceKind: ResourceContributionKind.prompt,
      cli: CliTool.claude,
      providerId: 'provider',
      message: 'same fields',
    );

    expect(provider, isNot(conflict));
    expect(provider.hashCode, isNot(conflict.hashCode));
  });

  test(
    'ResourceAssemblyResult keeps deterministic warning and error order',
    () {
      const warning = ResourceAssemblyDiagnostic(
        severity: ResourceAssemblyDiagnosticSeverity.warning,
        resourceKind: ResourceContributionKind.skill,
        cli: CliTool.claude,
        providerId: 'catalog',
        message: 'optional skill skipped',
      );
      const error = ResourceAssemblyDiagnostic(
        severity: ResourceAssemblyDiagnosticSeverity.error,
        resourceKind: ResourceContributionKind.hook,
        cli: CliTool.claude,
        providerId: 'managed-hooks',
        message: 'required hook missing',
      );

      final result = ResourceAssemblyResult(diagnostics: [warning, error]);

      expect(result.warnings, [warning]);
      expect(result.errors, [error]);
      expect(result.diagnostics, [warning, error]);
      expect(() => result.warnings.add(warning), throwsUnsupportedError);
      expect(() => result.errors.add(error), throwsUnsupportedError);
      expect(() => result.diagnostics.add(warning), throwsUnsupportedError);
    },
  );

  test('ResourceMaterializationResult freezes diagnostic collections', () {
    const diagnostic = ResourceAssemblyDiagnostic(
      severity: ResourceAssemblyDiagnosticSeverity.warning,
      resourceKind: ResourceContributionKind.hook,
      cli: CliTool.cursor,
      providerId: 'hook-materializer',
      message: 'optional hook skipped',
    );
    final result = ResourceMaterializationResult(
      kind: ResourceContributionKind.hook,
      attempted: true,
      warnings: ['optional hook skipped'],
      diagnostics: [diagnostic],
    );

    expect(() => result.warnings.add('late mutation'), throwsUnsupportedError);
    expect(() => result.diagnostics.add(diagnostic), throwsUnsupportedError);
  });
}
