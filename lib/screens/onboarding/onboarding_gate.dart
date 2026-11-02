import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/onboarding_state.dart';
import '../../widgets/budget_exceeded_dialog.dart';
import '../../widgets/rate_limit_dialog.dart';
import '../navigation/bottom_nav_screen.dart';
import '../splash/welcome_transition.dart';
import 'onboarding_screen.dart';

class OnboardingGate extends StatefulWidget {
  const OnboardingGate({
    super.key,
    required this.uid,
    required this.showInitially,
    required this.initialRecord,
    required this.onInitialFlowClosed,
  });

  final String uid;
  final bool showInitially;
  final OnboardingRecord? initialRecord;
  final Future<void> Function() onInitialFlowClosed;

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  late bool _showFlow;
  OnboardingStatus? _status;

  @override
  void initState() {
    super.initState();
    _showFlow = widget.showInitially;
    _status = widget.initialRecord?.status;
  }

  void _initialClosed(OnboardingStatus? status) {
    if (!mounted) return;
    setState(() {
      _status = status;
      _showFlow = false;
    });
    unawaited(widget.onInitialFlowClosed());
  }

  Future<void> _runAgain() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => OnboardingScreen(
          uid: widget.uid,
          existingStatus: _status,
          isRerun: true,
          onClosed: (status) {
            if (mounted) setState(() => _status = status);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showFlow) {
      return RateLimitListener(
        child: OnboardingScreen(
          uid: widget.uid,
          existingStatus: _status,
          onClosed: _initialClosed,
        ),
      );
    }

    return RateLimitListener(
      child: PlannerAlertListener(
        child: PostLoginWelcome(
          child: BottomNavScreen(
            showFinishSetup: _status == OnboardingStatus.dismissed,
            onRunSetup: _runAgain,
          ),
        ),
      ),
    );
  }
}
