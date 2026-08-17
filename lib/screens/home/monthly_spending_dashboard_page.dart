import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/monthly_spending_stats.dart';
import '../../providers/budget_provider.dart';
import '../../widgets/barrier_blur.dart';
import 'daily_spending_page.dart';

class MonthlySpendingDashboardPage extends StatefulWidget {
  const MonthlySpendingDashboardPage({super.key});

  @override
  State<MonthlySpendingDashboardPage> createState() =>
      _MonthlySpendingDashboardPageState();
}

class _MonthlySpendingDashboardPageState
    extends State<MonthlySpendingDashboardPage> {
  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
      );
    });
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(
        _selectedMonth.year,
        _selectedMonth.month,
        1,
      ),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Select month',
      initialDatePickerMode: DatePickerMode.year,
      builder: (context, child) => withBarrierBlur(child!),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedMonth = DateTime(picked.year, picked.month);
    });
  }

  @override
  Widget build(BuildContext context) {
    final budget = context.watch<BudgetProvider>();
    final stats = MonthlySpendingStats.fromBudget(
      budget: budget,
      month: _selectedMonth,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Monthly Spending Dashboard',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: Colors.black,
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final padding = EdgeInsets.fromLTRB(
              wide ? 28 : 16,
              8,
              wide ? 28 : 16,
              28,
            );

            final calendar = _CalendarHeatmapPanel(
              stats: stats,
              onPrevMonth: () => _shiftMonth(-1),
              onNextMonth: () => _shiftMonth(1),
              onPickMonth: _pickMonth,
              onDayTap: (day) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DailySpendingPage(day: day),
                  ),
                );
              },
            );

            final summary = _SummaryAndBreakdownPanel(stats: stats);

            if (wide) {
              return SingleChildScrollView(
                padding: padding,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: calendar),
                    const SizedBox(width: 24),
                    Expanded(child: summary),
                  ],
                ),
              );
            }

            return ListView(
              padding: padding,
              children: [
                calendar,
                const SizedBox(height: 24),
                summary,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CalendarHeatmapPanel extends StatelessWidget {
  const _CalendarHeatmapPanel({
    required this.stats,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onPickMonth,
    required this.onDayTap,
  });

  final MonthlySpendingStats stats;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onPickMonth;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onPrevMonth,
                icon: const Icon(Icons.chevron_left),
                color: Colors.black87,
              ),
              Expanded(
                child: InkWell(
                  onTap: onPickMonth,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      stats.monthYearLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: onNextMonth,
                icon: const Icon(Icons.chevron_right),
                color: Colors.black87,
              ),
            ],
          ),
          const SizedBox(height: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              // Swipe left → next month; swipe right → previous month.
              if (velocity <= -200) {
                onNextMonth();
              } else if (velocity >= 200) {
                onPrevMonth();
              }
            },
            child: _MonthCalendarGrid(stats: stats, onDayTap: onDayTap),
          ),
          const SizedBox(height: 20),
          const _SpendingLevelKey(),
        ],
      ),
    );
  }
}

class _MonthCalendarGrid extends StatelessWidget {
  const _MonthCalendarGrid({
    required this.stats,
    required this.onDayTap,
  });

  final MonthlySpendingStats stats;
  final ValueChanged<DateTime> onDayTap;

  static const _weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  @override
  Widget build(BuildContext context) {
    final year = stats.month.year;
    final month = stats.month.month;
    final daysInMonth = DateUtils.getDaysInMonth(year, month);
    final firstWeekday = DateTime(year, month, 1).weekday % 7; // Sun=0
    final today = DateTime.now();
    final cells = <Widget>[];

    for (final label in _weekdayLabels) {
      cells.add(
        Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
          ),
        ),
      );
    }

    for (var i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }

    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(year, month, day);
      final intensity =
          stats.intensityByDay[date] ?? SpendingIntensity.none;
      final isToday =
          today.year == year && today.month == month && today.day == day;
      final amount = stats.dailyTotals[date] ?? 0;

      cells.add(
        _DayCell(
          day: day,
          intensity: intensity,
          isToday: isToday,
          amount: amount,
          onTap: () => onDayTap(date),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1,
        children: cells,
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.intensity,
    required this.isToday,
    required this.amount,
    required this.onTap,
  });

  final int day;
  final SpendingIntensity intensity;
  final bool isToday;
  final double amount;
  final VoidCallback onTap;

  Color get _dotColor {
    return switch (intensity) {
      SpendingIntensity.none => Colors.transparent,
      SpendingIntensity.minimal => const Color(0xFFD1D5DB),
      SpendingIntensity.average => const Color(0xFF9CA3AF),
      SpendingIntensity.significant => const Color(0xFF111827),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Tooltip(
          message: amount > 0
              ? '₱${NumberFormat('#,##0.##').format(amount)}'
              : 'No spending',
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: isToday
                  ? Border.all(color: Colors.black87, width: 1.2)
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SpendingLevelKey extends StatelessWidget {
  const _SpendingLevelKey();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SPENDING LEVEL KEY',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 14),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _LegendItem(
                color: Color(0xFFD1D5DB),
                label: 'MINIMAL',
              ),
              _LegendItem(
                color: Color(0xFF9CA3AF),
                label: 'AVERAGE',
              ),
              _LegendItem(
                color: Color(0xFF111827),
                label: 'SIGNIFICANT',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }
}

class _SummaryAndBreakdownPanel extends StatelessWidget {
  const _SummaryAndBreakdownPanel({required this.stats});

  final MonthlySpendingStats stats;

  String get _currency =>
      '₱${NumberFormat('#,##0').format(stats.total.round())}';

  String get _avg =>
      '₱${NumberFormat('#,##0').format(stats.avgDaily.round())}';

  String get _highest {
    final day = stats.highestDay;
    if (day == null) return '—';
    return DateFormat('MMM d').format(day);
  }

  String get _lowest {
    if (stats.lowestDays.isEmpty) return '—';
    final monthLabel = DateFormat('MMM').format(stats.lowestDays.first);
    final days = stats.lowestDays.map((d) => '${d.day}').join(', ');
    return '$monthLabel $days';
  }

  @override
  Widget build(BuildContext context) {
    void openDay(DateTime day) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DailySpendingPage(day: day),
        ),
      );
    }

    Future<void> openLowestDays() async {
      final days = stats.lowestDays;
      if (days.isEmpty) return;
      if (days.length == 1) {
        openDay(days.first);
        return;
      }

      final picked = await showModalBottomSheet<DateTime>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          return withBarrierBlur(
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Lowest spending days',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...days.map(
                        (day) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            DateFormat('EEEE, MMM d').format(day),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(sheetContext).pop(day),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            alignment: Alignment.bottomCenter,
          );
        },
      );

      if (picked != null && context.mounted) {
        openDay(picked);
      }
    }

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Monthly Summary',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            stats.summaryMonthLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 16),
          _SummaryRow(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Total Spending',
            value: _currency,
          ),
          const SizedBox(height: 10),
          _SummaryRow(
            icon: Icons.payments_outlined,
            label: 'Avg. Daily Spend',
            value: _avg,
          ),
          const SizedBox(height: 10),
          _SummaryRow(
            icon: Icons.calendar_today_outlined,
            label: 'Highest Spending Day',
            value: _highest,
            valueColor: const Color(0xFFDC2626),
            onValueTap: stats.highestDay == null
                ? null
                : () => openDay(stats.highestDay!),
          ),
          const SizedBox(height: 10),
          _SummaryRow(
            icon: Icons.shopping_cart_outlined,
            label: 'Lowest Spending Days',
            value: _lowest,
            valueColor: const Color(0xFFD6C4A3),
            onValueTap:
                stats.lowestDays.isEmpty ? null : openLowestDays,
          ),
          const SizedBox(height: 28),
          const Text(
            'Spending Breakdown',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
          
          const SizedBox(height: 16),
          if (stats.breakdown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No spending recorded for this month.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
            )
          else
            ...stats.breakdown.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _CategoryBreakdownRow(item: item),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor = Colors.black,
    this.onValueTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;
  final VoidCallback? onValueTap;

  @override
  Widget build(BuildContext context) {
    final valueText = Text(
      value,
      textAlign: TextAlign.right,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: valueColor,
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onValueTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8E8E8)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: Colors.black),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
              Flexible(child: valueText),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryBreakdownRow extends StatelessWidget {
  const _CategoryBreakdownRow({required this.item});

  final CategoryBreakdown item;

  @override
  Widget build(BuildContext context) {
    final percent = item.percent.clamp(0, 100);
    final label =
        '${categoryDashboardLabel(item.category)} ${percent.round()}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(8),
              child: Image.asset(
                categoryIconAsset(item.category),
                fit: BoxFit.contain,
                color: Colors.black,
                colorBlendMode: BlendMode.srcIn,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.category_outlined,
                  size: 16,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            Text(
              '₱${NumberFormat('#,##0').format(item.amount.round())}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: (percent / 100).clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: const Color(0xFFF3F4F6),
            color: Colors.black,
          ),
        ),
      ],
    );
  }
}
