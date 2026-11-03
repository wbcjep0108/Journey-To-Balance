import 'dart:async';

import 'package:flutter/material.dart';

class SkeletonSwitcher extends StatefulWidget {
  const SkeletonSwitcher({
    super.key,
    required this.loading,
    required this.skeleton,
    required this.child,
    this.delay = const Duration(milliseconds: 150),
    this.minimumDisplayDuration = const Duration(milliseconds: 400),
    this.fadeDuration = const Duration(milliseconds: 180),
  });

  final bool loading;
  final Widget skeleton;
  final Widget child;
  final Duration delay;
  final Duration minimumDisplayDuration;
  final Duration fadeDuration;

  @override
  State<SkeletonSwitcher> createState() => _SkeletonSwitcherState();
}

class _SkeletonSwitcherState extends State<SkeletonSwitcher> {
  Timer? _delayTimer;
  Timer? _minimumTimer;
  bool _minimumElapsed = false;
  bool _showSkeleton = false;

  @override
  void initState() {
    super.initState();
    if (widget.loading) {
      _scheduleSkeleton();
    }
  }

  @override
  void didUpdateWidget(covariant SkeletonSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loading == widget.loading) return;
    if (widget.loading) {
      _scheduleSkeleton();
    } else {
      _scheduleContent();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) && !widget.loading) {
      _delayTimer?.cancel();
      _minimumTimer?.cancel();
      _showSkeleton = false;
      _minimumElapsed = false;
    }
  }

  void _scheduleSkeleton() {
    _delayTimer?.cancel();
    _minimumTimer?.cancel();
    _minimumElapsed = false;
    _showSkeleton = false;
    _delayTimer = Timer(widget.delay, () {
      if (!mounted || !widget.loading) return;
      setState(() {
        _showSkeleton = true;
      });
      _minimumTimer = Timer(widget.minimumDisplayDuration, () {
        if (!mounted) return;
        _minimumElapsed = true;
        if (!widget.loading) {
          setState(() => _showSkeleton = false);
        }
      });
    });
  }

  void _scheduleContent() {
    _delayTimer?.cancel();
    if (!_showSkeleton || MediaQuery.disableAnimationsOf(context)) {
      _minimumTimer?.cancel();
      setState(() {
        _showSkeleton = false;
        _minimumElapsed = false;
      });
      return;
    }

    if (_minimumElapsed) {
      setState(() {
        _showSkeleton = false;
        _minimumElapsed = false;
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _minimumTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion ? Duration.zero : widget.fadeDuration;
    final Widget current;
    if (_showSkeleton) {
      current = KeyedSubtree(
        key: const ValueKey('skeleton-switcher-skeleton'),
        child: widget.skeleton,
      );
    } else if (widget.loading) {
      current = const SizedBox.shrink(key: ValueKey('skeleton-switcher-delay'));
    } else {
      current = KeyedSubtree(
        key: const ValueKey('skeleton-switcher-content'),
        child: widget.child,
      );
    }

    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeOut,
      child: current,
    );
  }
}

class SkeletonShimmer extends StatefulWidget {
  const SkeletonShimmer({
    super.key,
    required this.child,
    this.semanticsLabel = 'Loading',
  });

  final Widget child;
  final String semanticsLabel;

  @override
  State<SkeletonShimmer> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<SkeletonShimmer>
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
      _controller
        ..stop()
        ..value = 0;
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
    final staticOnly = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: widget.semanticsLabel,
      liveRegion: true,
      container: true,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _controller,
          child: widget.child,
          builder: (context, child) => _SkeletonScope(
            progress: _controller.value,
            staticOnly: staticOnly,
            child: child!,
          ),
        ),
      ),
    );
  }
}

class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({
    super.key,
    this.width,
    required this.height,
    this.radius = 8,
    this.baseColor = const Color(0xFFF1F2F4),
  });

  final double? width;
  final double height;
  final double radius;
  final Color baseColor;

  @override
  Widget build(BuildContext context) {
    final scope = _SkeletonScope.maybeOf(context);
    final staticOnly = scope?.staticOnly ?? true;
    final progress = scope?.progress ?? 0;
    final position = (progress * 2) - 1;
    final decoration = staticOnly
        ? BoxDecoration(
            color: baseColor,
            borderRadius: BorderRadius.circular(radius),
          )
        : BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment(position - 1, 0),
              end: Alignment(position + 1, 0),
              colors: [baseColor, const Color(0xFFE5E7EB), baseColor],
              stops: const [0.25, 0.5, 0.75],
            ),
          );
    return Container(width: width, height: height, decoration: decoration);
  }
}

class SkeletonLine extends StatelessWidget {
  const SkeletonLine({super.key, this.width, this.height = 12, this.radius});

  final double? width;
  final double height;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return SkeletonBlock(
      width: width,
      height: height,
      radius: radius ?? height / 2,
    );
  }
}

class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SkeletonBlock(width: size, height: size, radius: size / 2);
  }
}

class _SkeletonScope extends InheritedWidget {
  const _SkeletonScope({
    required this.progress,
    required this.staticOnly,
    required super.child,
  });

  final double progress;
  final bool staticOnly;

  static _SkeletonScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_SkeletonScope>();
  }

  @override
  bool updateShouldNotify(_SkeletonScope oldWidget) {
    return progress != oldWidget.progress || staticOnly != oldWidget.staticOnly;
  }
}
