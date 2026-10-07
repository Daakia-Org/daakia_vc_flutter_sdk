import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WhiteBoardWidget extends StatelessWidget {
  final WebViewController controller;

  const WhiteBoardWidget({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 10,
      color: Colors.grey.shade200,
      clipBehavior: Clip.antiAliasWithSaveLayer,
      // Users with edit rights draw, pan and pinch on the board, so the page
      // must get every touch first rather than lose drags to Flutter.
      child: WebViewWidget(
        controller: controller,
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(
              () => EagerGestureRecognizer()),
        },
      ),
    );
  }
}
