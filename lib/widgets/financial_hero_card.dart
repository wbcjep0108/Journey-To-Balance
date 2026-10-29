import 'package:flutter/material.dart';

class FinancialHeroCard extends StatelessWidget {
  const FinancialHeroCard({
    super.key,
    required this.child,
    this.height,
    this.background = const [],
  });

  final Widget child;
  final double? height;
  final List<Widget> background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF333333), Color(0xFF000000)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          ...background,
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
            child: child,
          ),
        ],
      ),
    );
  }
}

class FinancialHeroLabel extends StatelessWidget {
  const FinancialHeroLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Color(0xFFD7DCE5),
        fontSize: 13,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class FinancialHeroAmount extends StatelessWidget {
  const FinancialHeroAmount(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 42,
          height: 1.05,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class FinancialHeroSubtitle extends StatelessWidget {
  const FinancialHeroSubtitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(color: Color(0xFFE2E6EC), fontSize: 16),
    );
  }
}
