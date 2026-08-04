import 'package:flutter/material.dart';

import '../account/account_page.dart';
import '../bills/bills_page.dart';
import '../home/home_page.dart';
import '../personal/personal_page.dart';
import '../savings/savings_page.dart';

class BottomNavScreen extends StatefulWidget {
  const BottomNavScreen({super.key});

  @override
  State<BottomNavScreen> createState() => _BottomNavScreenState();
}

class _BottomNavScreenState extends State<BottomNavScreen>
    with TickerProviderStateMixin {
  static const _pageTransitionDuration = Duration(milliseconds: 360);
  static const _indicatorDuration = Duration(milliseconds: 420);

  final List<Widget> _pages = const [
    HomePage(),
    BillsPage(),
    SavingsPage(),
    PersonalPage(),
    AccountPage(),
  ];

  final List<_NavDestination> _destinations = const [
    _NavDestination('Home', 'assets/images/icons/home.png'),
    _NavDestination('Bills', 'assets/images/icons/bills.png'),
    _NavDestination('Savings', 'assets/images/icons/savings.png'),
    _NavDestination('Personal', 'assets/images/icons/personal.png'),
    _NavDestination('Account', 'assets/images/icons/account.png'),
  ];

  late final AnimationController _entranceController;
  late final AnimationController _pageController;
  late final Animation<double> _entranceOpacity;
  late final Animation<double> _entranceScale;
  late final Animation<Offset> _entranceSlide;
  late final Animation<double> _pageCurve;

  int _selectedIndex = 0;
  int _previousIndex = 0;
  /// 1 = navigate toward a right tab, -1 = toward a left tab.
  int _slideDirection = 1;
  bool _entranceStarted = false;
  bool _isTransitioning = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    final entranceCurve = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutExpo,
    );
    _entranceOpacity = entranceCurve;
    _entranceScale = Tween<double>(begin: 0.96, end: 1).animate(entranceCurve);
    _entranceSlide = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(entranceCurve);

    _pageController = AnimationController(
      vsync: this,
      duration: _pageTransitionDuration,
      value: 1,
    );
    _pageCurve = CurvedAnimation(
      parent: _pageController,
      curve: Curves.easeInOutCubic,
    );
    _pageController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _isTransitioning = false);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entranceStarted) return;
    _entranceStarted = true;

    if (MediaQuery.disableAnimationsOf(context)) {
      _entranceController.value = 1;
    } else {
      _entranceController.forward();
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex || _isTransitioning) return;

    final direction = index > _selectedIndex ? 1 : -1;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      setState(() {
        _previousIndex = _selectedIndex;
        _selectedIndex = index;
        _slideDirection = direction;
        _isTransitioning = false;
      });
      _pageController.value = 1;
      return;
    }

    setState(() {
      _previousIndex = _selectedIndex;
      _selectedIndex = index;
      _slideDirection = direction;
      _isTransitioning = true;
    });
    _pageController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final indicatorDuration = reduceMotion ? Duration.zero : _indicatorDuration;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          _PreservedPageStack(
            pages: _pages,
            selectedIndex: _selectedIndex,
            previousIndex: _previousIndex,
            isTransitioning: _isTransitioning,
            slideDirection: _slideDirection,
            animation: _pageCurve,
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: SafeArea(
              child: FadeTransition(
                opacity: _entranceOpacity,
                child: SlideTransition(
                  position: _entranceSlide,
                  child: ScaleTransition(
                    scale: _entranceScale,
                    child: _AnimatedNavigationBar(
                      destinations: _destinations,
                      selectedIndex: _selectedIndex,
                      indicatorDuration: indicatorDuration,
                      reduceMotion: reduceMotion,
                      onSelected: _onItemTapped,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreservedPageStack extends StatelessWidget {
  const _PreservedPageStack({
    required this.pages,
    required this.selectedIndex,
    required this.previousIndex,
    required this.isTransitioning,
    required this.slideDirection,
    required this.animation,
  });

  final List<Widget> pages;
  final int selectedIndex;
  final int previousIndex;
  final bool isTransitioning;
  final int slideDirection;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (var index = 0; index < pages.length; index++)
                _buildPageLayer(index),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPageLayer(int index) {
    final isIncoming = index == selectedIndex;
    final isOutgoing =
        isTransitioning &&
        index == previousIndex &&
        previousIndex != selectedIndex;
    final isVisible = isIncoming || isOutgoing;

    late final double opacity;
    late final Offset translation;

    if (isIncoming) {
      if (isTransitioning && previousIndex != selectedIndex) {
        // Right tab: enter from right. Left tab: enter from left.
        translation = Offset(slideDirection * (1 - animation.value), 0);
        opacity = 0.3 + (0.7 * animation.value);
      } else {
        translation = Offset.zero;
        opacity = 1;
      }
    } else if (isOutgoing) {
      // Right tab: exit left. Left tab: exit right.
      translation = Offset(-slideDirection * animation.value, 0);
      opacity = (1 - animation.value).clamp(0.0, 1.0);
    } else {
      translation = Offset.zero;
      opacity = 0;
    }

    return IgnorePointer(
      key: ValueKey(index),
      ignoring: index != selectedIndex,
      child: ExcludeSemantics(
        excluding: index != selectedIndex,
        child: Offstage(
          offstage: !isVisible,
          child: TickerMode(
            enabled: isVisible,
            child: Opacity(
              opacity: opacity,
              child: FractionalTranslation(
                translation: translation,
                child: RepaintBoundary(child: pages[index]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedNavigationBar extends StatelessWidget {
  const _AnimatedNavigationBar({
    required this.destinations,
    required this.selectedIndex,
    required this.indicatorDuration,
    required this.reduceMotion,
    required this.onSelected,
  });

  static const double _itemSize = 44;

  final List<_NavDestination> destinations;
  final int selectedIndex;
  final Duration indicatorDuration;
  final bool reduceMotion;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final travelDistance = constraints.maxWidth - _itemSize;
          final indicatorLeft =
              travelDistance * selectedIndex / (destinations.length - 1);

          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              AnimatedPositioned(
                left: indicatorLeft,
                top: 14,
                width: _itemSize,
                height: _itemSize,
                duration: indicatorDuration,
                curve: Curves.easeOutCubic,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF121212).withValues(alpha: 0.09),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var index = 0; index < destinations.length; index++)
                    _AnimatedNavItem(
                      destination: destinations[index],
                      selected: selectedIndex == index,
                      reduceMotion: reduceMotion,
                      onTap: () => onSelected(index),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AnimatedNavItem extends StatefulWidget {
  const _AnimatedNavItem({
    required this.destination,
    required this.selected,
    required this.reduceMotion,
    required this.onTap,
  });

  final _NavDestination destination;
  final bool selected;
  final bool reduceMotion;
  final VoidCallback onTap;

  @override
  State<_AnimatedNavItem> createState() => _AnimatedNavItemState();
}

class _AnimatedNavItemState extends State<_AnimatedNavItem> {
  bool _pressed = false;
  bool _hovered = false;

  Duration get _duration =>
      widget.reduceMotion ? Duration.zero : const Duration(milliseconds: 280);

  double get _scale {
    if (_pressed) return 0.92;
    if (_hovered) return widget.selected ? 1.04 : 0.96;
    return widget.selected ? 1 : 0.9;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.destination.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: SizedBox(
            width: 44,
            height: 72,
            child: Center(
              child: AnimatedScale(
                scale: _scale,
                duration: _duration,
                curve: widget.selected
                    ? Curves.easeOutBack
                    : Curves.easeOutCubic,
                child: AnimatedSlide(
                  offset: widget.selected
                      ? const Offset(0, -0.08)
                      : Offset.zero,
                  duration: _duration,
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: widget.selected ? 1 : (_hovered ? 0.88 : 0.78),
                    duration: _duration,
                    curve: Curves.easeOutCubic,
                    child: TweenAnimationBuilder<Color?>(
                      tween: ColorTween(
                        end: widget.selected
                            ? const Color(0xFF121212)
                            : const Color(0xFF6B7280),
                      ),
                      duration: _duration,
                      curve: Curves.easeOutCubic,
                      builder: (context, color, _) => Image.asset(
                        widget.destination.assetPath,
                        width: 24,
                        height: 24,
                        color: color,
                      ),
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

class _NavDestination {
  const _NavDestination(this.label, this.assetPath);

  final String label;
  final String assetPath;
}
