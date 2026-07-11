import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../repositories/keybinding_repository.dart';
import '../services/commands/command_catalog.dart';
import '../services/commands/key_chord.dart';
import '../services/commands/keybinding_resolver.dart';

class ShortcutState extends Equatable {
  const ShortcutState({this.overrides = const {}, this.loaded = false});

  final Map<String, List<KeyChord>> overrides;
  final bool loaded;

  Map<String, List<KeyChord>> get effective => KeybindingResolver.effectiveBindings(
    catalog: CommandCatalog.v1,
    overrides: overrides,
  );

  List<KeybindingConflict> get conflicts =>
      KeybindingResolver.findConflicts(effective);

  ShortcutState copyWith({
    Map<String, List<KeyChord>>? overrides,
    bool? loaded,
  }) => ShortcutState(
    overrides: overrides ?? this.overrides,
    loaded: loaded ?? this.loaded,
  );

  @override
  List<Object?> get props => [overrides, loaded];
}

/// Result of [ShortcutCubit.importOverrides]: whether the import applied, and
/// any conflicts discovered while scanning the imported map against the
/// current effective bindings.
class ImportResult {
  const ImportResult({required this.applied, this.conflicts = const []});

  final bool applied;
  final List<KeybindingConflict> conflicts;
}

/// Owns keybinding overrides: loads/persists via [KeybindingRepository] and
/// exposes the effective (catalog + overrides) bindings and conflicts.
///
/// See docs/superpowers/specs/2026-07-11-keyboard-shortcuts-platform-design.md.
class ShortcutCubit extends Cubit<ShortcutState> {
  ShortcutCubit({KeybindingRepository? repository})
    : _repository = repository ?? KeybindingRepository(),
      super(const ShortcutState());

  final KeybindingRepository _repository;

  Map<String, List<KeyChord>> get effective => state.effective;

  List<KeybindingConflict> get conflicts => state.conflicts;

  Future<void> load() async {
    final overrides = await _repository.load();
    emit(state.copyWith(overrides: overrides, loaded: true));
  }

  /// Replaces the effective chords for [commandId] with [chords].
  Future<void> rebind(String commandId, List<KeyChord> chords) async {
    await _setOverride(commandId, List<KeyChord>.from(chords));
  }

  /// Marks [commandId] as intentionally unbound (empty chord list).
  Future<void> unbind(String commandId) async {
    await _setOverride(commandId, const []);
  }

  /// Removes the override for [commandId], reverting it to the catalog default.
  Future<void> resetCommand(String commandId) async {
    if (!state.overrides.containsKey(commandId)) return;
    final next = Map<String, List<KeyChord>>.from(state.overrides)
      ..remove(commandId);
    await _persist(next);
  }

  /// Clears all overrides, reverting every command to its catalog default.
  Future<void> resetAll() async {
    await _persist(const {});
  }

  /// Imports [chordsByCommandId] as overrides.
  ///
  /// If applying the import would create conflicts with commands *not* in
  /// [chordsByCommandId] and [replaceConflicts] is `false`, the state is left
  /// unchanged and the conflicts are returned for the caller to present a
  /// "Replace all / Cancel" choice. When [replaceConflicts] is `true`, the
  /// conflicting chords are cleared from the other commands and the import is
  /// applied.
  Future<ImportResult> importOverrides(
    Map<String, List<KeyChord>> chordsByCommandId, {
    bool replaceConflicts = false,
  }) async {
    final importedIds = chordsByCommandId.keys.toSet();
    final tentativeOverrides = Map<String, List<KeyChord>>.from(
      state.overrides,
    );
    for (final entry in chordsByCommandId.entries) {
      tentativeOverrides[entry.key] = List<KeyChord>.from(entry.value);
    }

    final tentativeEffective = KeybindingResolver.effectiveBindings(
      catalog: CommandCatalog.v1,
      overrides: tentativeOverrides,
    );
    final conflicts = KeybindingResolver.findConflicts(tentativeEffective)
        .where((conflict) => conflict.commandIds.any(importedIds.contains))
        .toList(growable: false);

    if (conflicts.isNotEmpty && !replaceConflicts) {
      return ImportResult(applied: false, conflicts: conflicts);
    }

    var finalOverrides = tentativeOverrides;
    if (conflicts.isNotEmpty) {
      finalOverrides = Map<String, List<KeyChord>>.from(tentativeOverrides);
      for (final conflict in conflicts) {
        for (final commandId in conflict.commandIds) {
          if (importedIds.contains(commandId)) continue;
          final currentChords =
              finalOverrides[commandId] ?? _defaultChordsFor(commandId);
          finalOverrides[commandId] = currentChords
              .where((chord) => chord != conflict.chord)
              .toList(growable: false);
        }
      }
    }

    await _persist(finalOverrides);
    return ImportResult(applied: true, conflicts: conflicts);
  }

  List<KeyChord> _defaultChordsFor(String commandId) {
    for (final def in CommandCatalog.v1) {
      if (def.id == commandId) return List<KeyChord>.from(def.defaultChords);
    }
    return const [];
  }

  Future<void> _setOverride(String commandId, List<KeyChord> chords) async {
    final next = Map<String, List<KeyChord>>.from(state.overrides);
    next[commandId] = chords;
    await _persist(next);
  }

  Future<void> _persist(Map<String, List<KeyChord>> overrides) async {
    await _repository.save(overrides);
    emit(state.copyWith(overrides: overrides));
  }
}
