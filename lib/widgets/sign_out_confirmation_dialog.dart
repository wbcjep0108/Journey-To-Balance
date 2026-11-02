import 'package:flutter/material.dart';

class SignOutConfirmationDialog extends StatelessWidget {
  const SignOutConfirmationDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('Sign out?'),
      content: const Text('Are you sure you want to sign out?'),
      actions: [
        TextButton(
          key: const ValueKey('sign-out-cancel'),
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF6B7280)),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('sign-out-confirm'),
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF121212),
            foregroundColor: Colors.white,
          ),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
