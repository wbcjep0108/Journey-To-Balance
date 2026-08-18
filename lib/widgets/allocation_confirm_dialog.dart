import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/currency_provider.dart';
import 'barrier_blur.dart';

enum AllocationConfirmKind { receiveSalary, addMoney }

class AllocationConfirmDialog {
  AllocationConfirmDialog._();

  static String formatMoney(BuildContext context, double amount) =>
      context.read<CurrencyProvider>().format(amount);

  static Future<bool> showNewMoneyConfirm({
    required BuildContext context,
    required AllocationConfirmKind kind,
    required double amount,
    required double billsPercentage,
    required double savingsPercentage,
    required double personalPercentage,
  }) async {
    if (amount <= 0) return false;

    final billsAdd = amount * (billsPercentage / 100);
    final personalAdd = amount * (personalPercentage / 100);
    final savingsAdd = amount * (savingsPercentage / 100);
    final amountLabel = formatMoney(context, amount);

    final String lead;
    final String footer;
    switch (kind) {
      case AllocationConfirmKind.receiveSalary:
        lead =
            'Your $amountLabel salary will be added to your Available Balance.\n\n'
            'The new money will be distributed according to your current percentages:';
        footer =
            'Your existing category balances will not be recalculated.';
      case AllocationConfirmKind.addMoney:
        lead =
            'Your $amountLabel will be added to your Available Balance.\n\n'
            'New allocation:';
        footer =
            'Only this new $amountLabel will be distributed.\n'
            'Your existing category balances will remain unchanged.';
    }

    final result = await _showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) => _ConfirmCard(
        title: 'Budget Allocation Update',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              lead,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.45,
                color: Color(0xFF4B5563),
              ),
            ),
            const SizedBox(height: 18),
            _NewMoneyBox(amountLabel: amountLabel),
            const SizedBox(height: 14),
            _AllocationRow(
              label: 'Bills',
              percentage: billsPercentage,
              amountLabel: '+${formatMoney(context, billsAdd)}',
            ),
            _AllocationRow(
              label: 'Personal',
              percentage: personalPercentage,
              amountLabel: '+${formatMoney(context, personalAdd)}',
            ),
            _AllocationRow(
              label: 'Savings',
              percentage: savingsPercentage,
              amountLabel: '+${formatMoney(context, savingsAdd)}',
            ),
            const SizedBox(height: 16),
            Text(
              footer,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.4,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 22),
            _ActionRow(
              cancelLabel: 'Cancel',
              confirmLabel: 'Continue',
              onCancel: () => Navigator.pop(dialogContext, false),
              onConfirm: () => Navigator.pop(dialogContext, true),
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  /// Confirm manual Available Balance edit: all categories are recalculated
  /// from the new total using the user's percentages.
  static Future<bool> showEditBalanceRecalculateConfirm({
    required BuildContext context,
    required double newAvailableBalance,
    required double billsPercentage,
    required double savingsPercentage,
    required double personalPercentage,
  }) async {
    if (newAvailableBalance < 0) return false;

    final balanceLabel = formatMoney(context, newAvailableBalance);
    final billsAmount = newAvailableBalance * (billsPercentage / 100);
    final personalAmount = newAvailableBalance * (personalPercentage / 100);
    final savingsAmount = newAvailableBalance * (savingsPercentage / 100);

    final result = await _showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) => _ConfirmCard(
        title: 'Adjust Available Balance',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'You\'re setting your Available Balance to $balanceLabel.\n\n'
              'All category balances will be recalculated using your current percentages:',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.45,
                color: Color(0xFF4B5563),
              ),
            ),
            const SizedBox(height: 18),
            _NewMoneyBox(
              amountLabel: balanceLabel,
              caption: 'New Available Balance',
            ),
            const SizedBox(height: 14),
            _AllocationRow(
              label: 'Bills',
              percentage: billsPercentage,
              amountLabel: formatMoney(context, billsAmount),
            ),
            _AllocationRow(
              label: 'Personal',
              percentage: personalPercentage,
              amountLabel: formatMoney(context, personalAmount),
            ),
            _AllocationRow(
              label: 'Savings',
              percentage: savingsPercentage,
              amountLabel: formatMoney(context, savingsAmount),
            ),
            const SizedBox(height: 16),
            const Text(
              'Previous spending will not be subtracted again after this update.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.4,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 22),
            _ActionRow(
              cancelLabel: 'Cancel',
              confirmLabel: 'Confirm',
              onCancel: () => Navigator.pop(dialogContext, false),
              onConfirm: () => Navigator.pop(dialogContext, true),
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  /// Confirm wallet cash + selected cards becoming the new Available Balance.
  static Future<bool> showWalletSourcesConfirm({
    required BuildContext context,
    required double walletCash,
    required List<(String label, double amount)> cards,
    required double billsPercentage,
    required double savingsPercentage,
    required double personalPercentage,
  }) async {
    final total = walletCash +
        cards.fold<double>(0, (sum, card) => sum + card.$2);
    if (total < 0) return false;

    final totalLabel = formatMoney(context, total);
    final billsAmount = total * (billsPercentage / 100);
    final personalAmount = total * (personalPercentage / 100);
    final savingsAmount = total * (savingsPercentage / 100);

    final result = await _showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) => _ConfirmCard(
        title: 'Budget Allocation Update',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Your Available Balance will be the total of wallet cash and your selected cards.\n\n'
              'That total will be allocated using your current percentages:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.45,
                color: Color(0xFF4B5563),
              ),
            ),
            const SizedBox(height: 16),
            _SourceRow(
              label: 'Wallet',
              amountLabel: formatMoney(context, walletCash),
            ),
            for (final card in cards)
              _SourceRow(
                label: card.$1,
                amountLabel: formatMoney(context, card.$2),
              ),
            const SizedBox(height: 8),
            _NewMoneyBox(
              amountLabel: totalLabel,
              caption: 'Available Balance',
            ),
            const SizedBox(height: 14),
            _AllocationRow(
              label: 'Bills',
              percentage: billsPercentage,
              amountLabel: formatMoney(context, billsAmount),
            ),
            _AllocationRow(
              label: 'Personal',
              percentage: personalPercentage,
              amountLabel: formatMoney(context, personalAmount),
            ),
            _AllocationRow(
              label: 'Savings',
              percentage: savingsPercentage,
              amountLabel: formatMoney(context, savingsAmount),
            ),
            const SizedBox(height: 16),
            const Text(
              'Category balances will be recalculated from this total.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.4,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 22),
            _ActionRow(
              cancelLabel: 'Cancel',
              confirmLabel: 'Continue',
              onCancel: () => Navigator.pop(dialogContext, false),
              onConfirm: () => Navigator.pop(dialogContext, true),
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  /// Warn that deleting cards also removes their amounts from Available Balance.
  static Future<bool> showDeleteCardsWarning({
    required BuildContext context,
    required List<(String label, double amount)> cardsToRemove,
    required double currentAvailable,
    required double nextAvailable,
  }) async {
    if (cardsToRemove.isEmpty) return false;

    final removedTotal = cardsToRemove.fold<double>(
      0,
      (sum, card) => sum + card.$2,
    );
    final isSingle = cardsToRemove.length == 1;
    final names = cardsToRemove.map((card) => card.$1).join(', ');

    final result = await _showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) => _ConfirmCard(
        title: isSingle ? 'Delete card' : 'Delete cards',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isSingle
                  ? 'Deleting $names will also delete its stored amount and lower your Available Balance.'
                  : 'Deleting $names will also delete their stored amounts and lower your Available Balance.',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.45,
                color: Color(0xFF4B5563),
              ),
            ),
            const SizedBox(height: 16),
            for (final card in cardsToRemove)
              _SourceRow(
                label: card.$1,
                amountLabel: formatMoney(context, card.$2),
              ),
            const SizedBox(height: 8),
            _SourceRow(
              label: 'Amount removed',
              amountLabel: formatMoney(context, removedTotal),
            ),
            const SizedBox(height: 12),
            _NewMoneyBox(
              amountLabel: formatMoney(context, nextAvailable),
              caption:
                  'Available Balance after delete (${formatMoney(context, currentAvailable)} now)',
            ),
            const SizedBox(height: 22),
            _ActionRow(
              cancelLabel: 'Cancel',
              confirmLabel: 'Delete',
              onCancel: () => Navigator.pop(dialogContext, false),
              onConfirm: () => Navigator.pop(dialogContext, true),
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  static Future<T?> _showAnimatedDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close confirmation dialog',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 240),
      pageBuilder: (context, _, _) => withBarrierBlur(
        SafeArea(
          child: builder(context),
        ),
      ),
      transitionBuilder: (_, animation, _, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curve),
            child: child,
          ),
        );
      },
    );
  }
}

class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 32,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF121212),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 16),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NewMoneyBox extends StatelessWidget {
  const _NewMoneyBox({
    required this.amountLabel,
    this.caption = 'New Money',
  });

  final String amountLabel;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            caption,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            amountLabel,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Color(0xFF121212),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.label, required this.amountLabel});

  final String label;
  final String amountLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF121212),
              ),
            ),
          ),
          Text(
            amountLabel,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF121212),
            ),
          ),
        ],
      ),
    );
  }
}

class _AllocationRow extends StatelessWidget {
  const _AllocationRow({
    required this.label,
    required this.percentage,
    required this.amountLabel,
  });

  final String label;
  final double percentage;
  final String amountLabel;

  @override
  Widget build(BuildContext context) {
    final pctLabel = percentage % 1 == 0
        ? '${percentage.toStringAsFixed(0)}%'
        : '${percentage.toStringAsFixed(1)}%';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF121212),
              ),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              pctLabel,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 110,
            child: Text(
              amountLabel,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF121212),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.cancelLabel,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
  });

  final String cancelLabel;
  final String confirmLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF6B7280),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: Text(
              cancelLabel,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            onPressed: onConfirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF121212),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: Text(
              confirmLabel,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}
