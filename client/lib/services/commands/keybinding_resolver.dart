import 'package:flutter/services.dart';
import 'command_catalog.dart';
import 'command_definition.dart';
import 'key_chord.dart';
import 'shortcut_context.dart';

/// Two or more commands whose effective chord lists share [chord].
class KeybindingConflict {
  const KeybindingConflict({required this.chord, required this.commandIds});

  final KeyChord chord;
  final List<String> commandIds;
}

/// Resolves effective keybindings and matches key events to command ids.
///
/// See docs/superpowers/specs/2026-07-11-keyboard-shortcuts-platform-design.md
/// for the matching rules this implements.
abstract final class KeybindingResolver {
  /// Merges user [overrides] on top of [catalog] defaults.
  ///
  /// A missing entry in [overrides] falls back to the command's default
  /// chords; an explicit empty list means the command is intentionally
  /// unbound; a non-empty list fully replaces the defaults.
  static Map<String, List<KeyChord>> effectiveBindings({
    required List<CommandDefinition> catalog,
    required Map<String, List<KeyChord>> overrides,
  }) {
    return {
      for (final def in catalog)
        def.id: overrides.containsKey(def.id)
            ? overrides[def.id]!
            : def.defaultChords,
    };
  }

  /// Returns the id of the first command in declaration order whose
  /// effective chords match [event] and whose `when`/terminal/text-input
  /// rules are satisfied by [context], or `null` if nothing matches.
  static String? match({
    required KeyEvent event,
    required Map<String, List<KeyChord>> effectiveByCommand,
    required ShortcutContext context,
    required bool isMacOS,
    List<CommandDefinition>? catalog,
  }) {
    if (event is! KeyDownEvent) {
      return null;
    }

    final effectiveCatalog = catalog ?? CommandCatalog.v1;

    for (final def in effectiveCatalog) {
      final chords = effectiveByCommand[def.id];
      if (chords == null || chords.isEmpty) {
        continue;
      }
      if (!def.when.isSatisfiedBy(context)) {
        continue;
      }
      if (context.inTerminal && !def.terminalPassthrough) {
        continue;
      }

      for (final chord in chords) {
        // Double-tap chords need multi-event state; see ShortcutDispatcher.
        if (chord.doubleTap) continue;

        if (!chord.hasModifiers && context.inTextInput) {
          final allowedBareComposeKey =
              def.when == ShortcutWhen.inCompose && context.inCompose;
          // Escape is not a typing key — allow even when focus is in an editor.
          final allowedBareEscape = chord.key == 'escape';
          if (!allowedBareComposeKey && !allowedBareEscape) {
            continue;
          }
        }

        // The focused surface owns this chord (e.g. editor/chat find) — the
        // global command must not fire; the surface's own Shortcuts handles it.
        if (context.claimedChords.contains(chord)) {
          continue;
        }

        final activator = chord.toActivator(isMacOS: isMacOS);
        if (activator.accepts(event, HardwareKeyboard.instance)) {
          return def.id;
        }
      }
    }

    return null;
  }

  /// Finds commands whose effective chord lists share an identical chord.
  static List<KeybindingConflict> findConflicts(
    Map<String, List<KeyChord>> effectiveByCommand,
  ) {
    final commandIdsByChord = <KeyChord, List<String>>{};
    for (final entry in effectiveByCommand.entries) {
      for (final chord in entry.value) {
        commandIdsByChord.putIfAbsent(chord, () => []).add(entry.key);
      }
    }

    return [
      for (final entry in commandIdsByChord.entries)
        if (entry.value.length > 1)
          KeybindingConflict(chord: entry.key, commandIds: entry.value),
    ];
  }
}
