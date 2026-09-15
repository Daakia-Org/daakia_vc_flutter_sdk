import 'dart:async';
import 'package:flutter/material.dart';

class RoomNotification extends StatefulWidget {
  const RoomNotification({super.key});

  @override
  State<RoomNotification> createState() => RoomNotificationState();
}

class RoomNotificationState extends State<RoomNotification>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  String? _message;
  String? _actionText;
  VoidCallback? _actionCallback;
  VoidCallback? _onDismiss;
  Timer? _dismissTimer;
  String? _lastMessage;
  DateTime? _lastShownAt;

  // Same message within this window is silently dropped to prevent storms.
  static const _dedupeWindow = Duration(seconds: 2);
  static const _displayDuration = Duration(milliseconds: 2500);
  static const _animDuration = Duration(milliseconds: 280);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: _animDuration);
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _notifyDismissed();
    _animController.dispose();
    super.dispose();
  }

  /// [duration] overrides [_displayDuration] for a notice that needs longer on
  /// screen than a routine one — a couple of sentences the user has to act on
  /// can't be read in the default 2.5s.
  ///
  /// [onDismiss] fires once the notice goes away, however it goes away — timed
  /// out, closed by the user, or replaced by the next one. Used by notices that
  /// are paired with something else, such as a sound that has to stop the
  /// moment the message does.
  void show({
    required String message,
    String? actionText,
    VoidCallback? actionCallback,
    Duration? duration,
    VoidCallback? onDismiss,
  }) {
    if (!mounted) return;

    final now = DateTime.now();
    if (_lastMessage == message &&
        _lastShownAt != null &&
        now.difference(_lastShownAt!) < _dedupeWindow) {
      return;
    }
    _lastMessage = message;
    _lastShownAt = now;

    _dismissTimer?.cancel();
    // The outgoing notice never gets to finish, so settle its pairing now.
    _notifyDismissed();
    setState(() {
      _message = message;
      _actionText = actionText;
      _actionCallback = actionCallback;
      _onDismiss = onDismiss;
    });
    _animController.forward(from: 0);
    _dismissTimer = Timer(duration ?? _displayDuration, _dismiss);
  }

  void _dismiss() {
    _dismissTimer?.cancel();
    _notifyDismissed();
    _animController.reverse().then((_) {
      if (mounted) setState(() => _message = null);
    });
  }

  /// Runs the pairing callback exactly once, so a user-dismiss followed by the
  /// timer (or vice versa) doesn't fire it twice.
  void _notifyDismissed() {
    final callback = _onDismiss;
    _onDismiss = null;
    callback?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_message == null) return const SizedBox.shrink();

    final topPad = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.only(top: topPad + 12, left: 16, right: 16),
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xF01C1C2E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _message!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_actionText != null && _actionText!.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () {
                        _actionCallback?.call();
                        _dismiss();
                      },
                      child: const Text(
                        'Open',
                        style: TextStyle(
                          color: Color(0xFF64B5F6),
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _dismiss,
                    child: const Icon(Icons.close, color: Colors.white38, size: 15),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
