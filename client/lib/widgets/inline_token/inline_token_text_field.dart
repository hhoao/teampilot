import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/inline_token/inline_token_chip_mirror.dart';
import '../../services/inline_token/inline_token_edit.dart';
import '../../services/inline_token/inline_token_palette.dart';
import '../dropdown/popover/anchor.dart';
import '../dropdown/popover/portal.dart';

/// Multiline text field that renders [tokenPattern] matches as inline chips.
///
/// The editable layer keeps plain text (transparent glyphs) while a mirror layer
/// underneath paints token pills aligned to layout metrics.
class InlineTokenTextField extends StatefulWidget {
  const InlineTokenTextField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.enabled,
    required this.onChanged,
    required this.textStyle,
    required this.hintStyle,
    required this.cursorColor,
    this.tokenPattern,
    this.resolveTokenPalette,
    this.minLines = 3,
    this.maxLines = 6,
    this.expands = false,
    this.overlayVisible = false,
    this.overlayAnchor = Offset.zero,
    this.overlayBuilder,
    this.onKeyEvent,
    this.fieldKey,
    this.selectionColor,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final TextStyle textStyle;
  final TextStyle hintStyle;
  final Color cursorColor;
  final Color? selectionColor;
  final RegExp? tokenPattern;
  final InlineTokenPaletteResolver? resolveTokenPalette;
  final int minLines;
  final int maxLines;

  /// When true, fill the parent (e.g. [AppTextareaShell]) instead of sizing
  /// from [minLines]/[maxLines]. Avoids untappable blank gaps below the field.
  final bool expands;
  final bool overlayVisible;
  final Offset overlayAnchor;
  final WidgetBuilder? overlayBuilder;
  final FocusOnKeyEventCallback? onKeyEvent;
  final GlobalKey? fieldKey;

  @override
  State<InlineTokenTextField> createState() => _InlineTokenTextFieldState();
}

class _InlineTokenTextFieldState extends State<InlineTokenTextField> {
  FocusOnKeyEventCallback? _chainedKeyHandler;
  final _scrollController = ScrollController();
  final _internalFieldKey = GlobalKey();

  GlobalKey get _effectiveFieldKey => widget.fieldKey ?? _internalFieldKey;

  RegExp get _tokenPattern => widget.tokenPattern ?? defaultInlineTokenPattern;

  InlineTokenPaletteResolver get _resolvePalette =>
      widget.resolveTokenPalette ?? resolveSlashAtTokenPalette;

  @override
  void initState() {
    super.initState();
    _attachKeyHandler(widget.focusNode);
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant InlineTokenTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _detachKeyHandler(oldWidget.focusNode);
      _attachKeyHandler(widget.focusNode);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _detachKeyHandler(widget.focusNode);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  void _attachKeyHandler(FocusNode node) {
    _chainedKeyHandler = node.onKeyEvent;
    node.onKeyEvent = _handleKeyWithChain;
  }

  void _detachKeyHandler(FocusNode node) {
    if (node.onKeyEvent == _handleKeyWithChain) {
      node.onKeyEvent = _chainedKeyHandler;
    }
    _chainedKeyHandler = null;
  }

  KeyEventResult _handleKeyWithChain(FocusNode node, KeyEvent event) {
    final result = _handleKey(node, event);
    if (result != KeyEventResult.ignored) {
      return result;
    }
    final extra = widget.onKeyEvent?.call(node, event);
    if (extra != null && extra != KeyEventResult.ignored) {
      return extra;
    }
    return _chainedKeyHandler?.call(node, event) ?? KeyEventResult.ignored;
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      final updated = applyInlineTokenBackspace(
        widget.controller.value,
        _tokenPattern,
      );
      if (updated != null) {
        widget.controller.value = updated;
        widget.onChanged(updated.text);
        setState(() {});
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.delete) {
      final updated = applyInlineTokenDelete(
        widget.controller.value,
        _tokenPattern,
      );
      if (updated != null) {
        widget.controller.value = updated;
        widget.onChanged(updated.text);
        setState(() {});
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final selectionColor =
        widget.selectionColor ??
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.25);

    return LayoutBuilder(
      builder: (context, constraints) {
        final child = widget.expands
            ? SizedBox.expand(child: _buildEditorStack(selectionColor))
            : _buildEditorStack(selectionColor);

        if (widget.overlayBuilder == null) {
          return child;
        }

        return AppPortal(
          visible: widget.overlayVisible,
          anchor: AppGlobalAnchor(widget.overlayAnchor),
          portalBuilder: (context) => SizedBox(
            width: constraints.maxWidth,
            child: widget.overlayBuilder!(context),
          ),
          child: child,
        );
      },
    );
  }

  Widget _buildEditorStack(Color selectionColor) {
    final mirror = ListenableBuilder(
      listenable: _scrollController,
      builder: (context, _) {
        final scrollOffset = _scrollController.hasClients
            ? _scrollController.offset
            : 0.0;
        return InlineTokenChipMirror(
          text: widget.controller.text,
          baseStyle: widget.textStyle,
          minLines: widget.expands ? 1 : widget.minLines,
          maxLines: widget.expands ? 100 : widget.maxLines,
          expands: widget.expands,
          scrollOffset: scrollOffset,
          tokenPattern: _tokenPattern,
          resolvePalette: _resolvePalette,
        );
      },
    );

    final field = TextSelectionTheme(
      data: TextSelectionThemeData(
        selectionColor: selectionColor,
        cursorColor: widget.cursorColor,
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        scrollController: _scrollController,
        expands: widget.expands,
        minLines: widget.expands ? null : widget.minLines,
        maxLines: widget.expands ? null : widget.maxLines,
        enabled: widget.enabled,
        onChanged: (value) {
          setState(() {});
          widget.onChanged(value);
        },
        style: widget.textStyle.copyWith(color: Colors.transparent),
        cursorColor: widget.cursorColor,
        textAlignVertical: widget.expands ? TextAlignVertical.top : null,
        decoration: InputDecoration(
          filled: false,
          hoverColor: Colors.transparent,
          hintText: widget.hint,
          hintStyle: widget.hintStyle,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          isDense: true,
        ),
      ),
    );

    return Stack(
      key: _effectiveFieldKey,
      alignment: Alignment.topLeft,
      children: [
        if (widget.expands) Positioned.fill(child: mirror) else mirror,
        if (widget.expands) Positioned.fill(child: field) else field,
      ],
    );
  }
}
