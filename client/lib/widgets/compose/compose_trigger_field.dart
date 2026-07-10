import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/plugin.dart';
import '../../models/skill.dart';
import '../../models/config_bundle.dart';
import '../../services/commands/command_bus.dart';
import '../../services/commands/shortcut_focus.dart';
import '../../services/storage/app_storage.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../services/compose/compose_file_search.dart';
import '../../services/compose/compose_slash_catalog.dart';
import '../../services/compose/compose_text_edit.dart';
import '../../services/compose/compose_trigger_caret.dart';
import '../../services/compose/compose_trigger_insert.dart';
import '../../services/compose/compose_trigger_query.dart';
import '../../services/keyboard/compose_keyboard_shortcut_handler.dart';
import '../inline_token/inline_token_text_field.dart';

sealed class ComposeTriggerSuggestion {}

final class ComposeTriggerFileSuggestion extends ComposeTriggerSuggestion {
  ComposeTriggerFileSuggestion(this.candidate);
  final ComposeFileCandidate candidate;
}

final class ComposeTriggerSlashSuggestion extends ComposeTriggerSuggestion {
  ComposeTriggerSlashSuggestion(this.candidate);
  final ComposeSlashCandidate candidate;
}

/// Multiline compose field with `@` file references and `/` skill/command picks.
class ComposeTriggerField extends StatefulWidget {
  const ComposeTriggerField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.enabled,
    required this.onChanged,
    required this.onSubmit,
    required this.canSubmit,
    required this.workspaceRoot,
    required this.skills,
    required this.plugins,
    required this.slashBundle,
    required this.mutedColor,
    required this.hintColor,
    this.onPasteImage,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final bool Function() canSubmit;
  final String workspaceRoot;
  final List<Skill> skills;
  final List<Plugin> plugins;
  final ConfigBundle slashBundle;
  final Color mutedColor;
  final Color hintColor;
  final Future<bool> Function()? onPasteImage;

  @override
  State<ComposeTriggerField> createState() => _ComposeTriggerFieldState();
}

class _ComposeTriggerFieldState extends State<ComposeTriggerField> {
  final _fieldKey = GlobalKey();
  ComposeTriggerQuery? _trigger;
  List<ComposeTriggerSuggestion> _suggestions = const [];
  var _selectedIndex = 0;
  var _searchGeneration = 0;
  Timer? _searchDebounce;
  Timer? _focusClearTimer;
  Offset _menuAnchor = Offset.zero;
  BoxConstraints? _fieldConstraints;
  VoidCallback? _newlineDisposer;
  VoidCallback? _submitDisposer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
    widget.focusNode.addListener(_handleFocusChanged);
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    if (widget.focusNode.hasFocus) {
      _registerComposeCommands();
    }
  }

  @override
  void didUpdateWidget(covariant ComposeTriggerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChanged);
      widget.focusNode.addListener(_handleFocusChanged);
    }
    if (widget.focusNode.hasFocus &&
        (oldWidget.controller != widget.controller ||
            oldWidget.onSubmit != widget.onSubmit ||
            oldWidget.canSubmit != widget.canSubmit)) {
      _registerComposeCommands();
    }
    if (oldWidget.workspaceRoot != widget.workspaceRoot ||
        oldWidget.skills != widget.skills ||
        oldWidget.plugins != widget.plugins ||
        oldWidget.slashBundle != widget.slashBundle) {
      _refreshSuggestions(immediate: true);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _focusClearTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    widget.controller.removeListener(_handleControllerChanged);
    widget.focusNode.removeListener(_handleFocusChanged);
    _unregisterComposeCommands();
    super.dispose();
  }

  void _registerComposeCommands() {
    _newlineDisposer?.call();
    _newlineDisposer = ComposeCommandBindings.registerNewline(
      bus: context.read<CommandBus>(),
      controller: widget.controller,
    );
    _syncSubmitRegistration();
  }

  void _unregisterComposeCommands() {
    _newlineDisposer?.call();
    _newlineDisposer = null;
    _submitDisposer?.call();
    _submitDisposer = null;
  }

  /// Keeps `compose.submit` registered only while focused and the `@` / `/`
  /// suggestion overlay is closed. While the overlay is open, Enter must
  /// only pick the highlighted suggestion (handled locally in
  /// [_handleComposeKey]) — not also fire `compose.submit` via the root
  /// dispatcher, so submit is un-registered rather than made a no-op (a
  /// registered no-op would still mark the key "handled" on the bus without
  /// telling the dispatcher/focus chain anything changed).
  void _syncSubmitRegistration() {
    _submitDisposer?.call();
    _submitDisposer = (widget.focusNode.hasFocus && !_overlayVisible)
        ? ComposeCommandBindings.registerSubmit(
            bus: context.read<CommandBus>(),
            onSubmit: widget.onSubmit,
            canSubmit: widget.canSubmit,
          )
        : null;
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (widget.onPasteImage == null || !widget.focusNode.hasFocus) {
      return false;
    }
    if (event is! KeyDownEvent || !_isPasteShortcut(event)) {
      return false;
    }
    unawaited(_handlePasteShortcut());
    return true;
  }

  void _handleFocusChanged() {
    if (widget.focusNode.hasFocus) {
      _focusClearTimer?.cancel();
      _registerComposeCommands();
      return;
    }
    _unregisterComposeCommands();
    // Defer closing so overlay pointer events can select an item first.
    _focusClearTimer?.cancel();
    _focusClearTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted || widget.focusNode.hasFocus) return;
      _clearSuggestions();
    });
  }

  void _handleControllerChanged() {
    _refreshSuggestions();
    _scheduleMenuAnchorUpdate();
  }

  void _scheduleMenuAnchorUpdate() {
    if (!_overlayVisible) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateMenuAnchor();
    });
  }

  void _updateMenuAnchor() {
    final constraints = _fieldConstraints;
    if (constraints == null) return;
    final fieldBox = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (fieldBox == null || !fieldBox.hasSize) return;

    final styles = AppTextStyles.of(context);
    final textStyle = styles.body.copyWith(
      color: widget.mutedColor,
      height: 1.5,
    );
    final anchor = composeTriggerMenuAnchor(
      context: context,
      fieldBox: fieldBox,
      value: widget.controller.value,
      textStyle: textStyle,
      maxWidth: constraints.maxWidth,
    );
    if (anchor == null || anchor == _menuAnchor) return;
    setState(() => _menuAnchor = anchor);
  }

  void _clearSuggestions() {
    if (_trigger == null && _suggestions.isEmpty) return;
    setState(() {
      _trigger = null;
      _suggestions = const [];
      _selectedIndex = 0;
    });
    _syncSubmitRegistration();
  }

  void _refreshSuggestions({bool immediate = false}) {
    final value = widget.controller.value;
    final cursor = value.selection.isValid
        ? value.selection.baseOffset
        : value.text.length;
    final trigger = detectComposeTrigger(value.text, cursor);
    if (trigger == null) {
      _clearSuggestions();
      return;
    }

    _trigger = trigger;
    _searchDebounce?.cancel();
    if (immediate) {
      unawaited(_runSearch(trigger));
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 120), () {
      unawaited(_runSearch(trigger));
    });
  }

  Future<void> _runSearch(ComposeTriggerQuery trigger) async {
    final generation = ++_searchGeneration;
    late final List<ComposeTriggerSuggestion> suggestions;
    switch (trigger.kind) {
      case ComposeTriggerKind.fileReference:
        try {
          final files = await searchComposeFilesDeep(
            fs: AppStorage.fs,
            workspaceRoot: widget.workspaceRoot,
            query: trigger.query,
          );
          suggestions = [
            for (final file in files) ComposeTriggerFileSuggestion(file),
          ];
        } on Object {
          suggestions = const [];
        }
      case ComposeTriggerKind.slashInvoke:
        final slash = buildComposeSlashCandidates(
          skills: widget.skills,
          plugins: widget.plugins,
          enabledBundle: widget.slashBundle,
          query: trigger.query,
        );
        suggestions = [
          for (final item in slash) ComposeTriggerSlashSuggestion(item),
        ];
    }

    if (!mounted || generation != _searchGeneration) return;
    setState(() {
      _trigger = trigger;
      _suggestions = suggestions;
      _selectedIndex = suggestions.isEmpty
          ? 0
          : _selectedIndex.clamp(0, suggestions.length - 1);
    });
    _syncSubmitRegistration();
    _scheduleMenuAnchorUpdate();
  }

  bool get _overlayVisible => _trigger != null && _suggestions.isNotEmpty;

  void _selectSuggestion(ComposeTriggerSuggestion suggestion) {
    final trigger = _trigger;
    if (trigger == null) return;

    final insertion = switch (suggestion) {
      ComposeTriggerFileSuggestion(:final candidate) => candidate.insertText,
      ComposeTriggerSlashSuggestion(:final candidate) => candidate.insertText,
    };
    widget.controller.value = replaceComposeTrigger(
      widget.controller,
      trigger,
      insertion,
    );
    _focusClearTimer?.cancel();
    _clearSuggestions();
    widget.onChanged(widget.controller.text);
    widget.focusNode.requestFocus();
    setState(() {});
  }

  KeyEventResult _handleComposeKey(FocusNode node, KeyEvent event) {
    if (_overlayVisible && event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _selectedIndex = (_selectedIndex + 1) % _suggestions.length;
        });
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _selectedIndex =
              (_selectedIndex - 1 + _suggestions.length) % _suggestions.length;
        });
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _clearSuggestions();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.tab) {
        _selectSuggestion(_suggestions[_selectedIndex]);
        return KeyEventResult.handled;
      }
    }

    // Enter / Mod+Enter (compose.submit / compose.newline) are matched by
    // the root ShortcutDispatcher and dispatched to the handlers registered
    // in _registerComposeCommands — nothing left to do here.
    return KeyEventResult.ignored;
  }

  bool _isPasteShortcut(KeyEvent event) {
    return event.logicalKey == LogicalKeyboardKey.keyV &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed);
  }

  Future<void> _handlePasteShortcut() async {
    final onPasteImage = widget.onPasteImage;
    if (onPasteImage == null) return;
    final pastedImage = await onPasteImage();
    if (pastedImage) {
      widget.onChanged(widget.controller.text);
      if (mounted) setState(() {});
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    widget.controller.value = insertTextAtSelection(
      widget.controller,
      text,
    );
    widget.onChanged(widget.controller.text);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.of(context);
    final textStyle = styles.body.copyWith(
      color: widget.mutedColor,
      height: 1.5,
    );

    if (_overlayVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateMenuAnchor();
      });
    }

    return ShortcutFocus(
      kind: ShortcutFocusKind.compose,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _fieldConstraints = constraints;
          return InlineTokenTextField(
            fieldKey: _fieldKey,
            controller: widget.controller,
            focusNode: widget.focusNode,
            hint: widget.hint,
            enabled: widget.enabled,
            onChanged: widget.onChanged,
            textStyle: textStyle,
            hintStyle: styles.body.copyWith(
              color: widget.hintColor,
              height: 1.5,
            ),
            cursorColor: widget.mutedColor,
            onKeyEvent: _handleComposeKey,
            overlayVisible: _overlayVisible,
            overlayAnchor: _menuAnchor,
            overlayBuilder: _overlayVisible
                ? (context) => _ComposeTriggerSuggestionPanel(
                    suggestions: _suggestions,
                    selectedIndex: _selectedIndex,
                    onSelected: _selectSuggestion,
                    onHover: (index) => setState(() => _selectedIndex = index),
                  )
                : null,
          );
        },
      ),
    );
  }
}

class _ComposeTriggerSuggestionPanel extends StatelessWidget {
  const _ComposeTriggerSuggestionPanel({
    required this.suggestions,
    required this.selectedIndex,
    required this.onSelected,
    required this.onHover,
  });

  final List<ComposeTriggerSuggestion> suggestions;
  final int selectedIndex;
  final ValueChanged<ComposeTriggerSuggestion> onSelected;
  final ValueChanged<int> onHover;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.appSpacing;
    final styles = AppTextStyles.of(context);

    return Material(
      elevation: 8,
      shadowColor: cs.shadow.withValues(alpha: 0.18),
      color: cs.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.symmetric(vertical: spacing.xs),
          children: _buildPanelChildren(
            context: context,
            cs: cs,
            spacing: spacing,
            styles: styles,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPanelChildren({
    required BuildContext context,
    required ColorScheme cs,
    required AppSpacingTheme spacing,
    required AppTextStyles styles,
  }) {
    final children = <Widget>[];
    ComposeSlashCandidateKind? slashSection;

    for (var index = 0; index < suggestions.length; index++) {
      final suggestion = suggestions[index];
      if (suggestion is ComposeTriggerSlashSuggestion) {
        final section = suggestion.candidate.kind;
        if (slashSection != section) {
          slashSection = section;
          children.add(
            _ComposeTriggerSectionHeader(
              label: section == ComposeSlashCandidateKind.skill
                  ? 'Skills'
                  : 'Commands',
              spacing: spacing,
              styles: styles,
              color: cs.onSurfaceVariant,
            ),
          );
        }
      }

      final selected = index == selectedIndex;
      final (icon, label, subtitle) = switch (suggestion) {
        ComposeTriggerFileSuggestion(:final candidate) => (
          candidate.isDirectory
              ? Icons.folder_outlined
              : Icons.description_outlined,
          candidate.insertText,
          candidate.relativePath,
        ),
        ComposeTriggerSlashSuggestion(:final candidate) => (
          candidate.kind == ComposeSlashCandidateKind.skill
              ? Icons.auto_awesome_outlined
              : Icons.terminal_outlined,
          candidate.insertText,
          candidate.subtitle,
        ),
      };

      children.add(
        Material(
          color: selected
              ? cs.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          child: InkWell(
            onTapDown: (_) => onSelected(suggestion),
            onTap: () => onSelected(suggestion),
            onHover: (_) => onHover(index),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: spacing.md,
                vertical: spacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: spacing.xs / 2),
                    child: Icon(icon, size: 18, color: cs.onSurfaceVariant),
                  ),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: styles.bodySmall.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitle != null && subtitle.trim().isNotEmpty)
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: styles.bodySmall.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return children;
  }
}

class _ComposeTriggerSectionHeader extends StatelessWidget {
  const _ComposeTriggerSectionHeader({
    required this.label,
    required this.spacing,
    required this.styles,
    required this.color,
  });

  final String label;
  final AppSpacingTheme spacing;
  final AppTextStyles styles;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.md,
        spacing.sm,
        spacing.md,
        spacing.xs,
      ),
      child: Text(
        label,
        style: styles.bodySmall.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
