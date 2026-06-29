import 'package:flutter/material.dart';

/// Text field that mounts [TextField] only while focused.
///
/// Unfocused fields render as static text inside [InputDecorator], avoiding
/// Linux platform-channel probes (clipboard, LiveText, ProcessText) on rebuild.
class FocusGatedTextField extends StatefulWidget {
  const FocusGatedTextField({
    required this.controller,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.minLines = 1,
    this.maxLines = 1,
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final InputDecoration decoration;
  final int minLines;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  State<FocusGatedTextField> createState() => _FocusGatedTextFieldState();
}

class _FocusGatedTextFieldState extends State<FocusGatedTextField> {
  bool _editing = false;
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    final external = widget.focusNode;
    if (external != null) {
      _focusNode = external;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant FocusGatedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      _focusNode.removeListener(_onFocusChanged);
      if (_ownsFocusNode) {
        _focusNode.dispose();
      }
      final external = widget.focusNode;
      if (external != null) {
        _focusNode = external;
        _ownsFocusNode = false;
      } else {
        _focusNode = FocusNode();
        _ownsFocusNode = true;
      }
      _focusNode.addListener(_onFocusChanged);
      if (!_focusNode.hasFocus && _editing) {
        _editing = false;
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _focusNode.removeListener(_onFocusChanged);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _onControllerChanged() {
    if (!_editing && mounted) setState(() {});
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus && _editing) {
      setState(() => _editing = false);
    }
  }

  void _enterEdit() {
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_editing) {
      return _buildIdleField(context);
    }

    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      autofocus: true,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      decoration: widget.decoration,
      onChanged: widget.onChanged,
    );
  }

  Widget _buildIdleField(BuildContext context) {
    final text = widget.controller.text;
    final theme = Theme.of(context);
    final baseStyle =
        widget.decoration.hintStyle ??
        theme.inputDecorationTheme.hintStyle ??
        theme.textTheme.bodyLarge;
    final fontSize = baseStyle?.fontSize ?? 16.0;
    final lineHeight = baseStyle?.height ?? 1.0;
    // Match [TextField] minLines vertical extent while unfocused.
    final minIdleHeight = fontSize * lineHeight * widget.minLines;
    final hintText = widget.decoration.hintText;
    final hintStyle = baseStyle?.copyWith(
      color: widget.decoration.hintStyle?.color ?? theme.hintColor,
    );

    return InkWell(
      onTap: _enterEdit,
      child: InputDecorator(
        decoration: widget.decoration,
        isEmpty: text.isEmpty,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minIdleHeight),
          child: Align(
            alignment: Alignment.topLeft,
            child: text.isEmpty
                ? (hintText != null && hintText.isNotEmpty
                      ? Text(
                          hintText,
                          style: hintStyle,
                          maxLines: widget.maxLines > 1 ? widget.maxLines : 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : const SizedBox(width: double.infinity))
                : Text(
                    text,
                    style: baseStyle?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: widget.maxLines > 1 ? widget.maxLines : 1,
                    overflow: widget.maxLines > 1
                        ? TextOverflow.fade
                        : TextOverflow.ellipsis,
                  ),
          ),
        ),
      ),
    );
  }
}
