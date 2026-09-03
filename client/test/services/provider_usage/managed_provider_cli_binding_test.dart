import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/provider_usage/managed_provider_cli_binding.dart';

void main() {
  const binding = ManagedProviderCliBinding();

  test('row id is cli-mp-providerId', () {
    expect(
      managedProviderCliRowId(CliTool.cursor, 'managed-123'),
      'cursor-mp-managed-123',
    );
    expect(
      managedProviderCliRowId(CliTool.claude, 'managed-123'),
      'claude-mp-managed-123',
    );
    expect(
      managedProviderCliRowId(CliTool.codex, 'managed-123'),
      'codex-mp-managed-123',
    );
  });

  test('cliForCredentialSource recognizes per-entry and legacy sources', () {
    expect(
      binding.cliForCredentialSource('cli:cursor-mp-managed-1'),
      CliTool.cursor,
    );
    expect(binding.cliForCredentialSource('cli:claude-mp-m-1'), CliTool.claude);
    expect(binding.cliForCredentialSource('cli:codex-mp-m-1'), CliTool.codex);
    expect(binding.cliForCredentialSource('cli:cursor-account'), CliTool.cursor);
    expect(binding.cliForCredentialSource('cli:claude-official'), CliTool.claude);
    expect(binding.cliForCredentialSource('cli:openai-official'), CliTool.codex);
    expect(binding.cliForCredentialSource('secret'), isNull);
    expect(binding.cliForCredentialSource('cli:nope'), isNull);
    expect(binding.cliForCredentialSource('cli:cursor-mp-'), isNull);
  });

  test('isPerEntrySource distinguishes per-entry from legacy', () {
    expect(binding.isPerEntrySource('cli:cursor-mp-managed-1'), isTrue);
    expect(binding.isPerEntrySource('cli:cursor-account'), isFalse);
    expect(binding.isPerEntrySource('secret'), isFalse);
  });

  test('rowIdForCredentialSource extracts row id', () {
    expect(
      binding.rowIdForCredentialSource('cli:cursor-mp-managed-1'),
      'cursor-mp-managed-1',
    );
    expect(
      binding.rowIdForCredentialSource('cli:cursor-account'),
      'cursor-account',
    );
    expect(binding.rowIdForCredentialSource('secret'), isNull);
  });

  test('migrateCredentialSource rewrites legacy to per-entry', () {
    expect(
      binding.migrateCredentialSource(
        source: 'cli:cursor-account',
        managedProviderId: 'managed-9',
      ),
      'cli:cursor-mp-managed-9',
    );
    expect(
      binding.migrateCredentialSource(
        source: 'cli:claude-official',
        managedProviderId: 'managed-9',
      ),
      'cli:claude-mp-managed-9',
    );
    expect(
      binding.migrateCredentialSource(
        source: 'cli:openai-official',
        managedProviderId: 'managed-9',
      ),
      'cli:codex-mp-managed-9',
    );
    expect(
      binding.migrateCredentialSource(
        source: 'cli:cursor-mp-managed-9',
        managedProviderId: 'managed-9',
      ),
      isNull,
    );
    expect(
      binding.migrateCredentialSource(
        source: 'secret',
        managedProviderId: 'managed-9',
      ),
      isNull,
    );
  });

  test('rowTemplateFor derives dedicated row from official preset', () {
    final template = binding.rowTemplateFor(
      CliTool.cursor,
      'managed-1',
      'My Cursor',
    );
    expect(template?.id, 'cursor-mp-managed-1');
    expect(template?.cli, CliTool.cursor);
    expect(template?.name, 'Cursor Account (My Cursor)');
    expect(template?.isOfficial, isTrue);
    expect(template?.category, AppProviderCategory.official);

    final claude = binding.rowTemplateFor(CliTool.claude, 'm1', 'Work');
    expect(claude?.id, 'claude-mp-m1');
    expect(claude?.isOfficial, isTrue);
    expect(claude?.category, AppProviderCategory.official);

    final codex = binding.rowTemplateFor(CliTool.codex, 'm1', 'Work');
    expect(codex?.id, 'codex-mp-m1');
    expect(codex?.isOfficial, isTrue);
    expect(codex?.category, AppProviderCategory.official);

    expect(binding.rowTemplateFor(CliTool.opencode, 'm1', 'X'), isNull);
  });
}
