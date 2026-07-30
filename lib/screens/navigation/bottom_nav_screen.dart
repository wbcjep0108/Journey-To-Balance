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
    with SingleTickerProviderStateMixin {
  static const _pageTransitionDuration = Duration(milliseconds: 300);
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
  late final Animation<double> _entranceOpacity;
  late final Animation<double> _entranceScale;
  late final Animation<Offset> _entranceSlide;

  int _selectedIndex = 0;
  bool _entranceStarted = false;

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
    super.dispose();
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final pageDuration = reduceMotion ? Duration.zero : _pageTransitionDuration;
    final indicatorDuration = reduceMotion ? Duration.zero : _indicatorDuration;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          _PreservedPageStack(
            pages: _pages,
            selectedIndex: _selectedIndex,
            duration: pageDuration,
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
    required this.duration,
  });

  final List<Widget> pages;
  final int selectedIndex;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var index = 0; index < pages.length; index++)
          IgnorePointer(
            key: ValueKey(index),
            ignoring: index != selectedIndex,
            child: ExcludeSemantics(
              excluding: index != selectedIndex,
              child: AnimatedOpacity(
                opacity: index == selectedIndex ? 1 : 0,
                duration: duration,
                curve: Curves.easeOutCubic,
                child: AnimatedSlide(
                  offset: index == selectedIndex
                      ? Offset.zero
                      : Offset(index < selectedIndex ? -0.045 : 0.045, 0),
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  child: TickerMode(
                    enabled: index == selectedIndex,
                    child: RepaintBoundary(child: pages[index]),
                  ),
                ),
              ),
            ),
          ),
      ],
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
                    opacity: widget.selected ? 1 : (_hovered ? 0.72 : 0.55),
                    duration: _duration,
                    curve: Curves.easeOutCubic,
                    child: TweenAnimationBuilder<Color?>(
                      tween: ColorTween(
                        end: widget.selected
                            ? const Color(0xFF121212)
                            : Colors.grey,
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
