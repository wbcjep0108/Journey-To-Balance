import 'package:flutter/material.dart';

import '../home/home_page.dart';
import '../bills/bills_page.dart';
import '../savings/savings_page.dart';
import '../personal/personal_page.dart';
import '../account/account_page.dart';

class BottomNavScreen extends StatefulWidget {
  const BottomNavScreen({super.key});

  @override
  State<BottomNavScreen> createState() => _BottomNavScreenState();
}

class _BottomNavScreenState extends State<BottomNavScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    HomePage(),
    BillsPage(),
    SavingsPage(),
    PersonalPage(),
    AccountPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _navItem({
    required int index,
    required String assetPath,
  }) {
    final bool isSelected = _selectedIndex == index;

    return GestureDetector(
      onTap: () => _onItemTapped(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF121212).withOpacity(0.08)
              : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Opacity(
          opacity: isSelected ? 1.0 : 0.45,
          child: Image.asset(
            assetPath,
            width: 24,
            height: 24,
            color: isSelected ? const Color(0xFF121212) : Colors.grey,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      body: Stack(
        children: [
          // Pages
          IndexedStack(
            index: _selectedIndex,
            children: _pages,
          ),

      
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: SafeArea(
              child: Container(
                height: 72,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 24,
                      spreadRadius: 2,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _navItem(
                      index: 0,
                      assetPath: 'assets/images/icons/home.png',
                    ),
                    _navItem(
                      index: 1,
                      assetPath: 'assets/images/icons/bills.png',
                    ),
                    _navItem(
                      index: 2,
                      assetPath: 'assets/images/icons/savings.png',
                    ),
                    _navItem(
                      index: 3,
                      assetPath: 'assets/images/icons/personal.png',
                    ),
                    _navItem(
                      index: 4,
                      assetPath: 'assets/images/icons/account.png',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}