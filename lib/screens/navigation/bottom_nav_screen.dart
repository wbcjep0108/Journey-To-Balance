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
      backgroundColor: const Color(0xFFF7F7F7), 
      type: BottomNavigationBarType.fixed,
      currentIndex: _selectedIndex,
      onTap: _onItemTapped,

  selectedItemColor: const Color(0xFF121212), // Selected label color
  unselectedItemColor: Colors.grey,  
  items: const [
          BottomNavigationBarItem(
            icon: Image(
              image: AssetImage('assets/images/icons/home.png'),
              width: 24,
              height: 24,
            ),
            label: 'HOME',
          ),
          BottomNavigationBarItem(
            icon: Image(
              image: AssetImage('assets/images/icons/bills.png'),
              width: 24,
              height: 24,
            ),
            label: 'BILLS',
          ),
          BottomNavigationBarItem(
            icon: Image(
              image: AssetImage('assets/images/icons/savings.png'),
              width: 24,
              height: 24,
            ),
            label: 'SAVINGS',
          ),
          BottomNavigationBarItem(
            icon: Image(
              image: AssetImage('assets/images/icons/personal.png'),
              width: 24,
              height: 24,
            ),
            label: 'PERSONAL',
          ),
          BottomNavigationBarItem(
            icon: Image(
              image: AssetImage('assets/images/icons/account.png'),
              width: 24,
              height: 24,
            ),
            label: 'ACCOUNT',
          ),
        ],
      ),
    );
  }
}