import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/shortcut_cubit.dart';
import 'command_catalog.dart';
import 'key_chord.dart';
import 'key_chord_formatter.dart';
import 'keybinding_resolver.dart';

/// Label with the first effective shortcut for [commandId], e.g. `Hide sidebar (Ctrl+B)`.
///
/// Returns [label] unchanged when the command is unbound, missing from the
/// catalog, or [ShortcutCubit] is not in the tree.
String commandTooltip(BuildContext context, String label, String commandId) {
  try {
    final overrides = context.read<ShortcutCubit>().state.overrides;
    final bindings = KeybindingResolver.effectiveBindings(
      catalog: CommandCatalog.v1,
      overrides: overrides,
    );
    final chords = bindings[commandId] ?? const <KeyChord>[];
    if (chords.isEmpty) return label;
    final chord = formatKeyChord(chords.first, isMacOS: defaultIsMacOS());
    return '$label ($chord)';
  } catch (_) {
    return label;
  }
}
