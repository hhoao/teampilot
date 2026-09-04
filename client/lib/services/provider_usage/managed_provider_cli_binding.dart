import '../../models/app_provider_config.dart';
import '../cli/claude/provider_presets.dart';
import '../cli/codex/provider_presets.dart';
import '../cli/cursor/provider_presets.dart';

/// Per-entry CLI provider row binding for managed-provider `cli:` sources.
///
/// A managed-provider entry that uses an official CLI credential source owns
/// a dedicated CLI provider row (`<cli>-mp-<managedProviderId>`) whose
/// isolated HOME holds that entry's login. Only per-entry sources are
/// recognized: preset templates carry an intent source (`cli:cursor`) that
/// the editor / cubit expands to the per-entry source before persistence.
class ManagedProviderCliBinding {
  const ManagedProviderCliBinding();

  static const _officialClis = <CliTool>{
    CliTool.cursor,
    CliTool.claude,
    CliTool.codex,
  };

  static const _officialTemplates = <CliTool, AppProviderConfig Function()>{
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

  /// CLI for a per-entry credential source (`cli:<cli>-mp-<entryId>`).
  ///
  /// Legacy shared sources (`cli:cursor-account`, …) and intent sources
  /// (`cli:cursor`) return null — only per-entry sources are valid here.
  CliTool? cliForCredentialSource(String source) {
    final rowId = rowIdForCredentialSource(source);
    if (rowId == null) return null;
    for (final cli in _officialClis) {
      // `<cli>-mp-` with an empty trailing provider id segment is malformed.
      if (rowId == '${cli.value}-mp-') return null;
      if (rowId.startsWith('${cli.value}-mp-')) return cli;
    }
    return null;
  }

  String? rowIdForCredentialSource(String source) {
    const prefix = 'cli:';
    if (!source.startsWith(prefix)) return null;
    final rowId = source.substring(prefix.length).trim();
    return rowId.isEmpty ? null : rowId;
  }

  /// CLI named by a preset intent source (`cli:cursor`, `cli:claude`,
  /// `cli:codex`). Row sources and unknown values return null.
  CliTool? intentCliForSource(String source) {
    final trimmed = source.trim();
    for (final cli in _officialClis) {
      if (trimmed == 'cli:${cli.value}') return cli;
    }
    return null;
  }

  /// Expands an intent source to the entry's per-entry source, or null when
  /// [source] is not an intent source (already per-entry, legacy, non-cli).
  String? resolveIntentSource({
    required String source,
    required String managedProviderId,
  }) {
    final cli = intentCliForSource(source);
    if (cli == null) return null;
    return 'cli:${managedProviderCliRowId(cli, managedProviderId)}';
  }

  /// Dedicated CLI provider row for a managed-provider entry, or `null` for
  /// CLIs without an official preset.
  AppProviderConfig? rowTemplateFor(
    CliTool cli,
    String managedProviderId,
    String managedProviderName,
  ) {
    final templateFactory = _officialTemplates[cli];
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
