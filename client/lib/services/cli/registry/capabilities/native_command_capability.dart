import '../cli_capability.dart';

enum NativeCommandDescription {
  goal('durable objective long-running work'),
  compact('compact active conversation context'),
  plan('planning workflow session task'),
  help('commands available CLI session');

  const NativeCommandDescription(this.searchTerms);

  /// Stable, locale-independent terms mirroring the localized description.
  ///
  /// Compose filtering stays outside Flutter l10n so the pure catalog remains
  /// usable in service tests and non-widget callers.
  final String searchTerms;
}

enum NativeCommandAvailability { stable, experimental }

final class NativeCommand {
  const NativeCommand({
    required this.name,
    this.description,
    this.descriptionText,
    this.argumentHint,
    this.availability = NativeCommandAvailability.stable,
  });

  final String name;

  /// Localized enum used by the curated static tables.
  final NativeCommandDescription? description;

  /// Agent-provided free text (ACP `AvailableCommand.description`).
  final String? descriptionText;

  final String? argumentHint;
  final NativeCommandAvailability availability;

  /// Command names are slash-free; tolerate one leading `/` from adapter data.
  String get slashName => name.startsWith('/') ? name.substring(1) : name;

  bool get acceptsArgument => argumentHint != null;

  String get insertText => acceptsArgument ? '/$slashName ' : '/$slashName';
}

abstract interface class NativeCommandCapability implements CliCapability {
  List<NativeCommand> get commands;
}
