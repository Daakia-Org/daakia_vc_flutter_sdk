import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Lets a lazily built chat list scroll to a message by id.
///
/// Messages have different heights, so an offset can't be computed from the
/// index. Each built row registers itself here; [scrollTo] pages through the
/// list until the target row is built, then brings it into view.
class ChatScrollTargets {
  final Map<String, _ChatScrollTargetState> _rows = {};

  /// Wraps a message row so [scrollTo] can find it. [index] is the row's
  /// position in the ListView (0 = the row nearest the scroll origin).
  Widget wrap({
    required String? id,
    required int index,
    required Widget child,
  }) {
    if (id == null || id.isEmpty) return child;
    return _ChatScrollTarget(targets: this, id: id, index: index, child: child);
  }

  /// Scrolls [controller] until the row for [id] at list [index] is on
  /// screen, centred where possible.
  Future<void> scrollTo(
    ScrollController controller, {
    required String id,
    required int index,
  }) async {
    // Each step moves most of a screen, so this covers very long chats while
    // still giving up if the row never appears.
    for (var step = 0; step < 200; step++) {
      final target = _rows[id];
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(
          target.context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        return;
      }
      if (!controller.hasClients) return;

      final built = _rows.values.where((r) => r.mounted).map((r) => r.index);
      if (built.isEmpty) return;
      final position = controller.position;
      final delta = position.viewportDimension * 0.8;
      final next = index > built.reduce(math.max)
          ? position.pixels + delta
          : position.pixels - delta;
      final clamped = next.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (clamped == position.pixels) return;
      controller.jumpTo(clamped);
      await WidgetsBinding.instance.endOfFrame;
    }
  }
}

class _ChatScrollTarget extends StatefulWidget {
  final ChatScrollTargets targets;
  final String id;
  final int index;
  final Widget child;

  const _ChatScrollTarget({
    required this.targets,
    required this.id,
    required this.index,
    required this.child,
  });

  @override
  State<_ChatScrollTarget> createState() => _ChatScrollTargetState();
}

class _ChatScrollTargetState extends State<_ChatScrollTarget> {
  int get index => widget.index;

  @override
  void initState() {
    super.initState();
    widget.targets._rows[widget.id] = this;
  }

  @override
  void didUpdateWidget(_ChatScrollTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _unregister(oldWidget.id);
      widget.targets._rows[widget.id] = this;
    }
  }

  @override
  void dispose() {
    _unregister(widget.id);
    super.dispose();
  }

  void _unregister(String id) {
    if (identical(widget.targets._rows[id], this)) {
      widget.targets._rows.remove(id);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
