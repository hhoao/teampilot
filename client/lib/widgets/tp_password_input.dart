import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';

/// Password input with a trailing show/hide toggle.
///
/// The value is obscured by default; tapping the eye icon reveals it without
/// clearing the text or moving focus away from the field. Autocorrect and
/// suggestions stay off so tokens and passwords are never rewritten.
class TpPasswordInput extends StatefulWidget {
  const TpPasswordInput({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration,
    this.onChanged,
    this.onEditingComplete,
    this.onSubmitted,
    this.style,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.maxLength,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.onTapOutside,
    this.restorationId,
    this.initiallyObscured = true,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onSubmitted;
  final TextStyle? style;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final TapRegionCallback? onTapOutside;
  final String? restorationId;

  /// Whether the value starts hidden. Defaults to `true`.
  final bool initiallyObscured;

  @override
  State<TpPasswordInput> createState() => _TpPasswordInputState();
}

class _TpPasswordInputState extends State<TpPasswordInput> {
  late bool _obscured = widget.initiallyObscured;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = widget.decoration ?? const InputDecoration();
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      decoration: tpOutlineInputDecoration(
        context,
        decoration: base.copyWith(
          suffixIcon: _suffixWithToggle(base.suffixIcon),
          suffixIconConstraints:
              base.suffixIconConstraints ??
              const BoxConstraints(minWidth: 0, minHeight: 0),
        ),
      ),
      style: widget.style ?? tpTextFieldStyle(theme.textTheme),
      obscureText: _obscured,
      autocorrect: false,
      enableSuggestions: false,
      maxLines: 1,
      maxLength: widget.maxLength,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      inputFormatters: widget.inputFormatters,
      onChanged: widget.onChanged,
      onEditingComplete: widget.onEditingComplete,
      onSubmitted: widget.onSubmitted,
      onTapOutside: widget.onTapOutside,
      restorationId: widget.restorationId,
    );
  }

  Widget _suffixWithToggle(Widget? existing) {
    final toggle = TpPasswordVisibilityToggle(
      key: const ValueKey('password-visibility-toggle'),
      obscured: _obscured,
      enabled: widget.enabled,
      onPressed: () => setState(() => _obscured = !_obscured),
    );
    if (existing == null) return toggle;
    return Row(mainAxisSize: MainAxisSize.min, children: [existing, toggle]);
  }
}

/// Eye icon that reveals or hides a password field.
///
/// Use as an `InputDecoration.suffixIcon` when the field itself cannot be a
/// [TpPasswordInput] (for example a [TextFormField] driven by a [Form]).
class TpPasswordVisibilityToggle extends StatelessWidget {
  const TpPasswordVisibilityToggle({
    super.key,
    required this.obscured,
    required this.onPressed,
    this.enabled = true,
  });

  final bool obscured;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: TpIconButton(
        icon: obscured
            ? Icons.visibility_outlined
            : Icons.visibility_off_outlined,
        compact: true,
        size: TpIconButton.kCompactSize,
        enabled: enabled,
        onTap: onPressed,
      ),
    );
  }
}
