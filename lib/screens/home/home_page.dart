import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/budget_provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  double balance = 0.0;
  double billsPercentage = 50.0;
  double savingsPercentage = 20.0;
  double personalPercentage = 30.0;

  double billsAmount = 0.0;
  double savingsAmount = 0.0;
  double personalAmount = 0.0;
  double remainingAmount = 0.0;


  late TextEditingController incomeController;
  late TextEditingController billsController;
  late TextEditingController savingsController;
  late TextEditingController personalController;

  @override
  void initState() {
    super.initState();
  
    incomeController = TextEditingController(text: balance.toStringAsFixed(0));
    billsController = TextEditingController(text: billsPercentage.toString());
    savingsController = TextEditingController(text: savingsPercentage.toString());
    personalController = TextEditingController(text: personalPercentage.toString());
  }

  @override
  void dispose() {
  
    incomeController.dispose();
    billsController.dispose();
    savingsController.dispose();
    personalController.dispose();
    super.dispose();
  }

  void _showEditDialog() {
    
    incomeController.text = balance.toStringAsFixed(0);
    billsController.text = billsPercentage.toString();
    savingsController.text = savingsPercentage.toString();
    personalController.text = personalPercentage.toString();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        insetAnimationDuration: Duration.zero,
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(32),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.68,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Budget Setup',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF121212),
                  ),
                ),
                const SizedBox(height: 24),
                _buildField(
                  label: 'Income',
                  controller: incomeController,
                  prefixText: '₱ ',
                ),
                const SizedBox(height: 16),
                _buildField(
                  label: 'Bills %',
                  controller: billsController,
                  suffixText: '%',
                ),
                const SizedBox(height: 16),
                _buildField(
                  label: 'Savings %',
                  controller: savingsController,
                  suffixText: '%',
                ),
                const SizedBox(height: 16),
                _buildField(
                  label: 'Personal %',
                  controller: personalController,
                  suffixText: '%',
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          balance = double.tryParse(incomeController.text) ?? 0;
                          billsPercentage = double.tryParse(billsController.text) ?? 0;
                          savingsPercentage = double.tryParse(savingsController.text) ?? 0;
                          personalPercentage = double.tryParse(personalController.text) ?? 0;

                          double totalPercentage = billsPercentage +
                              savingsPercentage +
                              personalPercentage;

                          if (totalPercentage != 100) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Bills + Savings + Personal must equal 100%',
                                ),
                              ),
                            );
                            return;
                          }

                          billsAmount = balance * (billsPercentage / 100);
                          savingsAmount = balance * (savingsPercentage / 100);
                          personalAmount = balance * (personalPercentage / 100);
                          remainingAmount = balance -
                              billsAmount -
                              savingsAmount -
                              personalAmount;
                        });

                        Provider.of<BudgetProvider>(
                          context,
                          listen: false,
                        ).updateBudget(
                          income: balance,
                          billsPercentage: billsPercentage,
                          savingsPercentage: savingsPercentage,
                          personalPercentage: personalPercentage,
                        );

                        Navigator.pop(context);
                      },
                      child: const Text(
                        'Save',
                        style: TextStyle(
                          color: Color(0xFF121212),
                          fontWeight: FontWeight.bold,
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
    );
  }

  
 Widget _buildField({
  required String label,
  required TextEditingController controller,
  String? prefixText,
  String? suffixText,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF121212))),
      const SizedBox(height: 8),
      RepaintBoundary( 
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              prefixText: prefixText,
              suffixText: suffixText,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              border: InputBorder.none,
            ),
          ),
        ),
      ),
    ],
  );
}

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final headerHeight = screenHeight * 0.38;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              height: headerHeight,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    Color(0xFF262626),
                    Color(0xFF000000),
                  ],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.grey[700],
                        backgroundImage: user?.photoURL != null
                            ? NetworkImage(user!.photoURL!)
                            : null,
                        child: user?.photoURL == null
                            ? Icon(
                                Icons.person,
                                size: 32,
                                color: Colors.grey[300],
                              )
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.displayName ?? 'User',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user?.email ?? 'No email',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[400],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ],
                  ),
                  Center(
                    child: SizedBox(
                      height: 120,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  'Income',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                    color: Colors.grey[400],
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      NumberFormat('#,##0').format(balance),
                                      style: const TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: _showEditDialog,
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[700],
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.edit,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 30,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Container(
                                  width: 1.5,
                                  height: 100,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  'Balance',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                    color: Colors.grey[400],
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  NumberFormat('#,##0').format(remainingAmount),
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Row(
                children: [
                  Expanded(
                    child: _BuildGridCard(
                      amount: NumberFormat('#,##0').format(billsAmount),
                      label: 'BILLS',
                      gradientColors: const [
                        Color(0xFF333333),
                        Color(0xFF000000),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _BuildGridCard(
                      amount: NumberFormat('#,##0').format(savingsAmount),
                      label: 'SAVINGS',
                      gradientColors: const [
                        Color(0xFF333333),
                        Color(0xFF000000),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _BuildGridCard(
                      amount: NumberFormat('#,##0').format(personalAmount),
                      label: 'PERSONAL',
                      gradientColors: const [
                        Color(0xFF333333),
                        Color(0xFF000000),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _BuildGridCard extends StatelessWidget {
  final String amount;
  final String label;
  final List<Color> gradientColors;

  const _BuildGridCard({
    required this.amount,
    required this.label,
    required this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              amount,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}