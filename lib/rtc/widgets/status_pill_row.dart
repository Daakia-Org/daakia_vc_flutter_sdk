import 'package:flutter/material.dart';

/// One status in the row at the top of the stage: Lobby, Workshop, Recording,
/// Audio off.
class StatusPill {
  /// Full text, also the tooltip and screen-reader label when compact.
  final String label;
  final Color color;

  /// Null draws a glowing dot instead.
  final IconData? icon;

  /// Used instead of [icon] when compact, for a status whose full pill is only
  /// a dot and a word: a lone coloured dot can't say what it means.
  final IconData? compactIcon;

  /// Kept beside the icon when compact, e.g. the lobby count.
  final String? compactText;

  /// Null for a status that only informs; tapping it then shows [label].
  final VoidCallback? onTap;
  final bool showChevron;

  const StatusPill({
    required this.label,
    required this.color,
    this.icon,
    this.compactIcon,
    this.compactText,
    this.onTap,
    this.showChevron = false,
  });
}

/// The status pills on one line. With their labels when they fit, otherwise
/// all of them shrink to icons, so the row never grows into a second line
/// over the video. A compact pill that only informs shows its label in a
/// tooltip when tapped; one that acts (lobby, audio off) acts as it does at
/// full size.
class StatusPillRow extends StatelessWidget {
  final List<StatusPill> pills;

  const StatusPillRow({required this.pills, super.key});

  static const double _spacing = 8;
  static const TextStyle _textStyle = TextStyle(
    color: Colors.white,
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );

  @override
  Widget build(BuildContext context) {
    if (pills.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final compact =
          _fullWidth(context) > constraints.maxWidth && pills.length > 1;
      return Wrap(
        // Compact pills fit on any phone; wrapping is only the fallback for
        // something narrower still.
        alignment: WrapAlignment.center,
        spacing: _spacing,
        runSpacing: 6,
        children: [
          for (final pill in pills)
            compact ? _CompactPill(pill: pill) : _FullPill(pill: pill),
        ],
      );
    });
  }

  double _fullWidth(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    var total = _spacing * (pills.length - 1);
    for (final pill in pills) {
      final painter = TextPainter(
        text: TextSpan(text: pill.label, style: _textStyle),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      total += _FullPill.chromeWidth(pill) + painter.width;
      painter.dispose();
    }
    return total;
  }
}

class _FullPill extends StatelessWidget {
  final StatusPill pill;

  const _FullPill({required this.pill});

  /// Everything but the label: padding, border, leading icon or dot, gap and
  /// chevron.
  static double chromeWidth(StatusPill pill) =>
      24 + 2 + (pill.icon == null ? 10 + 8 : 16 + 6) +
      (pill.showChevron ? 18 : 0);

  @override
  Widget build(BuildContext context) {
    return _PillShell(
      pill: pill,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pill.icon == null) ...[
            _GlowDot(color: pill.color),
            const SizedBox(width: 8),
          ] else ...[
            Icon(pill.icon, color: pill.color, size: 16),
            const SizedBox(width: 6),
          ],
          Text(pill.label, style: StatusPillRow._textStyle),
          if (pill.showChevron)
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white70, size: 18),
        ],
      ),
    );
  }
}

class _CompactPill extends StatelessWidget {
  final StatusPill pill;

  const _CompactPill({required this.pill});

  @override
  Widget build(BuildContext context) {
    final icon = pill.compactIcon ?? pill.icon;
    final shell = _PillShell(
      pill: pill,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon == null
              ? Padding(
                  padding: const EdgeInsets.all(3),
                  child: _GlowDot(color: pill.color),
                )
              : Icon(icon, color: pill.color, size: 16),
          if (pill.compactText != null) ...[
            const SizedBox(width: 4),
            Text(pill.compactText!, style: StatusPillRow._textStyle),
          ],
        ],
      ),
    );
    return Tooltip(
      message: pill.label,
      // Tap belongs to the action when there is one.
      triggerMode: pill.onTap == null
          ? TooltipTriggerMode.tap
          : TooltipTriggerMode.longPress,
      showDuration: const Duration(seconds: 2),
      child: shell,
    );
  }
}

class _PillShell extends StatelessWidget {
  final StatusPill pill;
  final EdgeInsets padding;
  final Widget child;

  const _PillShell({
    required this.pill,
    required this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pill.color.withValues(alpha: 0.5)),
      ),
      child: child,
    );
    return Semantics(
      label: pill.label,
      button: pill.onTap != null,
      excludeSemantics: true,
      child: pill.onTap == null
          ? body
          : GestureDetector(
              onTap: pill.onTap,
              behavior: HitTestBehavior.opaque,
              child: body,
            ),
    );
  }
}

class _GlowDot extends StatelessWidget {
  final Color color;

  const _GlowDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.7),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}
