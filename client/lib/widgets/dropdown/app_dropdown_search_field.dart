import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../app_icon_button.dart';

/// Compact search input for searchable [AppDropdownField] overlays (shadcn Combobox style).
class AppDropdownSearchField extends StatefulWidget {
  const AppDropdownSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  State<AppDropdownSearchField> createState() => _AppDropdownSearchFieldState();
}

class _AppDropdownSearchFieldState extends State<AppDropdownSearchField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(AppDropdownSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged('');
    widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasQuery = widget.controller.text.isNotEmpty;

    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      decoration: InputDecoration(
        hintText: widget.hintText,
        isDense: true,
        filled: true,
        fillColor: cs.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: context.appIconSizes.md,
          color: cs.onSurfaceVariant,
        ),
        suffixIcon: hasQuery
            ? AppIconButton(
                icon: Icons.clear,
                compact: true,
                size: AppIconButton.kCompactSize,
                onTap: _clear,
              )
            : null,
        floatingLabelBehavior: FloatingLabelBehavior.never,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: cs.primary),
        ),
      ),
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
    );
  }
}
