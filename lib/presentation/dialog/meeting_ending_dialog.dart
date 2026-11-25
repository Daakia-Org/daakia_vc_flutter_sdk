import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../resources/colors/color.dart';

/// Shows the "meeting ending soon" card with a live countdown.
///
/// With [onExtend] it is the prompt for the one participant allowed to extend
/// the meeting by [extendMinutes]; without it, the same card is a plain notice
/// for everyone else. [endTime] is read live rather than captured, so the
/// countdown follows the meeting's real end for as long as the card stays open.
/// [onExtend] resolves to null once the extension is accepted, or to the
/// message to show if it isn't. [onOpened] hands back the dialog's context so
/// the caller can close it from outside — when the meeting gets extended.
Future<void> showMeetingEndingDialog(
  BuildContext context, {
  required DateTime? Function() endTime,
  Future<String?> Function()? onExtend,
  int extendMinutes = 0,
  ValueChanged<BuildContext>? onOpened,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      onOpened?.call(dialogContext);
      return MeetingEndingDialog(
        endTime: endTime,
        onExtend: onExtend,
        extendMinutes: extendMinutes,
      );
    },
  );
}

/// A live countdown to the end of the meeting, optionally with an Extend button.
///
/// Shows whole minutes left — rounded up, so "3 min" never means more than
/// three — until the final minute, then counts down second by second. The ring
/// refills and turns red at that switch so the change of pace is hard to miss.
/// Closes itself when time runs out, so the meeting-end notice isn't left
/// hidden behind it.
class MeetingEndingDialog extends StatefulWidget {
  const MeetingEndingDialog({
    super.key,
    required this.endTime,
    this.onExtend,
    this.extendMinutes = 0,
  }) : assert(onExtend == null || extendMinutes > 0);

  final DateTime? Function() endTime;

  /// Null for the notice form, which has no Extend button.
  final Future<String?> Function()? onExtend;
  final int extendMinutes;

  @override
  State<MeetingEndingDialog> createState() => _MeetingEndingDialogState();
}

class _MeetingEndingDialogState extends State<MeetingEndingDialog> {
  static const int _finalCountdownSeconds = 60;
  static const Color _urgentColor = Color(0xFFD32F2F);

  Timer? _ticker;
  late int _secondsLeft;

  /// Seconds left when the card opened; the ring drains against this until the
  /// final minute, where it switches to draining against sixty.
  late int _openedWithSeconds;

  bool _isExtending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _secondsLeft = _readSecondsLeft();
    _openedWithSeconds = math.max(_secondsLeft, 1);
    // Ticks faster than once a second but repaints only when the shown second
    // changes: a 1s timer started mid-second would trail the real clock.
    _ticker =
        Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  int _readSecondsLeft() {
    final end = widget.endTime();
    if (end == null) return 0;
    final ms = end.difference(DateTime.now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  void _tick() {
    if (!mounted) return;
    final next = _readSecondsLeft();
    if (next <= 0) {
      _ticker?.cancel();
      _close();
      return;
    }
    if (next != _secondsLeft) setState(() => _secondsLeft = next);
  }

  /// Pops this dialog's own route, even if something was pushed above it —
  /// a plain `pop()` would close whatever happens to be on top instead.
  void _close() {
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).removeRoute(route);
    }
  }

  Future<void> _extend() async {
    setState(() {
      _isExtending = true;
      _error = null;
    });
    String? error;
    try {
      error = await widget.onExtend!();
    } catch (_) {
      error = "Couldn't extend the meeting. Please try again.";
    }
    if (!mounted) return;
    // On success the card has done its job; the caller confirms the new end
    // time with its own notice.
    if (error == null) {
      _close();
      return;
    }
    // On failure it stays open with the reason, so the host can retry before
    // time runs out instead of discovering the failure in a passing toast.
    setState(() {
      _isExtending = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canExtend = widget.onExtend != null;
    final isFinalMinute = _secondsLeft <= _finalCountdownSeconds;
    final accent = isFinalMinute ? _urgentColor : themeColor;
    final minutesLeft = (_secondsLeft / 60).ceil();

    final media = MediaQuery.of(context);
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCountdown(
                value: isFinalMinute ? '$_secondsLeft' : '$minutesLeft',
                unit: isFinalMinute ? 'sec left' : 'min left',
                semanticsLabel: isFinalMinute
                    ? '$_secondsLeft ${_secondsLeft == 1 ? 'second' : 'seconds'} left'
                    : '$minutesLeft ${minutesLeft == 1 ? 'minute' : 'minutes'} left',
                progress: isFinalMinute
                    ? _secondsLeft / _finalCountdownSeconds
                    : _secondsLeft / _openedWithSeconds,
                accent: accent,
              ),
              const SizedBox(height: 20),
              Text(
                isFinalMinute ? 'Meeting is about to end' : 'Meeting ending soon',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                canExtend
                    ? 'Extend by ${widget.extendMinutes} minutes to keep the '
                        'meeting going for everyone.'
                    : 'The meeting will close automatically when the timer '
                        'runs out.',
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
                    disabledBackgroundColor: themeColor.withValues(alpha: 0.6),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: canExtend
                      ? (_isExtending ? null : _extend)
                      : _close,
                  child: _isExtending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          !canExtend
                              ? 'Got it'
                              : _error == null
                                  ? 'Extend by ${widget.extendMinutes} minutes'
                                  : 'Try again',
                          style: const TextStyle(color: Colors.white),
                        ),
                ),
              ),
              if (canExtend) ...[
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _close,
                    child: const Text(
                      'Not now',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountdown({
    required String value,
    required String unit,
    required String semanticsLabel,
    required double progress,
    required Color accent,
  }) {
    return Semantics(
      label: semanticsLabel,
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
                color: accent,
                backgroundColor: accent.withValues(alpha: 0.12),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      color: accent,
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                      // Fixed-width digits, so the number doesn't jitter
                      // sideways as it counts down.
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    unit,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
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
        color: _urgentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: _urgentColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: _urgentColor,
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
