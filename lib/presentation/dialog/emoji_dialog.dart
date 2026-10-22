import 'dart:async';

import 'package:animated_emoji/emoji.dart';
import 'package:animated_emoji/emoji_data.dart';
import 'package:animated_emoji/emojis.g.dart';
import 'package:daakia_vc_flutter_sdk/viewmodel/rtc_viewmodel.dart';
import 'package:flutter/material.dart';

import '../../events/rtc_events.dart';
import '../../model/action_model.dart';
import '../../utils/meeting_actions.dart';

class EmojiDialog extends StatefulWidget {
  const EmojiDialog(this.viewModel, {super.key});

  final RtcViewmodel viewModel;

  @override
  State<StatefulWidget> createState() => _EmojiDialogState();
}

class _EmojiDialogState extends State<EmojiDialog>
    with TickerProviderStateMixin {
  final List<AnimationController> _controllers = [];
  final List<Animation<Offset>> _slideAnimations = [];
  final List<bool> _isVisible = [false, false, false, false, false];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startStaggeredAnimation();
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _initializeAnimations() {
    for (int i = 0; i < 5; i++) {
      final controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 150),
      );
      _controllers.add(controller);

      final animation = Tween<Offset>(
        begin: const Offset(0, 1), // Starts off-screen at the bottom
        end: Offset.zero, // Ends at its final position
      ).animate(CurvedAnimation(
        parent: controller,
        curve: Curves.easeOut,
      ));
      _slideAnimations.add(animation);

      // Explicitly set the controller value to 0
      controller.value = 0.0;
    }
  }

  void _startStaggeredAnimation() {
    Future.delayed(const Duration(milliseconds: 50), () {
      // Small delay to ensure everything is initialized
      for (int i = 0; i < _controllers.length; i++) {
        Future.delayed(Duration(milliseconds: i * 100), () {
          if (mounted) {
            setState(() {
              _isVisible[i] = true; // Make the emoji visible
            });
            _controllers[i].forward(); // Start the animation
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(30),
      ),
      backgroundColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildIcon(context, AnimatedEmojis.redHeart, 0, MeetingActions.heart),
                _buildIcon(context, AnimatedEmojis.blush, 1, MeetingActions.blush),
                _buildIcon(context, AnimatedEmojis.clap, 2, MeetingActions.clap),
                _buildIcon(context, AnimatedEmojis.smile, 3, MeetingActions.smile),
                _buildIcon(context, AnimatedEmojis.thumbsUp, 4, MeetingActions.thumbsUp),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(BuildContext context, AnimatedEmojiData emojiAsset,
      int index, String action) {
    // Fixed-size slot rather than Expanded: the dialog's minimum width (and the
    // full landscape width) would otherwise be shared out between the five
    // emojis, leaving wide gaps between them.
    return SizedBox.square(
      dimension: 48,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop(); // Dismiss dialog on tap
          }
          widget.viewModel.sendAction(ActionModel(action: action));
          widget.viewModel.sendEvent(ShowReaction(action));
        },
        child: Center(
          child: Visibility(
            visible: _isVisible[index], // Toggle visibility
            child: SlideTransition(
              position: _slideAnimations[index],
              child: AnimatedEmoji(
                emojiAsset,
                size: 30,
                animate: _isVisible[index],
                repeat: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
