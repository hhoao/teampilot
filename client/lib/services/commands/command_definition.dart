import 'key_chord.dart';

enum CommandCategory { navigation, tabs, view, zoom, compose, run, meta }

enum ShortcutWhen {
  always,
  hasWorkspace,
  hasOpenWorkspaceTabs,
  hasSessionTab,
  inCompose,
  floatingPanelOpen,
}

class CommandDefinition {
  const CommandDefinition({
    required this.id,
    required this.category,
    required this.defaultChords,
    required this.when,
    required this.terminalPassthrough,
    required this.titleL10nKey,
    this.descriptionL10nKey = '',
  });

  final String id;
  final CommandCategory category;
  final List<KeyChord> defaultChords;
  final ShortcutWhen when;
  final bool terminalPassthrough;
  final String titleL10nKey;
  final String descriptionL10nKey;
}
