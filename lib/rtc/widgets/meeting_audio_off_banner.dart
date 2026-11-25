import 'dart:async';

import 'package:flutter/material.dart';

import 'status_pill_row.dart';

/// The stage's status row while meeting audio is off on this device.
///
/// It opens as a full banner, so turning audio off is never missed, then
/// shrinks to a small "Audio off" chip in the same row as the other status
/// pills (Workshop, Recording) so it doesn't cover the video. Tapping the chip
/// opens the banner again, with its one-tap way back.
class MeetingAudioOffIndicator extends StatefulWidget {
  const MeetingAudioOffIndicator({
    super.key,
    required this.onTurnOn,
    this.pills = const [],
  });

  final VoidCallback onTurnOn;

  /// The other status pills, laid out here so the chip can sit beside them.
  final List<StatusPill> pills;

  @override
  State<MeetingAudioOffIndicator> createState() =>
      _MeetingAudioOffIndicatorState();
}

class _MeetingAudioOffIndicatorState extends State<MeetingAudioOffIndicator> {
  static const Color _amber = Color(0xFFFFB300);
  static const Duration _expandedFor = Duration(seconds: 5);

  bool _expanded = true;
  Timer? _collapseTimer;

  @override
  void initState() {
    super.initState();
    _scheduleCollapse();
  }

  void _scheduleCollapse() {
    _collapseTimer?.cancel();
    _collapseTimer = Timer(_expandedFor, () {
      if (mounted) setState(() => _expanded = false);
    });
  }

  void _expand() {
    setState(() => _expanded = true);
    _scheduleCollapse();
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pills = widget.pills;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: _expanded
          ? Column(
              key: const ValueKey('banner'),
              mainAxisSize: MainAxisSize.min,
              children: [if (pills.isNotEmpty) _pillRow(), _buildBanner()],
            )
          : KeyedSubtree(
              key: const ValueKey('chip'),
              child: _pillRow(chip: _buildChip()),
            ),
    );
  }

  /// Same row as the status pills elsewhere: centred and inset past the
  /// stage's corner buttons.
  Widget _pillRow({StatusPill? chip}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 84),
      child: StatusPillRow(pills: [...widget.pills, ?chip]),
    );
  }

  Widget _buildBanner() {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, widget.pills.isNotEmpty ? 8 : 40, 12, 0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _amber.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              const Icon(Icons.headset_off_rounded, color: _amber, size: 22),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Audio disconnected',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "You can't hear or be heard",
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: widget.onTurnOn,
                style: TextButton.styleFrom(
                  foregroundColor: _amber,
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Reconnect'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Same look as the Workshop / Recording pills; tapping opens the banner.
  StatusPill _buildChip() {
    return StatusPill(
      label: 'Audio off',
      color: _amber,
      icon: Icons.headset_off_rounded,
      onTap: _expand,
    );
  }
}
