import '../../../../models/hook_entry.dart';
import '../../../../models/hook_event.dart';
import '../../registry/capabilities/hook_capability.dart';

/// Gemini has no native hook config surface in this phase; render is a no-op
/// and no events are claimed.
final class GeminiHookWriter implements HookCapability {
  const GeminiHookWriter();

  @override
  String? nativeEvent(HookEvent event) => null;

  @override
  bool get supportsMatcher => false;

  @override
  bool get supportsHttp => false;

  @override
  bool get supportsPolicy => false;

  @override
  bool supportsEvent(HookEvent event) => false;

  @override
  HookWriteResult render({
    required List<HookEntry> entries,
    required HookRenderContext ctx,
  }) => const HookWriteResult();
}
