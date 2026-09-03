import '../../models/app_provider_config.dart';
import '../cli/claude/provider_presets.dart';
import '../cli/codex/provider_presets.dart';
import '../cli/cursor/provider_presets.dart';

/// Per-entry CLI provider row binding for managed-provider `cli:` sources.
///
/// A managed-provider entry that uses an official CLI credential source owns
/// a dedicated CLI provider row (`<cli>-mp-<managedProviderId>`) whose
/// isolated HOME holds that entry's login. Legacy shared sources
/// (`cli:cursor-account`, `cli:claude-official`, `cli:openai-official`) are
/// recognized and migrated to per-entry sources.
class ManagedProviderCliBinding {
  const ManagedProviderCliBinding();

  static const _legacyByCli = <CliTool, String>{
    CliTool.cursor: 'cursor-account',
    CliTool.claude: 'claude-official',
    CliTool.codex: 'openai-official',
  };

  static const _legacyTemplates = <CliTool, AppProviderConfig Function()>{
    CliTool.cursor: _cursorTemplate,
    CliTool.claude: _claudeTemplate,
    CliTool.codex: _codexTemplate,
  };

  static AppProviderConfig _cursorTemplate() =>
      CursorProviderPresets.byId('cursor-account')!.template;

  static AppProviderConfig _claudeTemplate() =>
      ClaudeProviderPresets.byId('claude-official')!.template;

  static AppProviderConfig _codexTemplate() =>
      CodexProviderPresets.byId('openai-official')!.template;

  CliTool? cliForCredentialSource(String source) {
    final rowId = rowIdForCredentialSource(source);
    if (rowId == null) return null;
    for (final cli in _legacyByCli.keys) {
      // `<cli>-mp-` with an empty trailing provider id segment is malformed.
      if (rowId == '${cli.value}-mp-') return null;
      if (rowId.startsWith('${cli.value}-mp-')) return cli;
      if (_legacyByCli[cli] == rowId) return cli;
    }
    return null;
  }

  bool isPerEntrySource(String source) =>
      cliForCredentialSource(source) != null &&
      (rowIdForCredentialSource(source) ?? '').contains('-mp-');

  String? rowIdForCredentialSource(String source) {
    const prefix = 'cli:';
    if (!source.startsWith(prefix)) return null;
    final rowId = source.substring(prefix.length).trim();
    return rowId.isEmpty ? null : rowId;
  }

  String? legacySourceForCli(CliTool cli) {
    final rowId = _legacyByCli[cli];
    return rowId == null ? null : 'cli:$rowId';
  }

  /// Rewrites a legacy shared source to the entry's per-entry source, or
  /// `null` when [source] is already per-entry, non-`cli:`, or unknown.
  String? migrateCredentialSource({
    required String source,
    required String managedProviderId,
  }) {
    final cli = cliForCredentialSource(source);
    if (cli == null || isPerEntrySource(source)) return null;
    if (rowIdForCredentialSource(source) != _legacyByCli[cli]) return null;
    return 'cli:${managedProviderCliRowId(cli, managedProviderId)}';
  }

  /// Dedicated CLI provider row for a managed-provider entry, or `null` for
  /// CLIs without an official preset.
  AppProviderConfig? rowTemplateFor(
    CliTool cli,
    String managedProviderId,
    String managedProviderName,
  ) {
    final templateFactory = _legacyTemplates[cli];
    if (templateFactory == null) return null;
    final preset = templateFactory();
    return preset.copyWith(
      id: managedProviderCliRowId(cli, managedProviderId),
      name: '${preset.name} ($managedProviderName)',
    );
  }
}

String managedProviderCliRowId(CliTool cli, String managedProviderId) =>
    '${cli.value}-mp-${managedProviderId.trim()}';
