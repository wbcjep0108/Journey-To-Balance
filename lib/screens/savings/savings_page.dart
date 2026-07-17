import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/budget_provider.dart';

class SavingsPage extends StatelessWidget {
  const SavingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final budget = context.watch<BudgetProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 20,
          ),
          child: Column(
            children: [
              // ===== TOP SAVINGS CARD =====
              Container(
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF1a1a1a),
                      Color(0xFF4a4a4a),
                    ],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: 20,
                      top: 20,
                      child: Opacity(
                        opacity: 0.25,
                        child: Image.asset(
                          'assets/images/icons/savings.png',
                          width: 140,
                          height: 140,
                          color: Colors.white,
                        ),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        28,
                        24,
                        28,
                        24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'SAVINGS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                            ),
                          ),

                          const Spacer(),

                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            crossAxisAlignment:
                                CrossAxisAlignment.center,
                            children: [
                              Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${NumberFormat('#,##0').format(budget.savingsAmount)}php',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 42,
                                      fontWeight: FontWeight.w800,
                                      height: 1,
                                    ),
                                  ),

                                  const SizedBox(height: 6),

                                  Text(
                                    'Total balance',
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),

                                  const SizedBox(height: 6),

                                  Text(
                                    '${budget.savingsPercentage.toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),

                              GestureDetector(
                                onTap: () {
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      shape:
                                          RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(24),
                                      ),
                                      title:
                                          const Text('Savings'),
                                      content: const Text(
                                        'Savings Action Placeholder',
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding:
                                      const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white
                                        .withOpacity(0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.add,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ===== RECENT SAVINGS =====
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF161616),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Recent Savings',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                        const SizedBox(height: 28),

                        Expanded(
                          child: SingleChildScrollView(
                            physics:
                                const BouncingScrollPhysics(),
                            child: Column(
                              children: [
                                _buildTransactionRow(
                                  title: 'Emergency Fund',
                                  amount: '+2,000php',
                                ),

                                const SizedBox(height: 20),

                                Divider(
                                  color: Colors.white
                                      .withOpacity(0.1),
                                  height: 1,
                                ),

                                const SizedBox(height: 20),

                                _buildTransactionRow(
                                  title: 'Travel Fund',
                                  amount: '+1,500php',
                                ),

                                const SizedBox(height: 20),

                                Divider(
                                  color: Colors.white
                                      .withOpacity(0.1),
                                  height: 1,
                                ),

                                const SizedBox(height: 20),

                                _buildTransactionRow(
                                  title: 'Future Savings',
                                  amount: '+5,000php',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionRow({
    required String title,
    required String amount,
  }) {
    return Row(
      mainAxisAlignment:
          MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          amount,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}