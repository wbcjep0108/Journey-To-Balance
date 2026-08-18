import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/loan_entry.dart';
import '../../providers/currency_provider.dart';
import '../../providers/loan_provider.dart';
import '../../widgets/barrier_blur.dart';
import '../../widgets/sensitive_action_auth.dart';

class PaidLoanTransactionsPage extends StatelessWidget {
  const PaidLoanTransactionsPage({super.key});

  Future<bool> _confirmDeleteLoan(
    BuildContext context,
    LoanEntry loan,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (dialogContext) {
        return withBarrierBlur(
          Center(
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Delete loan?',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF121212),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Remove "${loan.name}" from loan transactions? This cannot be undone.',
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(false),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF6B7280),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF121212),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              child: const Text(
                                'Delete',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    if (confirmed != true || !context.mounted) return false;

    final authorized = await showSensitiveActionAuth(
      context: context,
      title: 'Confirm delete',
      description:
          'Enter your PIN or use fingerprint to delete "${loan.name}".',
    );
    if (!authorized || !context.mounted) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final loans = context.watch<LoanProvider>();
    final paidLoans = loans.paidLoans;
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F3),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(4, topInset + 10, 4, 0),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.black,
                      size: 26,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.10),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Text(
                    'Loan Transaction',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                const SizedBox(height: 36),
              ],
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(40),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: paidLoans.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(28, 40, 28, 28),
                        child: Text(
                          'No paid loans yet.\nFinish the final installment on a loan to see it here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 15,
                            height: 1.45,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
                      itemCount: paidLoans.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        final loan = paidLoans[index];
                        return _PaidLoanCard(
                          loan: loan,
                          onConfirmDelete: () =>
                              _confirmDeleteLoan(context, loan),
                          onDismissed: () => loans.deleteLoan(loan.id),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaidLoanCard extends StatelessWidget {
  const _PaidLoanCard({
    required this.loan,
    required this.onConfirmDelete,
    required this.onDismissed,
  });

  final LoanEntry loan;
  final Future<bool> Function() onConfirmDelete;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final installmentCount = loan.installmentDates.length;
    final totalPaid = installmentCount * loan.amount;
    final currency = context.watch<CurrencyProvider>();
    final totalLabel = NumberFormat.currency(
      locale: currency.currency.locale,
      symbol: currency.symbol,
      decimalDigits: totalPaid % 1 == 0 ? 0 : 2,
    ).format(totalPaid);
    final monthlyLabel = NumberFormat.currency(
      locale: currency.currency.locale,
      symbol: currency.symbol,
      decimalDigits: loan.amount % 1 == 0 ? 0 : 2,
    ).format(loan.amount);
    final completedOn = loan.installmentDates.isEmpty
        ? loan.finalPaymentDate
        : loan.installmentDates.last;
    final completedLabel = DateFormat('MMM d, yyyy').format(completedOn);

    return Dismissible(
      key: ValueKey('paid_${loan.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
      ),
      confirmDismiss: (_) => onConfirmDelete(),
      onDismissed: (_) => onDismissed(),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8F8),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loan.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF121212),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    totalLabel,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF121212),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$installmentCount × $monthlyLabel · Completed $completedLabel',
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'PAID',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: Color(0xFF16A34A),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
