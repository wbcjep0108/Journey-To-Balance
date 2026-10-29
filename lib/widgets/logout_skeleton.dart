import 'package:flutter/material.dart';

import '../screens/auth/login_layout_constants.dart';

class LogoutTransitionView extends StatelessWidget {
  const LogoutTransitionView({
    super.key,
    required this.showLogin,
    required this.loginScreen,
    required this.onFinished,
  });

  final bool showLogin;
  final Widget loginScreen;
  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!showLogin) {
      return const LogoutSkeleton(key: ValueKey('logout-skeleton'));
    }
    if (reduceMotion && showLogin) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onFinished());
      return KeyedSubtree(
        key: const ValueKey('logout-login-screen'),
        child: loginScreen,
      );
    }
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 200);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOut,
      onEnd: onFinished,
      builder: (context, value, _) => Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(
            excluding: showLogin,
            child: Opacity(
              opacity: 1 - value,
              child: const LogoutSkeleton(key: ValueKey('logout-skeleton')),
            ),
          ),
          IgnorePointer(
            ignoring: !showLogin,
            child: ExcludeSemantics(
              excluding: !showLogin,
              child: Opacity(
                opacity: value,
                child: KeyedSubtree(
                  key: const ValueKey('logout-login-screen'),
                  child: loginScreen,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LogoutSkeleton extends StatefulWidget {
  const LogoutSkeleton({super.key});

  @override
  State<LogoutSkeleton> createState() => _LogoutSkeletonState();
}

class _LogoutSkeletonState extends State<LogoutSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'Signing out',
      liveRegion: true,
      container: true,
      child: AbsorbPointer(
        child: Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                kLoginPaddingH,
                kLoginPaddingTop,
                kLoginPaddingH,
                kLoginPaddingBottom,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: kLoginMaxWidth),
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Logo badge ──
                        Center(
                          child: _SkeletonBlock(
                            width: kLoginLogoSize,
                            height: kLoginLogoSize,
                            radius: kLoginLogoRadius,
                            progress: _controller.value,
                            staticOnly: reduceMotion,
                          ),
                        ),
                        // ── Title ──
                        const SizedBox(height: kLoginLogoTitleGap),
                        Center(
                          child: _SkeletonBlock(
                            width: kLoginTitleSkeletonWidth,
                            height: kLoginTitleHeight,
                            radius: kLoginTitleHeight / 2,
                            progress: _controller.value,
                            staticOnly: reduceMotion,
                          ),
                        ),
                        // ── Tagline ──
                        const SizedBox(height: kLoginTitleTaglineGap),
                        Center(
                          child: _SkeletonBlock(
                            width: kLoginTaglineSkeletonWidth,
                            height: kLoginTaglineHeight,
                            radius: kLoginTaglineHeight / 2,
                            progress: _controller.value,
                            staticOnly: reduceMotion,
                          ),
                        ),
                        // ── Mode toggle track ──
                        const SizedBox(height: kLoginTaglineToggleGap),
                        _SkeletonBlock(
                          height: kLoginToggleHeight,
                          radius: kLoginToggleRadius,
                          progress: _controller.value,
                          staticOnly: reduceMotion,
                        ),
                        // ── Email field ──
                        const SizedBox(height: kLoginToggleFieldGap),
                        _SkeletonBlock(
                          height: kLoginFieldHeight,
                          radius: kLoginFieldRadius,
                          progress: _controller.value,
                          staticOnly: reduceMotion,
                        ),
                        // ── Password field ──
                        const SizedBox(height: kLoginFieldFieldGap),
                        _SkeletonBlock(
                          height: kLoginFieldHeight,
                          radius: kLoginFieldRadius,
                          progress: _controller.value,
                          staticOnly: reduceMotion,
                        ),
                        // ── Primary button ──
                        const SizedBox(height: kLoginFieldButtonGap),
                        _SkeletonBlock(
                          height: kLoginPrimaryButtonHeight,
                          radius: kLoginButtonRadius,
                          baseColor: const Color(0xFFE5E7EB),
                          progress: _controller.value,
                          staticOnly: reduceMotion,
                        ),
                        // ── "or" divider row ──
                        const SizedBox(height: kLoginButtonDividerGap),
                        Row(
                          children: [
                            Expanded(
                              child: _SkeletonBlock(
                                height: 1,
                                radius: 0.5,
                                progress: _controller.value,
                                staticOnly: reduceMotion,
                              ),
                            ),
                            const SizedBox(
                              width: kLoginDividerLabelPadding * 2 + 14,
                            ),
                            Expanded(
                              child: _SkeletonBlock(
                                height: 1,
                                radius: 0.5,
                                progress: _controller.value,
                                staticOnly: reduceMotion,
                              ),
                            ),
                          ],
                        ),
                        // ── Google button ──
                        const SizedBox(height: kLoginDividerGoogleGap),
                        _SkeletonBlock(
                          height: kLoginGoogleButtonHeight,
                          radius: kLoginButtonRadius,
                          progress: _controller.value,
                          staticOnly: reduceMotion,
                        ),
                        // ── Terms / help text lines ──
                        const SizedBox(height: kLoginGoogleTermsGap),
                        Center(
                          child: _SkeletonBlock(
                            width: kLoginTermsLine1Width,
                            height: kLoginTermsLineHeight,
                            radius: kLoginTermsLineHeight / 2,
                            progress: _controller.value,
                            staticOnly: reduceMotion,
                          ),
                        ),
                        const SizedBox(height: kLoginTermsLineGap),
                        Center(
                          child: _SkeletonBlock(
                            width: kLoginTermsLine2Width,
                            height: kLoginTermsLineHeight,
                            radius: kLoginTermsLineHeight / 2,
                            progress: _controller.value,
                            staticOnly: reduceMotion,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    this.width,
    required this.height,
    required this.radius,
    required this.progress,
    required this.staticOnly,
    this.baseColor = const Color(0xFFF1F2F4),
  });

  final double? width;
  final double height;
  final double radius;
  final double progress;
  final bool staticOnly;
  final Color baseColor;

  @override
  Widget build(BuildContext context) {
    final highlight = staticOnly ? baseColor : const Color(0xFFE5E7EB);
    final position = (progress * 2) - 1;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment(position - 1, 0),
          end: Alignment(position + 1, 0),
          colors: [baseColor, highlight, baseColor],
          stops: const [0.25, 0.5, 0.75],
        ),
      ),
    );
  }
}
