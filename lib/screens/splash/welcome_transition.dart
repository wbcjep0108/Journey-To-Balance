import 'package:flutter/material.dart';

import '../../widgets/security_ui.dart';

/// Plays once per signed-in session after PIN unlock, then reveals [child].
class PostLoginWelcome extends StatefulWidget {
  const PostLoginWelcome({super.key, required this.child});

  final Widget child;

  static bool _playedThisSession = false;

  static void resetSession() {
    _playedThisSession = false;
  }

  @override
  State<PostLoginWelcome> createState() => _PostLoginWelcomeState();
}

class _PostLoginWelcomeState extends State<PostLoginWelcome>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _overlayOpacity;
  late final Animation<double> _markOpacity;
  late final Animation<double> _markScale;
  late final Animation<double> _textOpacity;
  late final Animation<Offset> _textSlide;

  bool _showOverlay = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    _markOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.28, curve: Curves.easeOut),
    );
    _markScale = Tween<double>(begin: 0.92, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.34, curve: Curves.easeOutCubic),
      ),
    );
    _textOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.18, 0.42, curve: Curves.easeOut),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.18, 0.46, curve: Curves.easeOutCubic),
      ),
    );
    _overlayOpacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.72, 1, curve: Curves.easeInOutCubic),
      ),
    );

    _controller.addStatusListener((status) {
      if (status != AnimationStatus.completed || !mounted) return;
      PostLoginWelcome._playedThisSession = true;
      setState(() => _showOverlay = false);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_showOverlay || _controller.isAnimating || _controller.isCompleted) {
      return;
    }

    if (PostLoginWelcome._playedThisSession ||
        MediaQuery.disableAnimationsOf(context)) {
      PostLoginWelcome._playedThisSession = true;
      _showOverlay = false;
      _controller.value = 1;
      return;
    }

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_showOverlay)
          IgnorePointer(
            child: FadeTransition(
              opacity: _overlayOpacity,
              child: const ColoredBox(
                color: Colors.white,
                child: SizedBox.expand(),
              ),
            ),
          ),
        if (_showOverlay)
          IgnorePointer(
            child: FadeTransition(
              opacity: _overlayOpacity,
              child: ColoredBox(
                color: Colors.transparent,
                child: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FadeTransition(
                            opacity: _markOpacity,
                            child: ScaleTransition(
                              scale: _markScale,
                              child: const BrandMark(size: 128),
                            ),
                          ),
                          const SizedBox(height: 36),
                          FadeTransition(
                            opacity: _textOpacity,
                            child: SlideTransition(
                              position: _textSlide,
                              child: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'Welcome to your\nJourney to Balance',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 26,
                                    height: 1.3,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.3,
                                    color: Color(0xFF111827),
                                    decoration: TextDecoration.none,
                                    decorationColor: Colors.transparent,
                                  ),
                                ),
                              ),
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
      ],
    );
  }
}
