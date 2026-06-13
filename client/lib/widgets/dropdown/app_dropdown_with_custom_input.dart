import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../l10n/l10n_extensions.dart';
import '../app_icon_button.dart';
import 'app_dropdown_decoration.dart';
import 'app_dropdown_field.dart';

/// [AppDropdownField] that also supports typing a custom value (cancel / confirm).
class AppDropdownWithCustomInput extends StatefulWidget {
  const AppDropdownWithCustomInput({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.hintText,
    this.decoration,
    this.customInputTooltip,
    super.key,
  });

  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;
  final String hintText;
  final AppDropdownDecoration? decoration;
  final String? customInputTooltip;

  @override
  State<AppDropdownWithCustomInput> createState() =>
      _AppDropdownWithCustomInputState();
}

class _AppDropdownWithCustomInputState extends State<AppDropdownWithCustomInput> {
  late final TextEditingController _customController;
  late final FocusNode _customFocusNode;
  bool _customMode = false;

  @override
  void initState() {
    super.initState();
    _customController = TextEditingController(text: widget.value);
    _customFocusNode = FocusNode();
    _customController.addListener(_onDraftChanged);
  }

  @override
  void didUpdateWidget(AppDropdownWithCustomInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_customMode && widget.value != _customController.text) {
      _customController.text = widget.value;
    }
  }

  @override
  void dispose() {
    _customController.removeListener(_onDraftChanged);
    _customFocusNode.dispose();
    _customController.dispose();
    super.dispose();
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  bool get _canConfirm => _customController.text.trim().isNotEmpty;

  List<String> _dropdownItems() {
    final items = List<String>.from(widget.items);
    final trimmed = widget.value.trim();
    if (trimmed.isNotEmpty && !items.contains(trimmed)) {
      items.add(trimmed);
    }
    items.sort();
    return items;
  }

  void _enterCustomMode() {
    setState(() {
      _customMode = true;
      _customController.text = widget.value;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _customFocusNode.requestFocus();
    });
  }

  void _cancelCustom() {
    _customFocusNode.unfocus();
    setState(() {
      _customMode = false;
      _customController.text = widget.value;
    });
  }

  void _confirmCustom() {
    if (!_canConfirm) return;
    _customFocusNode.unfocus();
    final next = _customController.text.trim();
    setState(() => _customMode = false);
    if (next != widget.value) {
      widget.onChanged(next);
    }
  }

  Widget _buildCustomInput() {
    return TextField(
      controller: _customController,
      focusNode: _customFocusNode,
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hintText,
      ),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) {
        if (_canConfirm) _confirmCustom();
      },
    );
  }

  Widget _buildCustomActions(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: _cancelCustom,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _canConfirm ? _confirmCustom : null,
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          child: Text(l10n.confirm),
        ),
      ],
    );
  }

  Widget _buildEditAction(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return AppIconButton(
      icon: Icons.edit_outlined,
      tooltip: widget.customInputTooltip ?? l10n.appProviderModelEnterCustom,
      color: cs.primary,
      size: AppIconButton.kCompactSize,
      iconSize: context.appIconSizes.sm,
      onTap: _enterCustomMode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dropdownItems = _dropdownItems();
    final deco =
        widget.decoration ?? AppDropdownDecorations.themed(context);

    if (_customMode) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: _buildCustomInput()),
          const SizedBox(width: 8),
          _buildCustomActions(context),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: AppDropdownField<String>(
            key: ValueKey(
              'dropdown-custom-input-${dropdownItems.join("|")}-${widget.value}',
            ),
            items: dropdownItems,
            initialItem: widget.value.trim().isEmpty
                ? null
                : widget.value.trim(),
            hintText: widget.hintText,
            decoration: deco,
            onChanged: (next) => widget.onChanged(next ?? ''),
            itemLabel: (item) => item,
          ),
        ),
        const SizedBox(width: 4),
        _buildEditAction(context),
      ],
    );
  }
}
