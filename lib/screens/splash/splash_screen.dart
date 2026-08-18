import 'package:flutter/material.dart';

import '../../widgets/security_ui.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color.fromARGB(255, 255, 255, 255),
      body: Center(child: BrandMark(size: 180)),
    );
  }
}
