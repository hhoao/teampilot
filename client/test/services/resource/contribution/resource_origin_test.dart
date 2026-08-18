import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/resource/contribution/resource_assembly_error.dart';
import 'package:teampilot/services/resource/contribution/resource_assembly_result.dart';
import 'package:teampilot/services/resource/contribution/resource_origin.dart';

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

      final result = ResourceAssemblyResult(
        warnings: [warning],
        errors: [error],
        diagnostics: [warning, error],
      );

      expect(result.warnings, [warning]);
      expect(result.errors, [error]);
      expect(result.diagnostics, [warning, error]);
    },
  );
}
