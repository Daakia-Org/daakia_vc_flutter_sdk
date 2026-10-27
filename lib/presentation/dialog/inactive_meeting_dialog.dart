import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../resources/colors/color.dart';
import '../../utils/constants.dart';

/// Shows the "Still there?" prompt with its two-minute countdown.
///
/// Blocks the whole meeting: no barrier tap, no Back. Only its buttons, or the
/// caller closing it on real activity, take it down. [onOpened] hands back the
/// dialog's context so the caller can do that.
Future<void> showInactiveMeetingDialog(
  BuildContext context, {
  required ValueListenable<bool> solo,
  required bool Function() canEndForAll,
  required VoidCallback onStay,
  required VoidCallback onLeave,
  required Future<String?> Function() onEnd,
  required VoidCallback onCountdownZero,
  ValueChanged<BuildContext>? onOpened,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      onOpened?.call(dialogContext);
      return PopScope(
        canPop: false,
        child: InactiveMeetingDialog(
          solo: solo,
          canEndForAll: canEndForAll,
          onStay: onStay,
          onLeave: onLeave,
          onEnd: onEnd,
          onCountdownZero: onCountdownZero,
        ),
      );
    },
  );
}

/// The "Still there?" card. Three versions, matching web:
///
///  * solo                      — Stay in the call / Leave now
///  * group, host or co-host    — Continue in meeting / End meeting
///  * group, anyone else        — Stay in meeting / Leave now
///
/// The text follows [solo] live, so people leaving switch it from group to
/// solo without restarting the countdown.
class InactiveMeetingDialog extends StatefulWidget {
  const InactiveMeetingDialog({
    super.key,
    required this.solo,
    required this.canEndForAll,
    required this.onStay,
    required this.onLeave,
    required this.onEnd,
    required this.onCountdownZero,
  });

  final ValueListenable<bool> solo;
  final bool Function() canEndForAll;
  final VoidCallback onStay;
  final VoidCallback onLeave;

  /// Resolves to null once the meeting is ended, or to the message to show in
  /// place if it isn't, so the host can try again.
  final Future<String?> Function() onEnd;

  /// Fires exactly once, when the countdown reaches zero.
  final VoidCallback onCountdownZero;

  @override
  State<InactiveMeetingDialog> createState() => _InactiveMeetingDialogState();
}

class _InactiveMeetingDialogState extends State<InactiveMeetingDialog> {
  static const Color _ringColor = Color(0xFF0A84FF);
  static const Color _trackColor = Color(0xFFE6E8EC);
  static const Color _dangerColor = Color(0xFFD32F2F);

  /// A deadline rather than a counter, so time spent in the background is not
  /// handed back as extra countdown.
  late final DateTime _deadline;
  Timer? _ticker;
  late int _secondsLeft;
  bool _zeroFired = false;
  bool _isEnding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _deadline = DateTime.now().add(
      const Duration(seconds: Constant.inactiveCountdownSeconds),
    );
    _secondsLeft = Constant.inactiveCountdownSeconds;
    // Ticks faster than once a second but repaints only when the shown second
    // changes: a 1s timer started mid-second would trail the real clock.
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
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
      if (_zeroFired) return;
      _zeroFired = true;
      setState(() => _secondsLeft = 0);
      widget.onCountdownZero();
      return;
    }
    if (next != _secondsLeft) setState(() => _secondsLeft = next);
  }

  Future<void> _end() async {
    setState(() {
      _isEnding = true;
      _error = null;
    });
    String? error;
    try {
      error = await widget.onEnd();
    } catch (_) {
      error = "Could not end the meeting. Please try again.";
    }
    if (!mounted || error == null) return;
    setState(() {
      _isEnding = false;
      _error = error;
    });
  }

  /// Narrower than any phone, even in landscape: the app is in Android
  /// picture-in-picture, where the card can't fit and the buttons can't be
  /// tapped anyway.
  static const double _pipMaxWidth = 300;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.size.width < _pipMaxWidth) return _buildPipContent();
    // Same clamp as the other SDK cards: a landscape phone is only ~360dp tall,
    // so the content scrolls rather than pushing the buttons off the card.
    final maxHeight = media.size.height - media.viewInsets.vertical - 96;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxHeight.clamp(160.0, 560.0),
          minWidth: 280,
          maxWidth: 360,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ValueListenableBuilder<bool>(
            valueListenable: widget.solo,
            builder: (context, solo, _) => _buildContent(solo),
          ),
        ),
      ),
    );
  }

  /// Just the countdown, scaled to the window, so someone glancing at the PiP
  /// window sees time running out and can reopen the app to answer.
  Widget _buildPipContent() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: FittedBox(
          // Material, not a bare Container: without one the text falls back to
          // the yellow-underlined debug style.
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildCountdown(),
                  const SizedBox(height: 8),
                  const Text(
                    'Still there?',
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(bool solo) {
    final canEnd = !solo && widget.canEndForAll();
    final String message;
    final String stayLabel;
    final String otherLabel;
    if (solo) {
      message = "You're the only one here. Do you want to stay in the call?";
      stayLabel = 'Stay in the call';
      otherLabel = 'Leave now';
    } else if (canEnd) {
      message =
          'Looks like no one is active. Do you want to continue or end '
          'the meeting?';
      stayLabel = 'Continue in meeting';
      otherLabel = 'End meeting';
    } else {
      message =
          'Looks like no one is active. Do you want to stay in the '
          'meeting or leave?';
      stayLabel = 'Stay in meeting';
      otherLabel = 'Leave now';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCountdown(),
        const SizedBox(height: 20),
        const Text(
          'Still there?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.black54,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          _buildError(_error!),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: themeColor,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: _isEnding ? null : widget.onStay,
            child: Text(stayLabel, style: const TextStyle(color: Colors.white)),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: _isEnding ? null : (canEnd ? _end : widget.onLeave),
            child: _isEnding
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _dangerColor,
                    ),
                  )
                : Text(
                    otherLabel,
                    // Red only where web makes it red: the group versions.
                    style: TextStyle(
                      color: solo ? Colors.black54 : _dangerColor,
                      fontWeight: solo ? FontWeight.normal : FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildCountdown() {
    final minutes = _secondsLeft ~/ 60;
    final seconds = (_secondsLeft % 60).toString().padLeft(2, '0');
    final progress =
        _secondsLeft / math.max(1, Constant.inactiveCountdownSeconds);
    return Semantics(
      label: '$_secondsLeft ${_secondsLeft == 1 ? 'second' : 'seconds'} left',
      excludeSemantics: true,
      child: SizedBox(
        width: 120,
        height: 120,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Animated so the ring glides between ticks instead of jumping a
            // notch every second.
            TweenAnimationBuilder<double>(
              tween: Tween(end: progress.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              builder: (context, ringValue, _) => CircularProgressIndicator(
                value: ringValue,
                strokeWidth: 8,
                strokeCap: StrokeCap.round,
                color: _ringColor,
                backgroundColor: _trackColor,
              ),
            ),
            Center(
              child: Text(
                '$minutes:$seconds',
                style: const TextStyle(
                  color: _ringColor,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                  // Fixed-width digits, so the time doesn't jitter sideways as
                  // it counts down.
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _dangerColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: _dangerColor,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: _dangerColor,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
