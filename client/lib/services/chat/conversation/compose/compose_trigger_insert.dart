import 'package:flutter/material.dart';

import 'compose_trigger_query.dart';

class ComposeTriggerInsertion {
  const ComposeTriggerInsertion({required this.text, this.suffix = ' '});

  final String text;
  final String suffix;
}

/// Replaces the active trigger token with [insertion].
TextEditingValue replaceComposeTrigger(
  TextEditingController controller,
  ComposeTriggerQuery trigger,
  ComposeTriggerInsertion insertion,
) {
  final value = controller.value;
  final chunk = '${insertion.text}${insertion.suffix}';
  final newText = value.text.replaceRange(
    trigger.triggerStart,
    trigger.triggerEnd,
    chunk,
  );
  final newOffset = trigger.triggerStart + chunk.length;
  return value.copyWith(
    text: newText,
    selection: TextSelection.collapsed(offset: newOffset),
    composing: TextRange.empty,
  );
}
