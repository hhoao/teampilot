import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/session_usage_pricing.dart';
import '../../utils/ui/app_keys.dart';

class UsagePricingDialog extends StatefulWidget {
  const UsagePricingDialog({
    required this.initialRules,
    required this.onSave,
    required this.onReset,
    super.key,
  });

  final List<UsagePriceRule> initialRules;
  final Future<bool> Function(List<UsagePriceRule> rules) onSave;
  final Future<bool> Function() onReset;

  @override
  State<UsagePricingDialog> createState() => _UsagePricingDialogState();
}

class _UsagePricingDialogState extends State<UsagePricingDialog> {
  late final List<_PriceDraft> _drafts;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _drafts = [
      for (final rule in widget.initialRules) _PriceDraft.fromRule(rule),
      if (widget.initialRules.isEmpty) _PriceDraft.empty(),
    ];
  }

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  void _add() {
    setState(() {
      _drafts.add(_PriceDraft.empty());
      _error = null;
    });
  }

  void _remove(int index) {
    setState(() {
      _drafts.removeAt(index).dispose();
      if (_drafts.isEmpty) _drafts.add(_PriceDraft.empty());
      _error = null;
    });
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final rules = <UsagePriceRule>[];
    try {
      for (final draft in _drafts) {
        final rule = draft.toRule();
        if (rule != null) rules.add(rule);
      }
    } on FormatException {
      setState(() => _error = l10n.sessionUsagePricingInvalid);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = await widget.onSave(rules);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = l10n.sessionUsagePricingFailed;
      });
    }
  }

  Future<void> _reset() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.sessionUsagePricingResetConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.sessionUsagePricingReset),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = await widget.onReset();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = l10n.sessionUsagePricingFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      key: AppKeys.sessionUsagePricingDialog,
      title: Text(l10n.sessionUsagePricingTitle),
      content: SizedBox(
        width: 980,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.sessionUsagePricingHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: _drafts.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) => _PriceRowEditor(
                  draft: _drafts[index],
                  index: index,
                  onDelete: _drafts.length == 1 ? null : () => _remove(index),
                ),
              ),
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 8),
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  key: AppKeys.sessionUsagePricingAddButton,
                  onPressed: _saving ? null : _add,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l10n.sessionUsagePricingAdd),
                ),
                const Spacer(),
                TextButton(
                  key: AppKeys.sessionUsagePricingResetButton,
                  onPressed: _saving ? null : _reset,
                  child: Text(l10n.sessionUsagePricingReset),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: AppKeys.sessionUsagePricingSaveButton,
                  onPressed: _saving ? null : _save,
                  child: Text(l10n.sessionUsagePricingSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceRowEditor extends StatelessWidget {
  const _PriceRowEditor({
    required this.draft,
    required this.index,
    required this.onDelete,
  });

  final _PriceDraft draft;
  final int index;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _field(draft.model, l10n.sessionUsagePricingModel, 220),
          _field(draft.input, l10n.sessionUsagePricingInput, 92),
          _field(draft.output, l10n.sessionUsagePricingOutput, 92),
          _field(draft.cacheRead, l10n.sessionUsagePricingCacheRead, 100),
          _field(draft.cacheWrite, l10n.sessionUsagePricingCacheWrite, 100),
          _field(draft.cacheWrite1h, l10n.sessionUsagePricingCacheWrite1h, 110),
          _field(
            draft.effectiveDate,
            l10n.sessionUsagePricingEffectiveDate,
            130,
            hint: l10n.sessionUsagePricingEffectiveHint,
          ),
          IconButton(
            tooltip: l10n.sessionUsagePricingDelete,
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 19),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    double width, {
    String? hint,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

final class _PriceDraft {
  _PriceDraft({
    required this.model,
    required this.input,
    required this.output,
    required this.cacheRead,
    required this.cacheWrite,
    required this.cacheWrite1h,
    required this.effectiveDate,
  });

  factory _PriceDraft.empty() => _PriceDraft(
    model: TextEditingController(),
    input: TextEditingController(),
    output: TextEditingController(),
    cacheRead: TextEditingController(text: '0'),
    cacheWrite: TextEditingController(text: '0'),
    cacheWrite1h: TextEditingController(),
    effectiveDate: TextEditingController(),
  );

  factory _PriceDraft.fromRule(UsagePriceRule rule) => _PriceDraft(
    model: TextEditingController(text: rule.model),
    input: TextEditingController(text: _number(rule.inputPerMillion)),
    output: TextEditingController(text: _number(rule.outputPerMillion)),
    cacheRead: TextEditingController(text: _number(rule.cacheReadPerMillion)),
    cacheWrite: TextEditingController(text: _number(rule.cacheWritePerMillion)),
    cacheWrite1h: TextEditingController(
      text: rule.cacheWrite1hPerMillion == null
          ? ''
          : _number(rule.cacheWrite1hPerMillion!),
    ),
    effectiveDate: TextEditingController(
      text: rule.effectiveFromMs <= 0 ? '' : _date(rule.effectiveFromMs),
    ),
  );

  final TextEditingController model;
  final TextEditingController input;
  final TextEditingController output;
  final TextEditingController cacheRead;
  final TextEditingController cacheWrite;
  final TextEditingController cacheWrite1h;
  final TextEditingController effectiveDate;

  UsagePriceRule? toRule() {
    final modelId = model.text.trim();
    if (modelId.isEmpty) return null;
    final inputRate = _parse(input.text);
    final outputRate = _parse(output.text);
    final cacheReadRate = _parse(cacheRead.text);
    final cacheWriteRate = _parse(cacheWrite.text);
    final cacheWrite1hRate = cacheWrite1h.text.trim().isEmpty
        ? null
        : _parse(cacheWrite1h.text);
    final dateText = effectiveDate.text.trim();
    final effectiveFrom = dateText.isEmpty
        ? 0
        : DateTime.tryParse(dateText)?.millisecondsSinceEpoch;
    if (effectiveFrom == null) throw const FormatException('date');
    return UsagePriceRule(
      model: modelId,
      inputPerMillion: inputRate,
      outputPerMillion: outputRate,
      cacheReadPerMillion: cacheReadRate,
      cacheWritePerMillion: cacheWriteRate,
      cacheWrite1hPerMillion: cacheWrite1hRate,
      effectiveFromMs: effectiveFrom,
      source: UsagePriceSource.user,
    );
  }

  void dispose() {
    model.dispose();
    input.dispose();
    output.dispose();
    cacheRead.dispose();
    cacheWrite.dispose();
    cacheWrite1h.dispose();
    effectiveDate.dispose();
  }

  static double _parse(String raw) {
    final value = double.tryParse(raw.trim());
    if (value == null || value < 0) throw const FormatException('price');
    return value;
  }

  static String _number(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toString();
  }

  static String _date(int timestampMs) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs).toLocal();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
