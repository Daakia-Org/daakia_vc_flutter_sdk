import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WhiteBoardWidget extends StatelessWidget {
  final WebViewController controller;

  /// Closes the whiteboard for everyone. Null hides the close button, for
  /// users who aren't allowed to manage the whiteboard.
  final VoidCallback? onClose;

  /// Disables the close button while an open/close request is in flight.
  final bool isClosing;

  const WhiteBoardWidget({
    required this.controller,
    this.onClose,
    this.isClosing = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 10,
      color: Colors.grey.shade200,
      clipBehavior: Clip.antiAliasWithSaveLayer,
      child: Column(
        children: [
          // A strip of its own rather than a button floating on the board: on
          // phones the board's toolbar spans the whole top edge, so anything
          // laid over it would cover one of its tools.
          if (onClose != null)
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Whiteboard',
                      style: TextStyle(
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close whiteboard',
                    icon: const Icon(Icons.close),
                    color: Colors.grey.shade800,
                    onPressed: isClosing ? null : onClose,
                  ),
                ],
              ),
            ),
          // Users with edit rights draw, pan and pinch on the board, so the
          // page must get every touch first rather than lose drags to Flutter.
          Expanded(
            child: WebViewWidget(
              controller: controller,
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<OneSequenceGestureRecognizer>(
                    () => EagerGestureRecognizer()),
              },
            ),
          ),
        ],
      ),
    );
  }
}
