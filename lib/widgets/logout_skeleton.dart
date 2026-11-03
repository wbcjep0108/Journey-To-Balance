import 'package:flutter/material.dart';

import '../screens/auth/login_layout_constants.dart';
import 'skeleton.dart';

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

class LogoutSkeleton extends StatelessWidget {
  const LogoutSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      semanticsLabel: 'Signing out',
      child: AbsorbPointer(
        child: Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, viewport) {
                final availableHeight =
                    viewport.maxHeight - kLoginPaddingTop - kLoginPaddingBottom;
                final minContentHeight = availableHeight > 0
                    ? availableHeight
                    : 0.0;
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    kLoginPaddingH,
                    kLoginPaddingTop,
                    kLoginPaddingH,
                    kLoginPaddingBottom,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: minContentHeight),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: kLoginMaxWidth,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ── Logo badge ──
                            Center(
                              child: SkeletonBlock(
                                width: kLoginLogoSize,
                                height: kLoginLogoSize,
                                radius: kLoginLogoRadius,
                              ),
                            ),
                            // ── Title ──
                            const SizedBox(height: kLoginLogoTitleGap),
                            Center(
                              child: SkeletonBlock(
                                width: kLoginTitleSkeletonWidth,
                                height: kLoginTitleHeight,
                                radius: kLoginTitleHeight / 2,
                              ),
                            ),
                            // ── Tagline ──
                            const SizedBox(height: kLoginTitleTaglineGap),
                            Center(
                              child: SkeletonBlock(
                                width: kLoginTaglineSkeletonWidth,
                                height: kLoginTaglineHeight,
                                radius: kLoginTaglineHeight / 2,
                              ),
                            ),
                            // ── Mode toggle track ──
                            const SizedBox(height: kLoginTaglineToggleGap),
                            const SkeletonBlock(
                              height: kLoginToggleHeight,
                              radius: kLoginToggleRadius,
                            ),
                            // ── Email field ──
                            const SizedBox(height: kLoginToggleFieldGap),
                            const SkeletonBlock(
                              height: kLoginFieldHeight,
                              radius: kLoginFieldRadius,
                            ),
                            // ── Password field ──
                            const SizedBox(height: kLoginFieldFieldGap),
                            const SkeletonBlock(
                              height: kLoginFieldHeight,
                              radius: kLoginFieldRadius,
                            ),
                            // ── Primary button ──
                            const SizedBox(height: kLoginFieldButtonGap),
                            const SkeletonBlock(
                              height: kLoginPrimaryButtonHeight,
                              radius: kLoginButtonRadius,
                              baseColor: Color(0xFFE5E7EB),
                            ),
                            // ── "or" divider row ──
                            const SizedBox(height: kLoginButtonDividerGap),
                            Row(
                              children: [
                                Expanded(
                                  child: SkeletonBlock(height: 1, radius: 0.5),
                                ),
                                const SizedBox(
                                  width: kLoginDividerLabelPadding * 2 + 14,
                                ),
                                Expanded(
                                  child: SkeletonBlock(height: 1, radius: 0.5),
                                ),
                              ],
                            ),
                            // ── Google button ──
                            const SizedBox(height: kLoginDividerGoogleGap),
                            const SkeletonBlock(
                              height: kLoginGoogleButtonHeight,
                              radius: kLoginButtonRadius,
                            ),
                            // ── Terms / help text lines ──
                            const SizedBox(height: kLoginGoogleTermsGap),
                            Center(
                              child: SkeletonBlock(
                                width: kLoginTermsLine1Width,
                                height: kLoginTermsLineHeight,
                                radius: kLoginTermsLineHeight / 2,
                              ),
                            ),
                            const SizedBox(height: kLoginTermsLineGap),
                            Center(
                              child: SkeletonBlock(
                                width: kLoginTermsLine2Width,
                                height: kLoginTermsLineHeight,
                                radius: kLoginTermsLineHeight / 2,
                              ),
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
        ),
      ),
    );
  }
}
