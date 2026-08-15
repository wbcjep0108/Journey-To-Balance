import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/loan_entry.dart';
import '../../providers/loan_provider.dart';

class PaidLoanTransactionsPage extends StatelessWidget {
  const PaidLoanTransactionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final paidLoans = context.watch<LoanProvider>().paidLoans;
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(8, topInset + 4, 8, 28),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Loan transactions',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  paidLoans.isEmpty
                      ? 'Fully paid loans appear here'
                      : '${paidLoans.length} paid loan${paidLoans.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: Color(0xFFB0B0B0),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
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
                        return _PaidLoanCard(loan: loan);
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
  const _PaidLoanCard({required this.loan});

  final LoanEntry loan;

  @override
  Widget build(BuildContext context) {
    final installmentCount = loan.installmentDates.length;
    final totalPaid = installmentCount * loan.amount;
    final totalLabel = NumberFormat.currency(
      locale: 'en_PH',
      symbol: 'PHP ',
      decimalDigits: totalPaid % 1 == 0 ? 0 : 2,
    ).format(totalPaid);
    final monthlyLabel = NumberFormat.currency(
      locale: 'en_PH',
      symbol: 'PHP ',
      decimalDigits: loan.amount % 1 == 0 ? 0 : 2,
    ).format(loan.amount);
    final completedOn = loan.installmentDates.isEmpty
        ? loan.finalPaymentDate
        : loan.installmentDates.last;
    final completedLabel = DateFormat('MMM d, yyyy').format(completedOn);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
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
    );
  }
}
