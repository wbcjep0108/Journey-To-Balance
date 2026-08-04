import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/budget_provider.dart';
import '../screens/home/daily_spending_page.dart';

class WeeklySpendingCard extends StatelessWidget {
  const WeeklySpendingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final days = context.watch<BudgetProvider>().weeklySpending;
    final maxAmount = days.fold<double>(
      0,
      (max, day) => day.amount > max ? day.amount : max,
    );
    final hasSpending = maxAmount > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Weekly Spending',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF121212),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Mon – Sun Overview',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 14),
          const _HeaderDivider(),
          const SizedBox(height: 22),
          SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < days.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _DayBar(
                      day: days[i],
                      maxAmount: maxAmount,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!hasSpending) ...[
            const SizedBox(height: 16),
            Text(
              'No spending recorded this week.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderDivider extends StatelessWidget {
  const _HeaderDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Color(0xFF121212),
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: Container(
            height: 1.2,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: const Color(0xFFE5E7EB),
          ),
        ),
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Color(0xFF121212),
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({required this.day, required this.maxAmount});

  final WeeklyDaySpend day;
  final double maxAmount;

  static const double _chartHeight = 96;
  static const double _minBarHeight = 6;

  void _openDay(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DailySpendingPage(day: day.date),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final ratio = maxAmount <= 0
        ? 0.0
        : (day.amount / maxAmount).clamp(0.0, 1.0);
    final targetHeight = day.amount <= 0
        ? _minBarHeight
        : (_minBarHeight + ratio * (_chartHeight - _minBarHeight));

    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: day.amount % 1 == 0 ? 0 : 2,
    ).format(day.amount);

    return Semantics(
      label: '${day.fullLabel}, $currency spent. Double tap to view details.',
      button: true,
      child: Tooltip(
        message: '${day.fullLabel}\n$currency',
        waitDuration: const Duration(milliseconds: 350),
        child: InkWell(
          onTap: () => _openDay(context),
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(
                height: _chartHeight,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: _minBarHeight,
                      end: targetHeight,
                    ),
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 420),
                    curve: Curves.easeOutCubic,
                    builder: (context, height, _) {
                      return AnimatedContainer(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        width: double.infinity,
                        height: height,
                        decoration: BoxDecoration(
                          color: day.isToday
                              ? const Color(0xFF0A0A0A)
                              : const Color(0xFF1A1A1A),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(10),
                          ),
                          border: day.isToday
                              ? Border.all(color: Colors.black, width: 1.2)
                              : null,
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                day.shortLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: day.isToday ? FontWeight.w700 : FontWeight.w600,
                  color: day.isToday
                      ? const Color(0xFF121212)
                      : const Color(0xFF6B7280),
                ),
              ),
              if (day.isToday) ...[
                const SizedBox(height: 4),
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: Color(0xFF121212),
                    shape: BoxShape.circle,
                  ),
                ),
              ] else
                const SizedBox(height: 9),
            ],
          ),
        ),
      ),
    );
  }
}
