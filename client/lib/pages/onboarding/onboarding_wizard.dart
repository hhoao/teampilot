import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/workspace_surface_layers.dart';
import 'steps/appearance_step.dart';
import 'steps/cli_step.dart';
import 'steps/default_preset_step.dart';
import 'steps/provider_import_step.dart';
import 'steps/ssh_step.dart';

enum OnboardingStepKind {
  appearance,
  ssh,
  cli,
  providerImport,
  defaultPreset,
}

List<OnboardingStepKind> onboardingStepsForPlatform() {
  if (Platform.isAndroid) {
    return const [
      OnboardingStepKind.appearance,
      OnboardingStepKind.ssh,
      OnboardingStepKind.cli,
      OnboardingStepKind.providerImport,
      OnboardingStepKind.defaultPreset,
    ];
  }
  return const [
    OnboardingStepKind.appearance,
    OnboardingStepKind.cli,
    OnboardingStepKind.providerImport,
    OnboardingStepKind.defaultPreset,
  ];
}

class OnboardingWizard extends StatefulWidget {
  const OnboardingWizard({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends State<OnboardingWizard> {
  static const _pageAnimationDuration = Duration(milliseconds: 300);
  static const _minPageViewportHeight = 280;
  static const _maxPageViewportHeight = 520;
  static const _footerReserve = 96;

  late final List<OnboardingStepKind> _steps;
  late final List<GlobalKey> _stepMeasureKeys;
  late final PageController _pageController;
  final _defaultPresetKey = GlobalKey<OnboardingDefaultPresetStepState>();
  final _cachedStepHeights = <int, double>{};
  var _pageIndex = 0;
  var _isAnimating = false;
  var _pageViewportHeight = _minPageViewportHeight.toDouble();

  @override
  void initState() {
    super.initState();
    _steps = onboardingStepsForPlatform();
    _stepMeasureKeys = List.generate(_steps.length, (_) => GlobalKey());
    _pageController = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncViewportHeightForPage(_pageIndex);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _isFirstStep => _pageIndex <= 0;
  bool get _isLastStep => _pageIndex >= _steps.length - 1;

  Future<void> _goPrevious() async {
    if (_isAnimating || _isFirstStep) return;
    await _animateToPage(_pageIndex - 1);
  }

  Future<void> _goNext() async {
    if (_isAnimating) return;
    if (_isLastStep) {
      await _defaultPresetKey.currentState?.commitSelection();
      if (!mounted) return;
      widget.onComplete();
      return;
    }
    await _animateToPage(_pageIndex + 1);
  }

  void _skip() => unawaited(_goNext());

  Future<void> _animateToPage(int page) async {
    if (!_pageController.hasClients) return;
    setState(() => _isAnimating = true);
    await _pageController.animateToPage(
      page,
      duration: _pageAnimationDuration,
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
    setState(() {
      _pageIndex = page;
      _isAnimating = false;
    });
    _syncViewportHeightForPage(page);
  }

  void _invalidateStepHeightCache(int index) {
    _cachedStepHeights.remove(index);
    if (index == _pageIndex) {
      _syncViewportHeightForPage(index);
    }
  }

  void _syncViewportHeightForPage(int index) {
    if (!mounted || _isAnimating) return;

    final cached = _cachedStepHeights[index];
    if (cached != null) {
      final nextHeight = cached.clamp(
        _minPageViewportHeight.toDouble(),
        _maxPageViewportHeight.toDouble(),
      );
      if ((_pageViewportHeight - nextHeight).abs() > 1) {
        setState(() => _pageViewportHeight = nextHeight);
      }
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isAnimating) return;
      final box =
          _stepMeasureKeys[index].currentContext?.findRenderObject()
              as RenderBox?;
      if (box == null || !box.hasSize) return;

      final measured = box.size.height.clamp(
        _minPageViewportHeight.toDouble(),
        _maxPageViewportHeight.toDouble(),
      );
      _cachedStepHeights[index] = measured;
      if ((_pageViewportHeight - measured).abs() <= 1) return;
      setState(() => _pageViewportHeight = measured);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final navigationLocked = _isAnimating;

    return Scaffold(
      backgroundColor: cs.workspacePage,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxViewportHeight = math
                .min(
                  _maxPageViewportHeight.toDouble(),
                  constraints.maxHeight - _footerReserve,
                )
                .clamp(
                  _minPageViewportHeight.toDouble(),
                  _maxPageViewportHeight.toDouble(),
                );
            final viewportHeight = math.min(_pageViewportHeight, maxViewportHeight);

            return ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AnimatedSize(
                          duration: _pageAnimationDuration,
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            height: viewportHeight,
                            child: PageView.builder(
                              controller: _pageController,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _steps.length,
                              itemBuilder: (context, index) {
                                return _OnboardingStepPage(
                                  child: NotificationListener<
                                      SizeChangedLayoutNotification>(
                                    onNotification: (_) {
                                      if (index == _pageIndex) {
                                        _invalidateStepHeightCache(index);
                                      }
                                      return false;
                                    },
                                    child: SizeChangedLayoutNotifier(
                                      child: Align(
                                        alignment: Alignment.topCenter,
                                        child: SingleChildScrollView(
                                          child: KeyedSubtree(
                                            key: _stepMeasureKeys[index],
                                            child: _buildStep(
                                              _steps[index],
                                              isActive: index == _pageIndex,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            TextButton(
                              onPressed: navigationLocked ? null : _skip,
                              child: Text(l10n.onboardingSkip),
                            ),
                            const Spacer(),
                            if (!_isFirstStep) ...[
                              OutlinedButton(
                                onPressed: navigationLocked
                                    ? null
                                    : () => unawaited(_goPrevious()),
                                child: Text(l10n.onboardingPrevious),
                              ),
                              const SizedBox(width: 12),
                            ],
                            FilledButton(
                              onPressed: navigationLocked
                                  ? null
                                  : () => unawaited(_goNext()),
                              child: Text(
                                _isLastStep
                                    ? l10n.onboardingGetStarted
                                    : l10n.onboardingNext,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStep(OnboardingStepKind kind, {required bool isActive}) {
    return switch (kind) {
      OnboardingStepKind.appearance => OnboardingAppearanceStep(
        isActive: isActive,
      ),
      OnboardingStepKind.ssh => OnboardingSshStep(
        isActive: isActive,
        onContinue: () => unawaited(_goNext()),
      ),
      OnboardingStepKind.cli => OnboardingCliStep(isActive: isActive),
      OnboardingStepKind.providerImport => OnboardingProviderImportStep(
        isActive: isActive,
      ),
      OnboardingStepKind.defaultPreset => OnboardingDefaultPresetStep(
        key: _defaultPresetKey,
        isActive: isActive,
      ),
    };
  }
}

class _OnboardingStepPage extends StatefulWidget {
  const _OnboardingStepPage({required this.child});

  final Widget child;

  @override
  State<_OnboardingStepPage> createState() => _OnboardingStepPageState();
}

class _OnboardingStepPageState extends State<_OnboardingStepPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
