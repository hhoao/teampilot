import '../cli/registry/capabilities/terminal_composer_region.dart';
import 'fullscreen_input_screen_probe.dart';
import 'fullscreen_pty_delivery_port.dart';
import 'terminal_input_controller.dart';
import 'terminal_screen_probe_controller.dart';

/// [FullscreenPtyDeliveryPort] backed by session input + screen probes.
final class TerminalFullscreenPtyPort implements FullscreenPtyDeliveryPort {
  TerminalFullscreenPtyPort({
    required TerminalInputController input,
    required TerminalScreenProbeController probe,
    required bool Function() aborted,
    required FullscreenComposerRegionSpec composerRegion,
    bool Function()? isAcked,
  }) : _input = input,
       _probe = probe,
       _aborted = aborted,
       _composerRegion = composerRegion,
       _isAcked = isAcked ?? (() => false);

  final TerminalInputController _input;
  final TerminalScreenProbeController _probe;
  final bool Function() _aborted;
  final FullscreenComposerRegionSpec _composerRegion;
  final bool Function() _isAcked;

  /// First composer prefix candidate (may be null when [prefixes] is empty).
  String? get _composerPrefix =>
      _composerRegion.prefixes.isEmpty ? null : _composerRegion.prefixes.first;

  @override
  bool get isAborted => _aborted();

  @override
  bool get isAcked => _isAcked();

  @override
  int get viewportRows => _probe.viewportRows;

  @override
  FullscreenComposerRegionSpec get composerRegion => _composerRegion;

  @override
  Future<void> syncDisplayGrid() => _probe.syncDisplayGrid();

  @override
  ComposerRegion? locateComposerRegion({int scanRows = 24}) =>
      _probe.locateComposerRegion(_composerRegion, scanRows: scanRows);

  @override
  bool regionContainsNeedle(ComposerRegion region, String needle) =>
      _probe.regionContainsNeedle(region, needle);

  @override
  bool isComposerRegionEmpty(ComposerRegion region) =>
      _probe.isComposerRegionEmpty(region, _composerRegion);

  @override
  bool needleAppearsOutsideRegion(
    ComposerRegion region,
    String needle, {
    int scanRows = 24,
  }) =>
      _probe.needleAppearsOutsideRegion(
        region,
        needle,
        scanRows: scanRows,
      );

  @override
  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24}) =>
      _probe.locateFullscreenPromptNeedle(
        needle,
        scanRows: scanRows,
        composerPrefix: _composerPrefix,
      );

  @override
  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24}) =>
      _probe.locateCollapsedPasteNeedle(
        scanRows: scanRows,
        composerPrefix: _composerPrefix,
      );

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) =>
      _probe.isFullscreenPromptAtAnchor(anchor, composerPrefix: _composerPrefix);

  @override
  Future<void> clearStagedInput() => _input.clearStagedInput();

  @override
  Future<void> pasteText(String text) => _input.pasteText(text);

  @override
  Future<void> submitCr() => _input.submitPendingCr();

  @override
  String describeProbeWindow({int scanRows = 24}) =>
      _probe.describeProbeWindow(scanRows: scanRows);
}
