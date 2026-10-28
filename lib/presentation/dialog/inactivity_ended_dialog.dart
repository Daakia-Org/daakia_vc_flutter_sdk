import 'dart:async';

import 'package:flutter/material.dart';

import '../../utils/constants.dart';

/// Full-screen notice that the meeting closed because nobody was active.
///
/// Counts down [Constant.inactiveEndScreenSeconds] and then completes, at
/// which point the caller closes the meeting. Cannot be dismissed early, same
/// as web's end screen.
Future<void> showInactivityEndedDialog(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black,
    pageBuilder: (dialogContext, _, _) =>
        const PopScope(canPop: false, child: _InactivityEndedScreen()),
  );
}

class _InactivityEndedScreen extends StatefulWidget {
  const _InactivityEndedScreen();

  @override
  State<_InactivityEndedScreen> createState() => _InactivityEndedScreenState();
}

class _InactivityEndedScreenState extends State<_InactivityEndedScreen> {
  late final DateTime _deadline;
  Timer? _ticker;
  int _secondsLeft = Constant.inactiveEndScreenSeconds;

  @override
  void initState() {
    super.initState();
    _deadline = DateTime.now()
        .add(const Duration(seconds: Constant.inactiveEndScreenSeconds));
    _ticker =
        Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final ms = _deadline.difference(DateTime.now()).inMilliseconds;
    final next = ms <= 0 ? 0 : (ms / 1000).ceil();
    if (next <= 0) {
      _ticker?.cancel();
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
      return;
    }
    if (next != _secondsLeft) setState(() => _secondsLeft = next);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'The meeting has been automatically ended due to inactivity',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'You Will Be Redirected In $_secondsLeft Seconds',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
