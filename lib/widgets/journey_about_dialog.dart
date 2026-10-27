import 'package:flutter/material.dart';

class JourneyAboutDialog extends StatelessWidget {
  const JourneyAboutDialog({super.key, required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final dialog = Semantics(
      label: 'About Journey to Balance',
      child: Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 360,
              maxHeight: MediaQuery.sizeOf(context).height * 0.88,
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.fromBorderSide(
                                BorderSide(color: Color(0xFFE5E7EB)),
                              ),
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/images/logo.png',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'About Journey to Balance',
                              maxLines: 1,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF121212),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Version $version',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF737983),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Simple tools to take control of your money, all in one secure place.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 1.5,
                              color: Color(0xFF25282D),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const _FeatureRow(
                            icon: Icons.account_balance_wallet_outlined,
                            label: 'Track income and expenses',
                          ),
                          const SizedBox(height: 10),
                          const _FeatureRow(
                            icon: Icons.receipt_long_outlined,
                            label: 'Manage your bills',
                          ),
                          const SizedBox(height: 10),
                          const _FeatureRow(
                            icon: Icons.savings_outlined,
                            label: 'Monitor your savings',
                          ),
                          const SizedBox(height: 10),
                          const _FeatureRow(
                            icon: Icons.cloud_done_outlined,
                            label: 'Sync securely across your devices',
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F2F4),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'DEVELOPER',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1,
                                    color: Color(0xFF737983),
                                  ),
                                ),
                                SizedBox(height: 7),
                                Text(
                                  'Wilhem Bruce Cuevas',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF121212),
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'BSIT student, National University Manila',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF737983),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF121212),
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                      ),
                      child: const Text(
                        'Close',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    );

    if (MediaQuery.disableAnimationsOf(context)) return dialog;
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      tween: Tween(begin: 0.96, end: 1),
      builder: (context, value, child) => Opacity(
        opacity: ((value - 0.96) / 0.04).clamp(0.0, 1.0),
        child: Transform.scale(scale: value, child: child),
      ),
      child: dialog,
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.fromBorderSide(
              BorderSide(color: Color(0xFFE5E7EB)),
            ),
          ),
          child: Icon(icon, size: 20, color: const Color(0xFF25282D)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF25282D),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
