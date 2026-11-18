import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_lock_provider.dart';
import '../providers/connectivity_provider.dart';
import '../screens/offline/offline_screen.dart';

/// Shows the offline page as an overlay above [child].
///
/// [child] is never replaced or rebuilt into a different tree, so typed text
/// and widget state survive an offline period. The overlay is skipped while
/// the PIN setup or PIN unlock screen is showing, because both work offline.
///
/// Place it in `MaterialApp.builder`, below the privacy blur.
class ConnectivityGate extends StatefulWidget {
  const ConnectivityGate({super.key, required this.child});

  final Widget child;

  @override
  State<ConnectivityGate> createState() => _ConnectivityGateState();
}

class _ConnectivityGateState extends State<ConnectivityGate> {
  static const _fadeDuration = Duration(milliseconds: 250);
  static const _noticeDuration = Duration(milliseconds: 2500);

  ConnectivityProvider? _connectivity;
  bool _wasOnline = true;
  bool _overlayMounted = false;
  bool _showBackOnline = false;
  Timer? _noticeTimer;

  @override
  void initState() {
    super.initState();
    final connectivity = context.read<ConnectivityProvider>();
    _connectivity = connectivity;
    _wasOnline = connectivity.online;
    connectivity.addListener(_onConnectivityChanged);
  }

  @override
  void dispose() {
    _connectivity?.removeListener(_onConnectivityChanged);
    _noticeTimer?.cancel();
    super.dispose();
  }

  void _onConnectivityChanged() {
    final online = _connectivity?.online ?? true;
    final reconnected = online && !_wasOnline;
    _wasOnline = online;
    if (!online) {
      // Drop focus so the keyboard closes. Typed text is kept.
      FocusManager.instance.primaryFocus?.unfocus();
    }
    // Only announce when the offline page was actually on screen.
    if (reconnected && _overlayMounted && mounted) {
      _noticeTimer?.cancel();
      setState(() => _showBackOnline = true);
      _noticeTimer = Timer(_noticeDuration, () {
        if (mounted) setState(() => _showBackOnline = false);
      });
    }
  }

  bool _isPinScreenShowing(AppLockStatus status) =>
      status == AppLockStatus.needsSetup || status == AppLockStatus.locked;

  @override
  Widget build(BuildContext context) {
    final connectivity = context.watch<ConnectivityProvider>();
    final lockStatus = context.select<AppLockProvider, AppLockStatus>(
      (lock) => lock.status,
    );

    final wantOverlay = !connectivity.online && !_isPinScreenShowing(lockStatus);
    if (wantOverlay) _overlayMounted = true;

    final showSlowHint =
        connectivity.isSlow && !wantOverlay && !_overlayMounted;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: ExcludeFocus(
            excluding: _overlayMounted,
            child: ExcludeSemantics(
              excluding: _overlayMounted,
              child: widget.child,
            ),
          ),
        ),
        if (_overlayMounted)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !wantOverlay,
              child: AnimatedOpacity(
                opacity: wantOverlay ? 1 : 0,
                duration: _fadeDuration,
                curve: Curves.easeOut,
                onEnd: () {
                  if (!wantOverlay && mounted) {
                    setState(() => _overlayMounted = false);
                  }
                },
                // Opaque listener: touches never reach the app underneath.
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  child: OfflineScreen(
                    checking: connectivity.checking,
                    onRetry: () => unawaited(connectivity.retry()),
                  ),
                ),
              ),
            ),
          ),
        _StatusPill(
          visible: _showBackOnline,
          text: "You're back online.",
        ),
        _StatusPill(visible: showSlowHint, text: 'Slow connection'),
      ],
    );
  }
}

/// Small, non-interactive pill at the top of the screen.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.visible, required this.text});

  final bool visible;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Align(
                alignment: Alignment.topCenter,
                child: Material(
                  color: const Color(0xFF121212),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
