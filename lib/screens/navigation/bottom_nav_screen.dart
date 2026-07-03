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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: SizedBox.shrink(),
            label: 'HOME',
          ),
          BottomNavigationBarItem(
            icon: SizedBox.shrink(),
            label: 'BILLS',
          ),
          BottomNavigationBarItem(
            icon: SizedBox.shrink(),
            label: 'SAVINGS',
          ),
          BottomNavigationBarItem(
            icon: SizedBox.shrink(),
            label: 'PERSONAL',
          ),
          BottomNavigationBarItem(
            icon: SizedBox.shrink(),
            label: 'ACCOUNT',
          ),
        ],
      ),
    );
  }
}